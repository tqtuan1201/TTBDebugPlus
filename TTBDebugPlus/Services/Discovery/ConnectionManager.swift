//
//  ConnectionManager.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Central manager for all device connections, Bonjour advertising, and message routing.
//  Updated 2026-04-09: multi-interface support via NetworkInterfaceMonitor.
//

import Foundation
import Network

// MARK: - Connection Manager

/// Central observable manager that owns the Bonjour advertiser, WebSocket server,
/// and all active device sessions. Views bind to this for real-time device/log updates.
@Observable
final class ConnectionManager {

    // MARK: - State

    var sessions: [String: DeviceSession] = [:] // deviceId → session
    var isServerRunning: Bool = false

    /// Guards against double-start while listeners are still initializing
    private var isStarted: Bool = false

    /// Per-interface port map (interfaceName → port)
    var serverPorts: [String: UInt16] = [:]

    /// Convenience: first available port (for backward UI compat)
    var serverPort: UInt16? { serverPorts.values.first }

    var totalAPILogs: Int = 0
    var totalConsoleLogs: Int = 0

    /// Currently active network interfaces (excluding loopback)
    var activeInterfaces: [NetworkInterface] = []

    // Sorted device list for UI binding
    var connectedDevices: [DeviceSession] {
        sessions.values.sorted { $0.connectedAt > $1.connectedAt }
    }

    var onlineDevices: [DeviceSession] {
        connectedDevices.filter { $0.isOnline }
    }

    // Active device selection
    var selectedDeviceId: String? = nil

    var selectedDevice: DeviceSession? {
        guard let id = selectedDeviceId else { return connectedDevices.first }
        return sessions[id]
    }

    // Cached log arrays — invalidated when counts or selected device change
    private var _cachedAPILogs: [APILogPayload]?
    private var _cachedAPILogsCount: Int = 0
    private var _cachedAPILogsDevice: String = ""
    private var _cachedConsoleLogs: [ConsoleLogPayload]?
    private var _cachedConsoleLogsCount: Int = 0
    private var _cachedConsoleLogsDevice: String = ""

    var allAPILogs: [APILogPayload] {
        let deviceKey = selectedDeviceId ?? "__all__"
        if let cached = _cachedAPILogs,
           _cachedAPILogsCount == totalAPILogs,
           _cachedAPILogsDevice == deviceKey { return cached }
        let result: [APILogPayload]
        if let device = selectedDevice {
            result = device.apiLogs
        } else {
            result = connectedDevices.flatMap { $0.apiLogs }.sorted { $0.timestamp > $1.timestamp }
        }
        _cachedAPILogs = result
        _cachedAPILogsCount = totalAPILogs
        _cachedAPILogsDevice = deviceKey
        return result
    }

    var allConsoleLogs: [ConsoleLogPayload] {
        let deviceKey = selectedDeviceId ?? "__all__"
        if let cached = _cachedConsoleLogs,
           _cachedConsoleLogsCount == totalConsoleLogs,
           _cachedConsoleLogsDevice == deviceKey { return cached }
        let result: [ConsoleLogPayload]
        if let device = selectedDevice {
            result = device.consoleLogs
        } else {
            result = connectedDevices.flatMap { $0.consoleLogs }.sorted { $0.timestamp > $1.timestamp }
        }
        _cachedConsoleLogs = result
        _cachedConsoleLogsCount = totalConsoleLogs
        _cachedConsoleLogsDevice = deviceKey
        return result
    }

    // MARK: - Private Services

    private let advertiser   = BonjourAdvertiser()
    private let wsServer     = WebSocketServer()
    private let ifMonitor    = NetworkInterfaceMonitor()
    private let ifPrefs      = InterfacePreferences.shared
    private var heartbeatTimer: Timer?

    // MARK: - Init

    init() {
        setupCallbacks()
    }

    // MARK: - Start Server

    func startServer() {
        guard !isStarted else {
            print("[TTBDebug] ⚠️ startServer called but already started — skipping")
            return
        }
        isStarted = true

        // Start monitoring interfaces — first update will kick off listeners
        ifMonitor.start()
        // NOTE: isServerRunning is driven by onStateChange (.ready callback)
        // to avoid showing "Running" before a port is actually bound.
        startHeartbeatMonitor()
        print("[TTBDebug] 🚀 Connection manager started (multi-interface mode)")
    }

    // MARK: - Stop Server

    func stopServer() {
        isStarted = false
        ifMonitor.stop()
        advertiser.stopAll()
        wsServer.disconnectAll()
        stopHeartbeatMonitor()
        sessions.removeAll()
        isServerRunning = false
        serverPorts.removeAll()
        activeInterfaces = []
        print("[TTBDebug] Server stopped")
    }

    // MARK: - Restart Server (full stop + start, clears sessions)

    func restartServer() {
        print("[TTBDebug] 🔄 Restarting server...")
        stopServer()
        // Small delay to let NWListeners fully tear down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServer()
        }
    }

    // MARK: - Force Reconnect (restart Bonjour only, keep sessions/logs)

    /// Tears down and re-creates all NWListeners without clearing sessions.
    /// Use when QC needs to "kick" the Bonjour stack without losing logs.
    func forceReconnect() {
        print("[TTBDebug] 🔄 Force-reconnecting Bonjour listeners...")
        advertiser.stopAll()
        // Small delay to let NWListeners fully tear down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.advertiser.updateInterfaces(self.activeInterfaces, preferences: self.ifPrefs)
            print("[TTBDebug] ✅ Bonjour listeners restarted")
        }
    }

    // MARK: - Interface Preference Toggle (called from UI)

    func setInterfaceEnabled(_ name: String, _ enabled: Bool) {
        ifPrefs.setEnabled(name, enabled)
        // Re-apply current interface list with updated prefs
        advertiser.updateInterfaces(activeInterfaces, preferences: ifPrefs)
    }

    func isInterfaceEnabled(_ name: String) -> Bool {
        ifPrefs.isEnabled(name)
    }

    /// Force a fresh POSIX scan without waiting for NWPathMonitor event.
    func rescanInterfaces() {
        ifMonitor.rescan()
    }

    // MARK: - Setup Callbacks

    private func setupCallbacks() {

        // Interface monitor → advertiser
        ifMonitor.onInterfacesChanged = { [weak self] interfaces in
            guard let self else { return }
            self.activeInterfaces = interfaces
            self.advertiser.updateInterfaces(interfaces, preferences: self.ifPrefs)
        }

        // Advertiser → WebSocket server
        advertiser.onNewConnection = { [weak self] connection in
            self?.wsServer.handleNewConnection(connection)
        }

        advertiser.onStateChange = { [weak self] interfaceName, state in
            DispatchQueue.main.async {
                guard let self else { return }
                // Sync port snapshot AFTER the serial queue has updated ports
                let snapshot = self.advertiser.portSnapshot
                switch state {
                case .ready:
                    self.isServerRunning = true
                    self.serverPorts = snapshot
                case .failed, .cancelled:
                    self.serverPorts = snapshot
                    // Still running if any other interface has a bound port or a device is connected
                    self.isServerRunning = !snapshot.isEmpty || !self.sessions.isEmpty
                case .waiting:
                    // Waiting means interface is trying — keep current running state
                    break
                default:
                    break
                }
            }
        }

        // WebSocket → Sessions
        wsServer.onDeviceConnected    = { [weak self] id, conn, info in self?.handleDeviceConnected(deviceId: id, connection: conn, info: info) }
        wsServer.onDeviceDisconnected = { [weak self] id in self?.handleDeviceDisconnected(deviceId: id) }
        wsServer.onAPILog             = { [weak self] id, log in self?.handleAPILog(deviceId: id, log: log) }
        wsServer.onConsoleLog         = { [weak self] id, log in self?.handleConsoleLog(deviceId: id, log: log) }
        wsServer.onHeartbeat          = { [weak self] id in self?.handleHeartbeat(deviceId: id) }
        wsServer.onScreenshot         = { [weak self] id, ss in self?.handleScreenshot(deviceId: id, screenshot: ss) }
        wsServer.onPerformanceMetrics = { [weak self] id, m in self?.handlePerformanceMetrics(deviceId: id, metrics: m) }
        wsServer.onConnectionDiagnostics = { [weak self] id, d in self?.handleConnectionDiagnostics(deviceId: id, diagnostics: d) }
    }

    // MARK: - Event Handlers

    private func handleDeviceConnected(deviceId: String, connection: NWConnection, info: DeviceInfoPayload) {
        let session: DeviceSession
        if let existing = sessions[deviceId] {
            existing.connection = connection
            existing.connectionState = .connected
            existing.deviceInfo = info
            existing.lastHeartbeat = Date()
            session = existing
            print("[TTBDebug] 📱 Device reconnected: \(info.deviceName)")
        } else {
            session = DeviceSession(id: deviceId, connection: connection)
            session.deviceInfo = info
            session.connectionState = .connected
            session.lastHeartbeat = Date()
            sessions[deviceId] = session
            print("[TTBDebug] 📱 New device connected: \(info.deviceName)")
        }
        if selectedDeviceId == nil { selectedDeviceId = deviceId }
    }

    private func handleDeviceDisconnected(deviceId: String) {
        if let session = sessions[deviceId] {
            session.connectionState = .disconnected
            session.connection = nil
            print("[TTBDebug] 📱 Device disconnected: \(session.displayName)")
        }
        // If the disconnected device was selected, auto-pivot to another online device
        if selectedDeviceId == deviceId {
            selectedDeviceId = onlineDevices.first(where: { $0.id != deviceId })?.id
        }
    }

    private func handleAPILog(deviceId: String, log: APILogPayload) {
        guard let session = sessions[deviceId] else { return }
        session.apiLogs.append(log)
        totalAPILogs += 1
        if session.apiLogs.count > 5000 { session.apiLogs.removeFirst(1000) }
    }

    private func handleConsoleLog(deviceId: String, log: ConsoleLogPayload) {
        guard let session = sessions[deviceId] else { return }
        session.consoleLogs.append(log)
        totalConsoleLogs += 1
        if session.consoleLogs.count > 10000 { session.consoleLogs.removeFirst(2000) }
    }

    private func handleHeartbeat(deviceId: String) {
        sessions[deviceId]?.lastHeartbeat = Date()
        sessions[deviceId]?.connectionState = .connected
    }

    private func handleScreenshot(deviceId: String, screenshot: ScreenshotResponsePayload) {
        sessions[deviceId]?.latestScreenshot = screenshot
    }

    private func handlePerformanceMetrics(deviceId: String, metrics: PerformanceMetricsPayload) {
        sessions[deviceId]?.latestPerformance = metrics
    }

    private func handleConnectionDiagnostics(deviceId: String, diagnostics: ConnectionDiagnosticsPayload) {
        sessions[deviceId]?.latestDiagnostics = diagnostics
        print("[TTBDebug] 📋 Diagnostics from \(sessions[deviceId]?.displayName ?? deviceId): IP=\(diagnostics.localIP ?? "N/A"), VPN=\(diagnostics.isVPN)")
    }

    // MARK: - macOS Network Info

    /// All active interface IPs (interfaceName → IPv4)
    var allLocalIPs: [String: String] {
        activeInterfaces.reduce(into: [:]) { result, iface in
            if let ip = iface.ipAddress { result[iface.name] = ip }
        }
    }

    /// Best guess at the primary mac IP: en0 → en1 → first available
    var macLocalIP: String? {
        allLocalIPs["en0"] ?? allLocalIPs["en1"] ?? allLocalIPs.values.first
    }

    /// Subnet mask for the primary interface (en0 → en1 → first)
    var macSubnetMask: String? {
        guard let primary = activeInterfaces.first(where: { $0.name == "en0" })
                         ?? activeInterfaces.first(where: { $0.name == "en1" })
                         ?? activeInterfaces.first,
              let ip = primary.ipAddress else { return nil }
        // return last-octet-zeroed mask heuristic (255.255.255.0)
        let parts = ip.split(separator: ".").prefix(3).map { String($0) }
        return parts.count == 3 ? parts.joined(separator: ".") + ".0" : nil
    }

    /// Network prefix for subnet comparison (uses primary IP)
    var macNetworkPrefix: String? {
        guard let ip = macLocalIP else { return nil }
        // Use /24 heuristic — compare first 3 octets
        let parts = ip.split(separator: ".").prefix(3)
        return parts.joined(separator: ".")
    }

    /// Per-interface network prefix map
    var allNetworkPrefixes: [String: String] {
        allLocalIPs.compactMapValues { ip in
            let parts = ip.split(separator: ".").prefix(3)
            return parts.count == 3 ? parts.joined(separator: ".") : nil
        }
    }

    // MARK: - Heartbeat Monitor

    private func startHeartbeatMonitor() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkHeartbeats()
        }
    }

    private func stopHeartbeatMonitor() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func checkHeartbeats() {
        let timeout: TimeInterval = 15
        for (_, session) in sessions where session.connectionState == .connected {
            let elapsed = Date().timeIntervalSince(session.lastHeartbeat)
            if elapsed > timeout {
                print("[TTBDebug] ⚠️ Heartbeat timeout: \(session.displayName) (\(Int(elapsed))s ago) — force-closing connection")
                // Cancel the NWConnection so TCP keep-alive fires and the remote
                // OS stack is notified. Also clears the session's connection reference.
                session.connection?.cancel()
                session.connection = nil
                session.connectionState = .disconnected
                // Auto-pivot selected device
                if selectedDeviceId == session.id {
                    selectedDeviceId = onlineDevices.first(where: { $0.id != session.id })?.id
                }
            }
        }
    }

    // MARK: - Actions

    func clearAllLogs() {
        for session in sessions.values {
            totalAPILogs     -= session.apiLogs.count
            totalConsoleLogs -= session.consoleLogs.count
            session.apiLogs.removeAll()
            session.consoleLogs.removeAll()
        }
        // Clamp to 0 to avoid negatives from any counter drift
        totalAPILogs     = max(0, totalAPILogs)
        totalConsoleLogs = max(0, totalConsoleLogs)
        // Bust cache
        _cachedAPILogs    = nil
        _cachedConsoleLogs = nil
    }

    /// Clear logs for a single session only, keeping other sessions' counters accurate.
    func clearLogs(for sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        totalAPILogs     = max(0, totalAPILogs     - session.apiLogs.count)
        totalConsoleLogs = max(0, totalConsoleLogs - session.consoleLogs.count)
        session.apiLogs.removeAll()
        session.consoleLogs.removeAll()
        _cachedAPILogs    = nil
        _cachedConsoleLogs = nil
    }

    func requestScreenshot(quality: Double = 0.7, maxWidth: Int? = 1170) {
        selectedDevice?.requestScreenshot(quality: quality, maxWidth: maxWidth)
    }

    func sendCommand(_ action: String) {
        selectedDevice?.sendCommand(action)
    }
}
