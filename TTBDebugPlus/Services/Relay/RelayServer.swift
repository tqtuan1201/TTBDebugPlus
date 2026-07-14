//
//  RelayServer.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-07-13.
//  Phase 3: relay mode — a dumb pipe that lets iOS devices and macOS viewers find each other
//  without sharing a LAN. Accepts connections from iOS "producers" (identical device_info
//  handshake as the local WebSocketServer) and macOS "viewers" (Relay Client instances,
//  identified by relay_client_hello), then forwards producer frames to every viewer (stamping
//  sourceDeviceId, since a single viewer connection multiplexes many devices) and viewer
//  frames to every producer. See plans/2026-07-13-connection-reliability/phase-03-relay-mode-design.md
//  for the full design rationale (v1 has no per-command device targeting; no auth).
//

import Foundation
import Network

// MARK: - Relay Server Status (published to main for UI)

@Observable
final class RelayServerStatus {
    var isRunning = false
    var port: UInt16?
    var producerCount = 0
    var viewerCount = 0
    var lastError: String?
}

// MARK: - Relay Server

final class RelayServer {

    private let queue = DispatchQueue(label: "com.ttbdebug.relayserver", qos: .utility)
    private var listener: NWListener?
    private var generation: UInt64 = 0

    let status = RelayServerStatus()

    // MARK: - Callbacks (always called on main thread) — same shape as WebSocketServer's.
    // Phase 4: lets this Mac be both the relay AND its own viewer with zero extra hop — a
    // producer's frame is still forwarded to remote viewers via `forward()`, but is now also
    // decoded and dispatched locally via `dispatchLocally()`, instead of requiring a loopback
    // RelayClient pointed at 127.0.0.1 just to see your own relay's traffic.

    var onDeviceConnected:       ((String, DeviceInfoPayload) -> Void)?
    var onDeviceDisconnected:    ((String, String) -> Void)?
    var onAPILog:                ((String, APILogPayload) -> Void)?
    var onConsoleLog:            ((String, ConsoleLogPayload) -> Void)?
    var onHeartbeat:             ((String) -> Void)?
    var onScreenshot:            ((String, ScreenshotResponsePayload) -> Void)?
    var onPerformanceMetrics:    ((String, PerformanceMetricsPayload) -> Void)?
    var onConnectionDiagnostics: ((String, ConnectionDiagnosticsPayload) -> Void)?

    // MARK: - Connection roles (queue-only)

    private enum Role {
        case pending
        case producer(deviceId: String)
        case viewer
    }

    private struct ConnState {
        let connection: NWConnection
        var role: Role
    }

    /// endpointId → state, for both producers and viewers once classified.
    private var connections: [String: ConnState] = [:]
    private var receivingEndpoints: Set<String> = []

    // MARK: - Start / Stop

    func start(port: UInt16) {
        queue.async { [weak self] in
            self?.startOnQueue(port: port)
        }
    }

    private func startOnQueue(port: UInt16) {
        stopOnQueue()
        generation &+= 1
        let currentGeneration = generation

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            DispatchQueue.main.async { [weak self] in self?.status.lastError = "Invalid port \(port)" }
            return
        }

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 3
        tcp.keepaliveCount = 5
        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: params, on: nwPort)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status.lastError = "Failed to start: \(error.localizedDescription)"
                self?.status.isRunning = false
            }
            return
        }

        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                guard self.generation == currentGeneration else { return }
                switch state {
                case .ready:
                    DispatchQueue.main.async { [weak self] in
                        self?.status.isRunning = true
                        self?.status.port = port
                        self?.status.lastError = nil
                    }
                    print("[TTBDebug] 🔀 Relay Server listening on port \(port)")
                case .failed(let error):
                    DispatchQueue.main.async { [weak self] in
                        self?.status.isRunning = false
                        self?.status.lastError = error.localizedDescription
                    }
                    print("[TTBDebug] ❌ Relay Server failed: \(error)")
                case .cancelled:
                    DispatchQueue.main.async { [weak self] in self?.status.isRunning = false }
                default:
                    break
                }
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        newListener.start(queue: queue)
        listener = newListener
    }

    func stop() {
        queue.async { [weak self] in self?.stopOnQueue() }
    }

    private func stopOnQueue() {
        generation &+= 1
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for (_, state) in connections {
            state.connection.stateUpdateHandler = nil
            state.connection.cancel()
        }
        connections.removeAll()
        receivingEndpoints.removeAll()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.status.isRunning = false
            self.status.port = nil
            self.status.producerCount = 0
            self.status.viewerCount = 0
        }
    }

    // MARK: - New Connection (queue)

    private func handleNewConnection(_ connection: NWConnection) {
        let endpointId = "\(connection.endpoint)#\(ObjectIdentifier(connection))"
        queue.async { [weak self] in
            guard let self else { return }
            self.connections[endpointId] = ConnState(connection: connection, role: .pending)

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                self.queue.async {
                    switch state {
                    case .ready:
                        if self.receivingEndpoints.insert(endpointId).inserted {
                            self.receiveLoop(endpointId: endpointId, connection: connection)
                        }
                    case .failed, .cancelled:
                        self.handleDisconnection(endpointId: endpointId)
                    default:
                        break
                    }
                }
            }
            connection.start(queue: self.queue)
        }
    }

    // MARK: - Length-Prefixed Receive (queue)

    private func receiveLoop(endpointId: String, connection: NWConnection) {
        guard connections[endpointId]?.connection === connection else {
            receivingEndpoints.remove(endpointId)
            return
        }
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            guard self.connections[endpointId]?.connection === connection else {
                self.receivingEndpoints.remove(endpointId)
                return
            }
            if error != nil {
                self.handleDisconnection(endpointId: endpointId)
                return
            }
            guard let header, header.count == 4 else {
                if isComplete {
                    self.handleDisconnection(endpointId: endpointId)
                } else {
                    self.receiveLoop(endpointId: endpointId, connection: connection)
                }
                return
            }
            let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 10_000_000 else {
                self.handleDisconnection(endpointId: endpointId)
                return
            }
            self.receiveBody(endpointId: endpointId, connection: connection, needed: Int(length), accumulated: Data())
        }
    }

    private func receiveBody(endpointId: String, connection: NWConnection, needed: Int, accumulated: Data) {
        let remaining = needed - accumulated.count
        guard remaining > 0 else {
            processFrame(accumulated, endpointId: endpointId)
            receiveLoop(endpointId: endpointId, connection: connection)
            return
        }
        guard connections[endpointId]?.connection === connection else {
            receivingEndpoints.remove(endpointId)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] body, _, isComplete, error in
            guard let self else { return }
            guard self.connections[endpointId]?.connection === connection else {
                self.receivingEndpoints.remove(endpointId)
                return
            }
            if error != nil {
                self.handleDisconnection(endpointId: endpointId)
                return
            }
            guard let chunk = body, !chunk.isEmpty else {
                if isComplete {
                    self.handleDisconnection(endpointId: endpointId)
                } else {
                    self.receiveBody(endpointId: endpointId, connection: connection, needed: needed, accumulated: accumulated)
                }
                return
            }
            var next = accumulated
            next.append(chunk)
            self.receiveBody(endpointId: endpointId, connection: connection, needed: needed, accumulated: next)
        }
    }

    // MARK: - Frame Processing / Role Classification / Forwarding (queue)

    private func processFrame(_ data: Data, endpointId: String) {
        guard var message = DebugMessage.from(data: data) else {
            print("[TTBDebug] ⚠️ Relay: failed to decode frame (\(data.count) bytes) from \(endpointId)")
            return
        }
        guard var state = connections[endpointId] else { return }

        switch state.role {
        case .pending:
            // First message determines the role for this connection's whole lifetime.
            if message.type == .relayClientHello {
                state.role = .viewer
                connections[endpointId] = state
                updateStatusCounts()
                print("[TTBDebug] 👁 Relay: viewer connected (\(endpointId))")
            } else if message.type == .deviceInfo, let info = message.decodePayload(DeviceInfoPayload.self) {
                state.role = .producer(deviceId: info.deviceId)
                connections[endpointId] = state
                updateStatusCounts()
                print("[TTBDebug] 📱 Relay: producer identified — \(info.deviceName) (\(info.deviceId))")
                message.sourceDeviceId = info.deviceId
                forward(message, toRole: .viewer)
                dispatchLocally(message, deviceId: info.deviceId)
            } else {
                print("[TTBDebug] ⚠️ Relay: dropping unclassifiable first message (\(message.type.rawValue)) from \(endpointId)")
            }

        case .producer(let deviceId):
            message.sourceDeviceId = deviceId
            forward(message, toRole: .viewer)
            dispatchLocally(message, deviceId: deviceId)

        case .viewer:
            // v1: no per-device targeting for *remote* viewers — broadcasts to every producer.
            // (This Mac's own local view uses `sendToProducer`, which targets precisely.)
            forward(message, toRole: .producer(deviceId: ""))
        }
    }

    // MARK: - Local Dispatch (queue → main)

    /// Decodes a producer's message and fires the matching callback directly — this Mac's own
    /// view of its own relay. Mirrors `RelayClient.processFrame`'s switch, but there's no
    /// separate connection to receive from: this runs on the same frame `forward()` just
    /// re-transmitted to remote viewers.
    private func dispatchLocally(_ message: DebugMessage, deviceId: String) {
        switch message.type {
        case .deviceInfo:
            guard let info = message.decodePayload(DeviceInfoPayload.self) else { return }
            DispatchQueue.main.async { [weak self] in self?.onDeviceConnected?(deviceId, info) }
        case .apiLog:
            guard let log = message.decodePayload(APILogPayload.self) else { return }
            DispatchQueue.main.async { [weak self] in self?.onAPILog?(deviceId, log) }
        case .consoleLog:
            guard let log = message.decodePayload(ConsoleLogPayload.self) else { return }
            DispatchQueue.main.async { [weak self] in self?.onConsoleLog?(deviceId, log) }
        case .heartbeat:
            DispatchQueue.main.async { [weak self] in self?.onHeartbeat?(deviceId) }
        case .screenshotResponse:
            guard let ss = message.decodePayload(ScreenshotResponsePayload.self) else { return }
            DispatchQueue.main.async { [weak self] in self?.onScreenshot?(deviceId, ss) }
        case .performanceMetrics:
            guard let m = message.decodePayload(PerformanceMetricsPayload.self) else { return }
            DispatchQueue.main.async { [weak self] in self?.onPerformanceMetrics?(deviceId, m) }
        case .connectionDiagnostics:
            guard let d = message.decodePayload(ConnectionDiagnosticsPayload.self) else { return }
            DispatchQueue.main.async { [weak self] in self?.onConnectionDiagnostics?(deviceId, d) }
        default:
            break
        }
    }

    /// Sends a command (screenshot request, app command) to one specific producer by deviceId.
    /// Unlike the general `forward()` path used for *remote* viewers (v1: broadcast, no
    /// targeting — see design doc §2), this Mac can target precisely because it holds each
    /// producer's actual `NWConnection` directly.
    func sendToProducer(deviceId: String, message: DebugMessage) {
        queue.async { [weak self] in
            guard let self, let data = message.toData() else { return }
            var length = UInt32(data.count).bigEndian
            var frame = Data(bytes: &length, count: 4)
            frame.append(data)
            for state in self.connections.values {
                if case .producer(let id) = state.role, id == deviceId {
                    state.connection.send(content: frame, completion: .contentProcessed { _ in })
                }
            }
        }
    }

    /// Forwards to every connection currently in the given role. `toRole`'s associated value
    /// (if any) is ignored for matching — only the case matters, since v1 has no per-device
    /// routing.
    private func forward(_ message: DebugMessage, toRole matchRole: Role) {
        guard let data = message.toData() else { return }
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)

        let targets = connections.values.compactMap { state -> NWConnection? in
            switch (state.role, matchRole) {
            case (.viewer, .viewer): return state.connection
            case (.producer, .producer): return state.connection
            default: return nil
            }
        }
        for target in targets {
            target.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    private func updateStatusCounts() {
        let producers = connections.values.filter { if case .producer = $0.role { return true }; return false }.count
        let viewers = connections.values.filter { if case .viewer = $0.role { return true }; return false }.count
        DispatchQueue.main.async { [weak self] in
            self?.status.producerCount = producers
            self?.status.viewerCount = viewers
        }
    }

    // MARK: - Disconnection (queue)

    private func handleDisconnection(endpointId: String) {
        receivingEndpoints.remove(endpointId)
        guard let state = connections.removeValue(forKey: endpointId) else { return }
        state.connection.stateUpdateHandler = nil
        state.connection.cancel()
        updateStatusCounts()

        if case .producer(let deviceId) = state.role {
            print("[TTBDebug] 📱 Relay: producer disconnected — \(deviceId)")
            DispatchQueue.main.async { [weak self] in
                self?.onDeviceDisconnected?(deviceId, "relay: producer disconnected")
            }
            guard var notice = DebugMessage.create(
                type: .disconnect,
                payload: RelayDisconnectPayload(reason: "producer disconnected")
            ) else { return }
            notice.sourceDeviceId = deviceId
            forward(notice, toRole: .viewer)
        } else if case .viewer = state.role {
            print("[TTBDebug] 👁 Relay: viewer disconnected (\(endpointId))")
        }
    }

    deinit { stop() }
}
