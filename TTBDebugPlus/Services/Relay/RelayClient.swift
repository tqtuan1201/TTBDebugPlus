//
//  RelayClient.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-07-13.
//  Phase 3: relay mode — the macOS-side counterpart to TTDebugBridge's outbound-connect logic.
//  Connects out to a configured Relay Server, sends relay_client_hello first, then decodes
//  forwarded producer frames (each stamped with sourceDeviceId, since one shared connection
//  multiplexes every relayed device) and drives the same callback surface WebSocketServer
//  exposes, so ConnectionManager doesn't need to know or care whether a device's data came in
//  locally or via relay. See plans/2026-07-13-connection-reliability/phase-03-relay-mode-design.md.
//

import Foundation
import Network

// MARK: - Relay Client Status

@Observable
final class RelayClientStatus {
    var isConnected = false
    var lastError: String?
}

// MARK: - Relay Client

final class RelayClient {

    private let queue = DispatchQueue(label: "com.ttbdebug.relayclient", qos: .utility)
    private var connection: NWConnection?
    private var generation: UInt64 = 0
    private var reconnectAttempt = 0
    private var isEnabled = false
    private var host = ""
    private var port: UInt16 = 0
    private var knownDeviceIds: Set<String> = []

    let status = RelayClientStatus()

    // MARK: - Callbacks (always called on main thread) — same shape as WebSocketServer's.

    var onDeviceConnected:       ((String, DeviceInfoPayload) -> Void)?
    var onDeviceDisconnected:    ((String, String) -> Void)?
    var onAPILog:                ((String, APILogPayload) -> Void)?
    var onConsoleLog:            ((String, ConsoleLogPayload) -> Void)?
    var onHeartbeat:             ((String) -> Void)?
    var onScreenshot:            ((String, ScreenshotResponsePayload) -> Void)?
    var onPerformanceMetrics:    ((String, PerformanceMetricsPayload) -> Void)?
    var onConnectionDiagnostics: ((String, ConnectionDiagnosticsPayload) -> Void)?

    // MARK: - Start / Stop

    func start(host: String, port: UInt16) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isEnabled = true
            self.host = host
            self.port = port
            self.reconnectAttempt = 0
            self.connectOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isEnabled = false
            self.generation &+= 1
            self.connection?.stateUpdateHandler = nil
            self.connection?.cancel()
            self.connection = nil
            self.notifyAllKnownDevicesOffline(reason: "relay client stopped")
            DispatchQueue.main.async { [weak self] in self?.status.isConnected = false }
        }
    }

    /// Sends an outbound message (e.g. a screenshot request) via the relay. v1: no per-device
    /// targeting — the Relay Server broadcasts to all connected producers. See design doc.
    func send(_ message: DebugMessage) {
        queue.async { [weak self] in
            guard let self, let conn = self.connection, let data = message.toData() else { return }
            self.sendFrame(data, on: conn)
        }
    }

    // MARK: - Connect (queue)

    private func connectOnQueue() {
        guard isEnabled else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port), !host.isEmpty else {
            DispatchQueue.main.async { [weak self] in self?.status.lastError = "Invalid relay address" }
            return
        }

        generation &+= 1
        let currentGeneration = generation

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 3
        tcp.keepaliveCount = 5
        tcp.connectionTimeout = 10
        let params = NWParameters(tls: nil, tcp: tcp)

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                guard self.generation == currentGeneration else { return }
                switch state {
                case .ready:
                    self.reconnectAttempt = 0
                    DispatchQueue.main.async { [weak self] in
                        self?.status.isConnected = true
                        self?.status.lastError = nil
                    }
                    print("[TTBDebug] 🔀 Relay Client connected to \(self.host):\(self.port)")
                    self.sendHello(on: conn)
                    self.receiveLoop(connection: conn, generation: currentGeneration)
                case .waiting(let error):
                    DispatchQueue.main.async { [weak self] in self?.status.lastError = "\(error)" }
                case .failed(let error):
                    DispatchQueue.main.async { [weak self] in
                        self?.status.isConnected = false
                        self?.status.lastError = error.localizedDescription
                    }
                    self.teardownAndScheduleReconnect(generation: currentGeneration)
                case .cancelled:
                    DispatchQueue.main.async { [weak self] in self?.status.isConnected = false }
                default:
                    break
                }
            }
        }

        conn.start(queue: queue)
    }

    private func teardownAndScheduleReconnect(generation: UInt64) {
        guard self.generation == generation, isEnabled else { return }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        notifyAllKnownDevicesOffline(reason: "relay connection lost")

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        print("[TTBDebug] 🔀 Relay Client reconnecting in \(delay)s (attempt \(reconnectAttempt))...")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isEnabled, self.generation == generation else { return }
            self.connectOnQueue()
        }
    }

    private func notifyAllKnownDevicesOffline(reason: String) {
        guard !knownDeviceIds.isEmpty else { return }
        let ids = knownDeviceIds
        knownDeviceIds.removeAll()
        DispatchQueue.main.async { [weak self] in
            for id in ids { self?.onDeviceDisconnected?(id, reason) }
        }
    }

    // MARK: - Handshake / Framing (queue)

    private func sendHello(on connection: NWConnection) {
        let name = Host.current().localizedName ?? "Mac"
        guard let msg = DebugMessage.create(type: .relayClientHello, payload: RelayClientHelloPayload(viewerName: name)),
              let data = msg.toData() else { return }
        sendFrame(data, on: connection)
    }

    private func sendFrame(_ data: Data, on connection: NWConnection) {
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: - Length-Prefixed Receive (queue)

    private func receiveLoop(connection: NWConnection, generation: UInt64) {
        guard self.connection === connection, self.generation == generation else { return }
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, isComplete, error in
            guard let self, self.connection === connection, self.generation == generation else { return }
            if error != nil {
                self.teardownAndScheduleReconnect(generation: generation)
                return
            }
            guard let header, header.count == 4 else {
                if isComplete {
                    self.teardownAndScheduleReconnect(generation: generation)
                } else {
                    self.receiveLoop(connection: connection, generation: generation)
                }
                return
            }
            let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 10_000_000 else {
                self.teardownAndScheduleReconnect(generation: generation)
                return
            }
            self.receiveBody(connection: connection, generation: generation, needed: Int(length), accumulated: Data())
        }
    }

    private func receiveBody(connection: NWConnection, generation: UInt64, needed: Int, accumulated: Data) {
        let remaining = needed - accumulated.count
        guard remaining > 0 else {
            processFrame(accumulated)
            receiveLoop(connection: connection, generation: generation)
            return
        }
        guard self.connection === connection, self.generation == generation else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] body, _, isComplete, error in
            guard let self, self.connection === connection, self.generation == generation else { return }
            if error != nil {
                self.teardownAndScheduleReconnect(generation: generation)
                return
            }
            guard let chunk = body, !chunk.isEmpty else {
                if isComplete {
                    self.teardownAndScheduleReconnect(generation: generation)
                } else {
                    self.receiveBody(connection: connection, generation: generation, needed: needed, accumulated: accumulated)
                }
                return
            }
            var next = accumulated
            next.append(chunk)
            self.receiveBody(connection: connection, generation: generation, needed: needed, accumulated: next)
        }
    }

    // MARK: - Frame Processing (queue)

    private func processFrame(_ data: Data) {
        guard let message = DebugMessage.from(data: data) else {
            print("[TTBDebug] ⚠️ Relay Client: failed to decode forwarded frame (\(data.count) bytes)")
            return
        }

        // device_info carries the id in its own payload even before sourceDeviceId is stamped
        // on later messages for that device.
        guard let deviceId = message.sourceDeviceId ?? decodedDeviceInfoId(from: message) else {
            print("[TTBDebug] ⚠️ Relay Client: dropping \(message.type.rawValue) with no attributable device")
            return
        }

        switch message.type {
        case .deviceInfo:
            guard let info = message.decodePayload(DeviceInfoPayload.self) else { return }
            let isNew = knownDeviceIds.insert(info.deviceId).inserted
            DispatchQueue.main.async { [weak self] in self?.onDeviceConnected?(info.deviceId, info) }
            if isNew { print("[TTBDebug] 📱 Relay Client: device online via relay — \(info.deviceName)") }

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

        case .disconnect:
            knownDeviceIds.remove(deviceId)
            DispatchQueue.main.async { [weak self] in self?.onDeviceDisconnected?(deviceId, "relay: producer disconnected") }

        default:
            break
        }
    }

    private func decodedDeviceInfoId(from message: DebugMessage) -> String? {
        guard message.type == .deviceInfo else { return nil }
        return message.decodePayload(DeviceInfoPayload.self)?.deviceId
    }

    deinit { stop() }
}
