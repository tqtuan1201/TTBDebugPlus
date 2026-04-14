//
//  WebSocketServer.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Handles TCP connections from iOS devices using length-prefixed framing.
//  Updated 2026-04-09: TCP keep-alive, stale-disconnect guard, diagnostic logging.
//

import Foundation
import Network

// MARK: - WebSocket Server

/// Manages TCP connections from iOS devices.
/// Uses 4-byte big-endian length-prefixed framing for message exchange.
final class WebSocketServer {

    private let queue = DispatchQueue(label: "com.ttbdebug.websocket", qos: .userInitiated)

    // MARK: - Callbacks (always called on main thread)

    var onDeviceConnected:       ((String, NWConnection, DeviceInfoPayload) -> Void)?
    var onDeviceDisconnected:    ((String) -> Void)?
    var onAPILog:                ((String, APILogPayload) -> Void)?
    var onConsoleLog:            ((String, ConsoleLogPayload) -> Void)?
    var onHeartbeat:             ((String) -> Void)?
    var onScreenshot:            ((String, ScreenshotResponsePayload) -> Void)?
    var onPerformanceMetrics:    ((String, PerformanceMetricsPayload) -> Void)?
    var onConnectionDiagnostics: ((String, ConnectionDiagnosticsPayload) -> Void)?

    // MARK: - Connection State (access ONLY on `queue`)

    /// endpointId → NWConnection (before & after handshake)
    private var pendingConnections: [String: NWConnection] = [:]

    /// endpointId → deviceId (set after handshake)
    private var identifiedConnections: [String: String] = [:]

    /// deviceId → endpointId — tracks which endpoint is the LIVE (current) connection.
    ///
    /// Solves the "ghost disconnect" bug:
    /// When iOS crashes, the old NWConnection eventually fires .failed seconds later.
    /// By that time the device may have reconnected on a NEW endpoint.
    /// We compare the disconnecting endpoint vs. liveEndpoint[deviceId]:
    ///   match  → device truly offline → notify macOS
    ///   differ → reconnected already  → ignore stale callback
    private var liveEndpoint: [String: String] = [:]

    // MARK: - Diagnostics

    /// Total accepted connection count (monotonic, for logging)
    private var connectionCounter: Int = 0

    // MARK: - Handle New Connection (called from Bonjour advertiser queue)

    func handleNewConnection(_ connection: NWConnection) {
        let endpointId = "\(connection.endpoint)"

        queue.async { [weak self] in
            guard let self else { return }
            self.connectionCounter += 1
            let connNum = self.connectionCounter
            print("[TTBDebug] 📲 [\(connNum)] Incoming TCP connection from: \(endpointId)")

            self.pendingConnections[endpointId] = connection

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                self.queue.async {
                    self.handleConnectionState(state, endpointId: endpointId,
                                               connection: connection, connNum: connNum)
                }
            }

            // NWConnection inherits TCP keepalive from NWListener params.
            // No need to set keepalive here — it was configured on the listener.
            connection.start(queue: self.queue)
        }
    }

    // MARK: - Connection State Machine (runs on `queue`)

    private func handleConnectionState(_ state: NWConnection.State,
                                       endpointId: String,
                                       connection: NWConnection,
                                       connNum: Int) {
        switch state {
        case .setup:
            print("[TTBDebug] ⚙️ [\(connNum)] TCP setup: \(endpointId)")

        case .preparing:
            print("[TTBDebug] 🔧 [\(connNum)] TCP preparing: \(endpointId)")

        case .ready:
            print("[TTBDebug] ✅ [\(connNum)] TCP ready: \(endpointId) — starting receive loop")
            receiveLoop(from: connection, endpointId: endpointId, connNum: connNum)

        case .waiting(let error):
            print("[TTBDebug] ⏳ [\(connNum)] TCP waiting: \(endpointId) — \(error.localizedDescription)")

        case .failed(let error):
            print("[TTBDebug] ❌ [\(connNum)] TCP failed: \(endpointId) — \(error.localizedDescription)")
            handleDisconnection(endpointId: endpointId, reason: "failed: \(error.localizedDescription)")

        case .cancelled:
            print("[TTBDebug] ⏹ [\(connNum)] TCP cancelled: \(endpointId)")
            handleDisconnection(endpointId: endpointId, reason: "cancelled")

        @unknown default:
            print("[TTBDebug] ❓ [\(connNum)] TCP unknown state: \(endpointId)")
        }
    }

    // MARK: - Length-Prefixed Receive (runs on `queue`)

    private func receiveLoop(from connection: NWConnection, endpointId: String, connNum: Int) {
        // Guard: only read if the connection is still tracked
        guard pendingConnections[endpointId] != nil else {
            print("[TTBDebug] 🔕 [\(connNum)] receiveLoop: endpoint \(endpointId) no longer tracked — stopping")
            return
        }

        // Read 4-byte big-endian length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("[TTBDebug] ❌ [\(connNum)] Header read error from \(endpointId): \(error.localizedDescription)")
                self.handleDisconnection(endpointId: endpointId, reason: "header read error")
                return
            }

            guard let header, header.count == 4 else {
                if isComplete {
                    print("[TTBDebug] 🔌 [\(connNum)] TCP connection closed gracefully: \(endpointId) (isComplete=true, header=\(header?.count ?? 0) bytes)")
                    self.handleDisconnection(endpointId: endpointId, reason: "graceful close (isComplete)")
                } else {
                    // Empty partial data — keep waiting
                    self.receiveLoop(from: connection, endpointId: endpointId, connNum: connNum)
                }
                return
            }

            let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 10_000_000 else {
                // Log first few bytes for protocol mismatch diagnosis
                let hex = header.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("[TTBDebug] ❌ [\(connNum)] Invalid message length (\(length)) from \(endpointId) — raw header: [\(hex)] — closing")
                self.handleDisconnection(endpointId: endpointId, reason: "invalid length \(length)")
                return
            }

            self.receiveBody(from: connection, endpointId: endpointId, connNum: connNum,
                             needed: Int(length), accumulated: Data())
        }
    }

    /// Recursively accumulate TCP body bytes until exactly `needed` bytes are received.
    private func receiveBody(from connection: NWConnection,
                             endpointId: String,
                             connNum: Int,
                             needed: Int,
                             accumulated: Data) {
        let remaining = needed - accumulated.count
        guard remaining > 0 else {
            processMessage(accumulated, endpointId: endpointId, connection: connection, connNum: connNum)
            receiveLoop(from: connection, endpointId: endpointId, connNum: connNum)
            return
        }

        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: remaining) { [weak self] body, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("[TTBDebug] ❌ [\(connNum)] Body read error from \(endpointId): \(error.localizedDescription)")
                self.handleDisconnection(endpointId: endpointId, reason: "body read error")
                return
            }

            guard let chunk = body, !chunk.isEmpty else {
                if isComplete {
                    print("[TTBDebug] ⚠️ [\(connNum)] Connection closed mid-message from \(endpointId) (\(accumulated.count)/\(needed) bytes)")
                    self.handleDisconnection(endpointId: endpointId, reason: "closed mid-message")
                } else {
                    // Transient empty — retry
                    self.receiveBody(from: connection, endpointId: endpointId, connNum: connNum,
                                     needed: needed, accumulated: accumulated)
                }
                return
            }

            self.receiveBody(from: connection, endpointId: endpointId, connNum: connNum,
                             needed: needed, accumulated: accumulated + chunk)
        }
    }

    // MARK: - Process Message (runs on `queue`)

    private func processMessage(_ data: Data, endpointId: String, connection: NWConnection, connNum: Int) {
        guard let message = DebugMessage.from(data: data) else {
            // Diagnostic: show first 200 chars of the raw payload for protocol mismatch
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[TTBDebug] ❌ [\(connNum)] Failed to decode DebugMessage (\(data.count) bytes) from \(endpointId)")
            print("[TTBDebug]    Preview: \(preview)")
            return
        }

        switch message.type {

        case .deviceInfo:
            guard let info = message.decodePayload(DeviceInfoPayload.self) else {
                print("[TTBDebug] ❌ [\(connNum)] Failed to decode DeviceInfoPayload from \(endpointId)")
                return
            }
            let deviceId = info.deviceId

            // ── Reconnect guard ────────────────────────────────────────────────
            // If this device was connected on a DIFFERENT (stale) endpoint,
            // cancel the old NWConnection immediately so its future .failed/
            // .cancelled callback doesn't kill the newly reconnected session.
            if let oldEndpoint = liveEndpoint[deviceId], oldEndpoint != endpointId {
                print("[TTBDebug] 🔄 [\(connNum)] \(info.deviceName) reconnected — retiring stale endpoint (\(oldEndpoint))")
                pendingConnections[oldEndpoint]?.cancel()
                pendingConnections.removeValue(forKey: oldEndpoint)
                identifiedConnections.removeValue(forKey: oldEndpoint)
            }

            identifiedConnections[endpointId] = deviceId
            liveEndpoint[deviceId] = endpointId
            print("[TTBDebug] 📱 [\(connNum)] Device identified: \(info.deviceName) (id=\(info.deviceId), app=\(info.appName), sdk=\(info.sdkVersion))")
            DispatchQueue.main.async { self.onDeviceConnected?(deviceId, connection, info) }

        case .apiLog:
            guard let log = message.decodePayload(APILogPayload.self),
                  let deviceId = identifiedConnections[endpointId] else { return }
            DispatchQueue.main.async { self.onAPILog?(deviceId, log) }

        case .consoleLog:
            guard let log = message.decodePayload(ConsoleLogPayload.self),
                  let deviceId = identifiedConnections[endpointId] else { return }
            DispatchQueue.main.async { self.onConsoleLog?(deviceId, log) }

        case .heartbeat:
            guard let deviceId = identifiedConnections[endpointId] else { return }
            DispatchQueue.main.async { self.onHeartbeat?(deviceId) }

        case .screenshotResponse:
            guard let screenshot = message.decodePayload(ScreenshotResponsePayload.self),
                  let deviceId = identifiedConnections[endpointId] else { return }
            DispatchQueue.main.async { self.onScreenshot?(deviceId, screenshot) }

        case .performanceMetrics:
            guard let metrics = message.decodePayload(PerformanceMetricsPayload.self),
                  let deviceId = identifiedConnections[endpointId] else { return }
            DispatchQueue.main.async { self.onPerformanceMetrics?(deviceId, metrics) }

        case .connectionDiagnostics:
            guard let diag = message.decodePayload(ConnectionDiagnosticsPayload.self),
                  let deviceId = identifiedConnections[endpointId] else { return }
            print("[TTBDebug] 📋 [\(connNum)] Diagnostics from \(deviceId): IP=\(diag.localIP ?? "N/A")")
            DispatchQueue.main.async { self.onConnectionDiagnostics?(deviceId, diag) }

        default:
            print("[TTBDebug] ⚠️ [\(connNum)] Unhandled message type: \(message.type.rawValue) from \(endpointId)")
        }
    }

    // MARK: - Handle Disconnection (runs on `queue`)

    private func handleDisconnection(endpointId: String, reason: String) {
        // Clean up the raw connection slot unconditionally
        pendingConnections[endpointId]?.cancel()
        pendingConnections.removeValue(forKey: endpointId)

        // Was this endpoint ever fully identified?
        guard let deviceId = identifiedConnections.removeValue(forKey: endpointId) else {
            print("[TTBDebug] 🧹 Cleaned up unidentified endpoint \(endpointId) (reason: \(reason))")
            return
        }

        // ── Stale disconnect guard ──────────────────────────────────────────
        // If device already reconnected on a new endpoint, ignore this one.
        guard liveEndpoint[deviceId] == endpointId else {
            print("[TTBDebug] 🔕 Stale disconnect ignored for \(deviceId) — reason: \(reason) (already live on newer endpoint)")
            return
        }

        liveEndpoint.removeValue(forKey: deviceId)
        print("[TTBDebug] 📱 Device disconnected: \(deviceId) — reason: \(reason)")
        DispatchQueue.main.async { self.onDeviceDisconnected?(deviceId) }
    }

    // MARK: - Diagnostics

    /// Thread-safe snapshot of current connection state for debugging.
    var diagnosticSnapshot: (pending: Int, identified: Int, live: Int) {
        queue.sync { (pendingConnections.count, identifiedConnections.count, liveEndpoint.count) }
    }

    // MARK: - Disconnect All

    func disconnectAll() {
        queue.async { [weak self] in
            guard let self else { return }
            print("[TTBDebug] 🧹 Disconnecting all: \(self.pendingConnections.count) connections")
            for (_, conn) in self.pendingConnections { conn.cancel() }
            self.pendingConnections.removeAll()
            self.identifiedConnections.removeAll()
            self.liveEndpoint.removeAll()
        }
    }
}
