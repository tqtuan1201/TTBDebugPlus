//
//  ConnectionManager.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Central manager for all device connections, Bonjour advertising, and message routing.
//  Updated 2026-04-09: multi-interface support via NetworkInterfaceMonitor.
//  Hardened 2026-07-10: sleep/wake recovery, honest isServerRunning, single-writer
//  heartbeat disconnect, shared uiNow clock, stopAllAndWait reconnect.
//  Hardened 2026-07-10b: isLifecycleActive, recoverAdvertising (sync rescan),
//  wake debounce, disconnectAllAndWait, offline session prune, startServer recover.
//

import Foundation
import Network
import AppKit

// MARK: - Connection Manager

/// Central observable manager that owns the Bonjour advertiser, WebSocket server,
/// and all active device sessions. Views bind to this for real-time device/log updates.
@Observable
final class ConnectionManager {

    // MARK: - State

    var sessions: [String: DeviceSession] = [:] // deviceId → session

    /// True only when at least one Bonjour listener has a bound port.
    var isServerRunning: Bool = false

    /// True while the connection stack is intended to be active (monitor + heartbeat + observers).
    /// Distinct from `isServerRunning` — ports may be temporarily unbound after wake/interface loss.
    private(set) var isLifecycleActive: Bool = false

    private var lifecycleGeneration: Int = 0

    /// Per-interface port map (interfaceName → port)
    var serverPorts: [String: UInt16] = [:]

    /// Convenience: first available port (for backward UI compat)
    var serverPort: UInt16? { serverPorts.values.first }

    var totalAPILogs: Int = 0
    var totalConsoleLogs: Int = 0
    var totalPerformanceMetrics: Int = 0

    /// Currently active network interfaces (excluding loopback)
    var activeInterfaces: [NetworkInterface] = []

    /// Shared UI clock — bumped by the single heartbeat timer so views don't need private timers.
    var uiNow: Date = Date()

    // Sorted device list for UI binding
    var connectedDevices: [DeviceSession] {
        sessions.values.sorted { $0.connectedAt > $1.connectedAt }
    }

    var onlineDevices: [DeviceSession] {
        connectedDevices.filter { $0.isOnline(relativeTo: uiNow) }
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

    // MARK: - Relay Mode

    /// Accepts connections from producers/remote viewers. Phase 4: folded into the main
    /// Server lifecycle (`startServer()`/`stopServer()`) — no separate enable toggle. This Mac
    /// is automatically both host and viewer of its own relay (see `RelayServer.dispatchLocally`),
    /// so running a dedicated second Mac purely for relaying is no longer required.
    let relayServer = RelayServer()
    /// Port `relayServer` listens on. Settable any time; changing it while the server is
    /// running restarts just the relay listener via `setRelayServerPort`.
    var relayServerPort: UInt16 = 51820

    /// Connect out to *someone else's* Relay Server, to see devices that aren't on this LAN.
    /// Independent, opt-in — for "I'm not hosting, I just want to watch a teammate's session."
    let relayClient = RelayClient()

    // MARK: - Log Coalescing (reduces per-message @Observable churn under high traffic)

    /// Log messages arrive one at a time from WebSocketServer but are buffered here and
    /// flushed in batches (`logFlushTimer`, 200ms) instead of mutating `@Observable` arrays
    /// per-message. Under bursty high-volume traffic this caps SwiftUI diff work to a fixed
    /// rate instead of one diff per inbound log — the best-supported hypothesis in the
    /// 2026-07-13 RCA for "random" mass-disconnects (main-thread contention starving the
    /// heartbeat Timer, which then hard-cancels every session at once).
    private var pendingAPILogs: [String: [APILogPayload]] = [:]
    private var pendingConsoleLogs: [String: [ConsoleLogPayload]] = [:]
    private var logFlushTimer: Timer?
    private let logFlushInterval: TimeInterval = 0.2
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Held for as long as the connection stack is meant to be running — opts out of App
    /// Nap so the OS doesn't throttle the 5s heartbeat/discovery timers while the window
    /// isn't frontmost. Does NOT prevent the Mac from sleeping (handled separately above).
    private var appNapActivityToken: NSObjectProtocol?
    private var wakeRecoveryWorkItem: DispatchWorkItem?
    private var advertiseRecoveryWorkItem: DispatchWorkItem?
    /// Per-reason cooldown timestamps — a forced recovery for one reason (e.g. wake)
    /// must not suppress the passive tick-driven self-heal for a different, unrelated failure.
    private var lastAdvertiseRecoveryAt: [String: Date] = [:]
    /// Suppresses advertiser updates from interface callbacks while a recovery rebind is in flight.
    private var isRecoveringAdvertise = false
    private var advertiseRecoveryToken: UInt64 = 0

    /// Optional session persistence sink (wired from app lifecycle — weak to avoid cycles).
    weak var sessionRecorder: SessionManager?

    /// Hard cancel aligns with TCP keepalive budget (~20s). Soft online is 15s (DeviceSession).
    private let hardHeartbeatTimeout: TimeInterval = 20
    /// Drop fully offline sessions after this age to prevent unbounded memory growth.
    private let offlineSessionRetention: TimeInterval = 30 * 60
    /// Min gap between automatic advertise recoveries (avoids thrash when bind keeps failing).
    private let advertiseRecoveryCooldown: TimeInterval = 15

    // MARK: - Init

    init() {
        setupCallbacks()
    }

    deinit {
        removeWorkspaceObservers()
        wakeRecoveryWorkItem?.cancel()
        advertiseRecoveryWorkItem?.cancel()
        stopHeartbeatMonitor()
    }

    // MARK: - Start Server

    func startServer() {
        // Already in lifecycle: recover advertise if ports died (was a silent no-op before).
        if isLifecycleActive {
            if !isServerRunning {
                print("[TTBDebug] ⚠️ startServer while lifecycle active but not advertising — recovering")
                recoverAdvertising(reason: "startServer-recover", force: true)
            } else {
                print("[TTBDebug] ⚠️ startServer called but already started — skipping")
            }
            return
        }

        isLifecycleActive = true
        lifecycleGeneration += 1

        if appNapActivityToken == nil {
            appNapActivityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "TTBDebugPlus keeps debug bridge connections alive"
            )
        }

        // Start monitoring interfaces — first update will kick off listeners
        ifMonitor.start()
        // NOTE: isServerRunning is driven by onStateChange (.ready callback)
        // to avoid showing "Running" before a port is actually bound.
        startHeartbeatMonitor()
        registerWorkspaceObservers()
        // Phase 4: the embedded relay follows the same On/Off as local Bonjour — one Mac can
        // be both host and viewer with no separate toggle or second machine.
        relayServer.start(port: relayServerPort)
        print("[TTBDebug] 🚀 Connection manager started (multi-interface mode)")
    }

    // MARK: - Stop Server

    func stopServer() {
        lifecycleGeneration += 1
        isLifecycleActive = false
        wakeRecoveryWorkItem?.cancel()
        wakeRecoveryWorkItem = nil
        advertiseRecoveryWorkItem?.cancel()
        advertiseRecoveryWorkItem = nil
        isRecoveringAdvertise = false
        removeWorkspaceObservers()
        if let token = appNapActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            appNapActivityToken = nil
        }
        ifMonitor.stopAndWait()
        advertiser.stopAllAndWait()
        wsServer.disconnectAllAndWait()
        relayServer.stop()
        stopHeartbeatMonitor()
        sessions.removeAll()
        selectedDeviceId = nil
        totalAPILogs = 0
        totalConsoleLogs = 0
        totalPerformanceMetrics = 0
        _cachedAPILogs = nil
        _cachedConsoleLogs = nil
        isServerRunning = false
        serverPorts.removeAll()
        activeInterfaces = []
        sessionRecorder?.endSession()
        print("[TTBDebug] Server stopped")
    }

    /// Toggle lifecycle using `isLifecycleActive` (not port-bound state).
    func toggleServer() {
        if isLifecycleActive {
            stopServer()
        } else {
            startServer()
        }
    }

    // MARK: - Restart Server (full stop + start, clears sessions)

    func restartServer() {
        print("[TTBDebug] 🔄 Restarting server...")
        stopServer()
        let generation = lifecycleGeneration
        // Small delay to let NW stack fully release ports after cancel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.lifecycleGeneration == generation, !self.isLifecycleActive else { return }
            self.startServer()
        }
    }

    // MARK: - Force Reconnect (restart Bonjour only, keep sessions/logs)

    /// Tears down and re-creates all NWListeners without clearing sessions.
    func forceReconnect() {
        guard isLifecycleActive else { return }
        recoverAdvertising(reason: "forceReconnect", force: true)
    }

    // MARK: - Advertise recovery (single path for wake / force / stuck-start)

    /// Synchronously rescans interfaces, stops listeners, then rebinds after a short yield.
    /// - Parameter force: When true (user force-reconnect / wake), ignore cooldown.
    private func recoverAdvertising(reason: String, force: Bool = false) {
        guard isLifecycleActive else { return }
        let now = Date()
        if !force,
           let last = lastAdvertiseRecoveryAt[reason],
           now.timeIntervalSince(last) < advertiseRecoveryCooldown {
            return
        }
        lastAdvertiseRecoveryAt[reason] = now

        let generation = lifecycleGeneration
        print("[TTBDebug] 🔄 Recover advertising (\(reason))...")

        // Cancel any in-flight recovery to avoid stacked rebinds
        advertiseRecoveryWorkItem?.cancel()
        advertiseRecoveryToken &+= 1
        let recoveryToken = advertiseRecoveryToken
        isRecoveringAdvertise = true

        // Sync rescan so we don't rebuild listeners with a stale interface list.
        // Interface callback may fire; isRecoveringAdvertise suppresses mid-recovery rebind.
        let interfaces = ifMonitor.rescanAndWait()
        if !interfaces.isEmpty {
            activeInterfaces = interfaces
        }
        advertiser.stopAllAndWait()
        syncServerRunningFromPorts()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer {
                // Only the latest recovery may clear the flag (cancelled predecessors no-op)
                if self.advertiseRecoveryToken == recoveryToken {
                    self.isRecoveringAdvertise = false
                }
            }
            guard self.isLifecycleActive, self.lifecycleGeneration == generation else { return }
            guard self.advertiseRecoveryToken == recoveryToken else { return }
            // Prefer monitor snapshot (may have merged NWInterface from path)
            let latest = self.ifMonitor.activeInterfaces
            let target = latest.isEmpty ? self.activeInterfaces : latest
            if !target.isEmpty {
                self.activeInterfaces = target
            }
            self.advertiser.updateInterfaces(self.activeInterfaces, preferences: self.ifPrefs)
            self.syncServerRunningFromPorts()
            print("[TTBDebug] ✅ Advertise recovery complete (\(reason))")
        }
        advertiseRecoveryWorkItem = work
        // Brief yield so cancelled listeners release sockets before re-bind
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: - Interface Preference Toggle (called from UI)

    func setInterfaceEnabled(_ name: String, _ enabled: Bool) {
        ifPrefs.setEnabled(name, enabled)
        advertiser.updateInterfaces(activeInterfaces, preferences: ifPrefs)
    }

    func isInterfaceEnabled(_ name: String) -> Bool {
        ifPrefs.isEnabled(name)
    }

    /// Force a fresh scan without waiting for NWPathMonitor event.
    func rescanInterfaces() {
        ifMonitor.rescan()
    }

    // MARK: - Setup Callbacks

    private func setupCallbacks() {

        // Interface monitor → advertiser
        ifMonitor.onInterfacesChanged = { [weak self] interfaces in
            guard let self else { return }
            guard self.isLifecycleActive else { return }
            self.activeInterfaces = interfaces
            // During recovery we only refresh the list; rebind is owned by recoverAdvertising.
            guard !self.isRecoveringAdvertise else { return }
            self.advertiser.updateInterfaces(interfaces, preferences: self.ifPrefs)
        }

        // Advertiser → WebSocket server
        advertiser.onNewConnection = { [weak self] connection in
            self?.wsServer.handleNewConnection(connection)
        }

        advertiser.onStateChange = { [weak self] _, state in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.isLifecycleActive else {
                    self.isServerRunning = false
                    self.serverPorts.removeAll()
                    return
                }
                let snapshot = self.advertiser.portSnapshot
                self.serverPorts = snapshot
                switch state {
                case .ready:
                    self.isServerRunning = !snapshot.isEmpty
                case .failed, .cancelled:
                    // Honest advertise state — sessions alone do NOT mean server is running
                    self.isServerRunning = !snapshot.isEmpty
                case .waiting:
                    self.isServerRunning = !snapshot.isEmpty
                default:
                    break
                }
            }
        }

        // WebSocket → Sessions (single writer for connect/disconnect state)
        wsServer.onDeviceConnected    = { [weak self] id, conn, info in self?.handleDeviceConnected(deviceId: id, connection: conn, relaySend: nil, channel: .bonjour, info: info) }
        wsServer.onDeviceDisconnected = { [weak self] id, reason in self?.handleDeviceDisconnected(deviceId: id, reason: reason) }
        wsServer.onAPILog             = { [weak self] id, log in self?.handleAPILog(deviceId: id, log: log) }
        wsServer.onConsoleLog         = { [weak self] id, log in self?.handleConsoleLog(deviceId: id, log: log) }
        wsServer.onHeartbeat          = { [weak self] id in self?.handleHeartbeat(deviceId: id) }
        wsServer.onScreenshot         = { [weak self] id, ss in self?.handleScreenshot(deviceId: id, screenshot: ss) }
        wsServer.onPerformanceMetrics = { [weak self] id, m in self?.handlePerformanceMetrics(deviceId: id, metrics: m) }
        wsServer.onConnectionDiagnostics = { [weak self] id, d in self?.handleConnectionDiagnostics(deviceId: id, diagnostics: d) }

        // Relay Client → Sessions (Phase 3). Same handlers as local — a device doesn't care
        // whether it arrived via LAN Bonjour or a relay.
        relayClient.onDeviceConnected    = { [weak self] id, info in
            self?.handleDeviceConnected(deviceId: id, connection: nil, relaySend: { [weak self] msg in self?.relayClient.send(msg) }, channel: .relay(isRemoteView: true), info: info)
        }
        relayClient.onDeviceDisconnected = { [weak self] id, reason in self?.handleDeviceDisconnected(deviceId: id, reason: reason) }
        relayClient.onAPILog             = { [weak self] id, log in self?.handleAPILog(deviceId: id, log: log) }
        relayClient.onConsoleLog         = { [weak self] id, log in self?.handleConsoleLog(deviceId: id, log: log) }
        relayClient.onHeartbeat          = { [weak self] id in self?.handleHeartbeat(deviceId: id) }
        relayClient.onScreenshot         = { [weak self] id, ss in self?.handleScreenshot(deviceId: id, screenshot: ss) }
        relayClient.onPerformanceMetrics = { [weak self] id, m in self?.handlePerformanceMetrics(deviceId: id, metrics: m) }
        relayClient.onConnectionDiagnostics = { [weak self] id, d in self?.handleConnectionDiagnostics(deviceId: id, diagnostics: d) }

        // Relay Server → Sessions (Phase 4). This Mac is both host and viewer of its own
        // relay — no loopback RelayClient needed. Uses `sendToProducer` for precise per-device
        // targeting (better than RelayClient's broadcast-only v1, since this Mac holds each
        // producer's actual connection directly, unlike a remote viewer).
        relayServer.onDeviceConnected    = { [weak self] id, info in
            self?.handleDeviceConnected(
                deviceId: id, connection: nil,
                relaySend: { [weak self] msg in self?.relayServer.sendToProducer(deviceId: id, message: msg) },
                channel: .relay(isRemoteView: false),
                info: info
            )
        }
        relayServer.onDeviceDisconnected = { [weak self] id, reason in self?.handleDeviceDisconnected(deviceId: id, reason: reason) }
        relayServer.onAPILog             = { [weak self] id, log in self?.handleAPILog(deviceId: id, log: log) }
        relayServer.onConsoleLog         = { [weak self] id, log in self?.handleConsoleLog(deviceId: id, log: log) }
        relayServer.onHeartbeat          = { [weak self] id in self?.handleHeartbeat(deviceId: id) }
        relayServer.onScreenshot         = { [weak self] id, ss in self?.handleScreenshot(deviceId: id, screenshot: ss) }
        relayServer.onPerformanceMetrics = { [weak self] id, m in self?.handlePerformanceMetrics(deviceId: id, metrics: m) }
        relayServer.onConnectionDiagnostics = { [weak self] id, d in self?.handleConnectionDiagnostics(deviceId: id, diagnostics: d) }
    }

    // MARK: - Relay Mode Control

    /// Changes the relay listen port. If the server is currently running, restarts just the
    /// relay listener (local Bonjour/WebSocket are untouched).
    func setRelayServerPort(_ port: UInt16) {
        relayServerPort = port
        guard isLifecycleActive else { return }
        relayServer.stop()
        relayServer.start(port: port)
    }

    func setRelayClientEnabled(_ enabled: Bool, host: String, port: UInt16) {
        if enabled {
            relayClient.start(host: host, port: port)
        } else {
            relayClient.stop()
        }
    }

    private func syncServerRunningFromPorts() {
        let snapshot = advertiser.portSnapshot
        serverPorts = snapshot
        isServerRunning = isLifecycleActive && !snapshot.isEmpty
    }

    // MARK: - Sleep / Wake

    private func registerWorkspaceObservers() {
        removeWorkspaceObservers()
        let nc = NSWorkspace.shared.notificationCenter

        let wake = nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSystemWake()
        }
        let screensWake = nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSystemWake()
        }
        let willSleep = nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSystemWillSleep()
        }
        let sessionResign = nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSessionResignActive()
        }
        let sessionBecome = nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSessionBecomeActive()
        }
        workspaceObservers = [wake, screensWake, willSleep, sessionResign, sessionBecome]
    }

    private func removeWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            nc.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    private func handleSystemWake() {
        guard isLifecycleActive else { return }
        // Debounce didWake + screensDidWake which often fire together
        wakeRecoveryWorkItem?.cancel()
        let generation = lifecycleGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isLifecycleActive, self.lifecycleGeneration == generation else { return }
            print("[TTBDebug] 💤→☀️ System wake — recovering Bonjour advertise")
            self.recoverAdvertising(reason: "systemWake", force: true)
        }
        wakeRecoveryWorkItem = work
        // Path stack may still be coming up after wake
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Proactively releases Bonjour listeners just before the Mac sleeps, instead of only
    /// reacting after wake (RCA §1.6: "only reactive, post-wake handling exists"). Existing
    /// device sessions/TCP connections are untouched — this only avoids listeners sitting in
    /// a stale half-bound state through the sleep transition; `handleSystemWake()` already
    /// rebuilds them fresh on resume.
    private func handleSystemWillSleep() {
        guard isLifecycleActive else { return }
        print("[TTBDebug] 💤 System will sleep — proactively releasing Bonjour listeners")
        wakeRecoveryWorkItem?.cancel()
        advertiseRecoveryWorkItem?.cancel()
        isRecoveringAdvertise = false
        advertiser.stopAllAndWait()
        syncServerRunningFromPorts()
    }

    /// Screen locked or fast user switch away. Logged only — no teardown: existing sessions
    /// keep working over their live TCP connections, and stopping listeners here would only
    /// needlessly block new devices from pairing while the screen happens to be locked.
    private func handleSessionResignActive() {
        guard isLifecycleActive else { return }
        print("[TTBDebug] 🔒 Session resigned active (screen lock / fast user switch)")
    }

    /// Screen unlocked or switched back — previously a complete blind spot (RCA §1.6): if
    /// Wi-Fi/socket teardown happened while locked without a full system sleep, nothing ever
    /// noticed or recovered. Treated like a lightweight wake, respecting the normal per-reason
    /// cooldown (unlike system wake, unlocking can happen many times an hour).
    private func handleSessionBecomeActive() {
        guard isLifecycleActive else { return }
        print("[TTBDebug] 🔓 Session became active (unlock) — verifying Bonjour advertise")
        recoverAdvertising(reason: "sessionBecomeActive", force: false)
    }

    // MARK: - Event Handlers

    /// `connection` is set for local (WebSocketServer) devices, `relaySend` for devices that
    /// arrived via Relay Client (Phase 3) — exactly one of the two is non-nil. `channel` (Phase
    /// 8) is set unconditionally on every call (including reconnects), so a device that hops
    /// from Bonjour to Relay (or back) between calls is reflected immediately in the UI badge.
    private func handleDeviceConnected(deviceId: String, connection: NWConnection?, relaySend: ((DebugMessage) -> Void)?, channel: ConnectionChannel, info: DeviceInfoPayload) {
        if let existing = sessions[deviceId] {
            existing.connection = connection
            existing.relaySend = relaySend
            existing.connectionChannel = channel
            existing.connectionState = .connected
            existing.deviceInfo = info
            existing.lastHeartbeat = Date()
            // Keep original connectedAt for stable sort; only refresh heartbeat
            print("[TTBDebug] 📱 Device reconnected: \(info.deviceName)")
        } else {
            let session = DeviceSession(id: deviceId, connection: connection)
            session.relaySend = relaySend
            session.connectionChannel = channel
            session.deviceInfo = info
            session.connectionState = .connected
            session.lastHeartbeat = Date()
            sessions[deviceId] = session
            print("[TTBDebug] 📱 New device connected: \(info.deviceName)")
        }
        if selectedDeviceId == nil { selectedDeviceId = deviceId }
        sessionRecorder?.noteDeviceConnected(
            deviceId: deviceId,
            deviceName: info.deviceName,
            appName: info.appName
        )
    }

    private func handleDeviceDisconnected(deviceId: String, reason: String) {
        if let session = sessions[deviceId] {
            session.connectionState = .disconnected
            session.connection = nil
            session.relaySend = nil
            session.lastDisconnectReason = reason
            print("[TTBDebug] 📱 Device disconnected: \(session.displayName) — reason: \(reason)")
        }
        if selectedDeviceId == deviceId {
            selectedDeviceId = onlineDevices.first(where: { $0.id != deviceId })?.id
                ?? connectedDevices.first(where: { $0.id != deviceId && $0.connectionState == .connected })?.id
        }
    }

    /// Buffers rather than appends directly — see `flushPendingLogs()`.
    private func handleAPILog(deviceId: String, log: APILogPayload) {
        guard sessions[deviceId] != nil else { return }
        pendingAPILogs[deviceId, default: []].append(log)
    }

    /// Buffers rather than appends directly — see `flushPendingLogs()`.
    private func handleConsoleLog(deviceId: String, log: ConsoleLogPayload) {
        guard sessions[deviceId] != nil else { return }
        pendingConsoleLogs[deviceId, default: []].append(log)
    }

    /// Drains `pendingAPILogs`/`pendingConsoleLogs` into the real `@Observable` session
    /// arrays in one batch per device, called every `logFlushInterval` instead of once per
    /// inbound message. Runs on main (called from the main-run-loop `logFlushTimer`).
    private func flushPendingLogs() {
        if !pendingAPILogs.isEmpty {
            for (deviceId, logs) in pendingAPILogs where !logs.isEmpty {
                guard let session = sessions[deviceId] else { continue }
                session.apiLogs.append(contentsOf: logs)
                totalAPILogs += logs.count
                // Cap without pathological O(n) churn: drop a chunk when over limit
                if session.apiLogs.count > 5000 {
                    session.apiLogs.removeFirst(min(1000, session.apiLogs.count - 4000))
                }
                for log in logs { sessionRecorder?.addAPILog(log) }
            }
            pendingAPILogs.removeAll(keepingCapacity: true)
        }

        if !pendingConsoleLogs.isEmpty {
            for (deviceId, logs) in pendingConsoleLogs where !logs.isEmpty {
                guard let session = sessions[deviceId] else { continue }
                session.consoleLogs.append(contentsOf: logs)
                totalConsoleLogs += logs.count
                if session.consoleLogs.count > 10000 {
                    session.consoleLogs.removeFirst(min(2000, session.consoleLogs.count - 8000))
                }
                for log in logs { sessionRecorder?.addConsoleLog(log) }
            }
            pendingConsoleLogs.removeAll(keepingCapacity: true)
        }
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
        totalPerformanceMetrics += 1
        sessionRecorder?.addPerformanceSnapshot(metrics)
    }

    private func handleConnectionDiagnostics(deviceId: String, diagnostics: ConnectionDiagnosticsPayload) {
        sessions[deviceId]?.latestDiagnostics = diagnostics
        print("[TTBDebug] 📋 Diagnostics from \(sessions[deviceId]?.displayName ?? deviceId): IP=\(diagnostics.localIP ?? "N/A"), VPN=\(diagnostics.isVPN)")
    }

    // MARK: - macOS Network Info

    var allLocalIPs: [String: String] {
        activeInterfaces.reduce(into: [:]) { result, iface in
            if let ip = iface.ipAddress { result[iface.name] = ip }
        }
    }

    var macLocalIP: String? {
        allLocalIPs["en0"] ?? allLocalIPs["en1"] ?? allLocalIPs.values.first
    }

    var macSubnetMask: String? {
        guard let primary = activeInterfaces.first(where: { $0.name == "en0" })
                         ?? activeInterfaces.first(where: { $0.name == "en1" })
                         ?? activeInterfaces.first,
              let ip = primary.ipAddress else { return nil }
        let parts = ip.split(separator: ".").prefix(3).map { String($0) }
        return parts.count == 3 ? parts.joined(separator: ".") + ".0" : nil
    }

    var macNetworkPrefix: String? {
        guard let ip = macLocalIP else { return nil }
        let parts = ip.split(separator: ".").prefix(3)
        return parts.joined(separator: ".")
    }

    var allNetworkPrefixes: [String: String] {
        allLocalIPs.compactMapValues { ip in
            let parts = ip.split(separator: ".").prefix(3)
            return parts.count == 3 ? parts.joined(separator: ".") : nil
        }
    }

    // MARK: - Heartbeat Monitor + shared UI clock

    private func startHeartbeatMonitor() {
        guard heartbeatTimer == nil else { return }
        // Ensure timer is on main run loop (UI / AppKit lifecycle)
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
        uiNow = Date()

        let flush = Timer(timeInterval: logFlushInterval, repeats: true) { [weak self] _ in
            self?.flushPendingLogs()
        }
        flush.tolerance = 0.05
        RunLoop.main.add(flush, forMode: .common)
        logFlushTimer = flush
    }

    private func stopHeartbeatMonitor() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        logFlushTimer?.invalidate()
        logFlushTimer = nil
        pendingAPILogs.removeAll()
        pendingConsoleLogs.removeAll()
    }

    private func tick() {
        uiNow = Date()
        checkHeartbeats()
        pruneStaleSessions()
        // Keep isServerRunning honest if ports drained without a state event
        if isLifecycleActive {
            let snapshot = advertiser.portSnapshot
            if serverPorts != snapshot {
                serverPorts = snapshot
            }
            let advertising = !snapshot.isEmpty
            if isServerRunning != advertising {
                isServerRunning = advertising
            }
            // Auto-recover if lifecycle is active but all listeners are gone
            // (interface flap without wake). Cooldown prevents thrash.
            if !advertising, !activeInterfaces.isEmpty {
                recoverAdvertising(reason: "tick-no-ports", force: false)
            }
        }
    }

    /// Hard path only cancels the NWConnection. Session state is written solely by
    /// WebSocketServer disconnect/connect callbacks (avoids double-writer races).
    /// Relay-sourced sessions (`session.connection == nil`) are intentionally skipped here —
    /// cancelling the shared RelayClient connection would drop every relayed device, not just
    /// the stale one. That's fine: RelayServer already detects a producer's real disconnect at
    /// the hop closest to it and forwards a synthesized `.disconnect`, which is faster and more
    /// precise than this local heartbeat-silence fallback anyway.
    private func checkHeartbeats() {
        for (_, session) in sessions where session.connectionState == .connected {
            let elapsed = uiNow.timeIntervalSince(session.lastHeartbeat)
            if elapsed > hardHeartbeatTimeout {
                print("[TTBDebug] ⚠️ Heartbeat hard-timeout: \(session.displayName) (\(Int(elapsed))s ago) — cancelling connection")
                // Cancel only; handleDeviceDisconnected will update state via WS callback
                session.connection?.cancel()
            }
        }
    }

    /// Remove long-offline sessions to bound memory (logs can be large).
    private func pruneStaleSessions() {
        let cutoff = offlineSessionRetention
        let staleIds = sessions.compactMap { id, session -> String? in
            guard session.connectionState == .disconnected || session.connectionState == .failed else {
                return nil
            }
            guard uiNow.timeIntervalSince(session.lastHeartbeat) > cutoff else { return nil }
            return id
        }
        guard !staleIds.isEmpty else { return }

        for id in staleIds {
            if let session = sessions.removeValue(forKey: id) {
                totalAPILogs = max(0, totalAPILogs - session.apiLogs.count)
                totalConsoleLogs = max(0, totalConsoleLogs - session.consoleLogs.count)
            }
            // Session is gone — flushPendingLogs would just skip these via its own guard,
            // but drop them explicitly so the buffer doesn't hold a dead device's key forever.
            pendingAPILogs.removeValue(forKey: id)
            pendingConsoleLogs.removeValue(forKey: id)
            if selectedDeviceId == id {
                selectedDeviceId = onlineDevices.first?.id ?? connectedDevices.first?.id
            }
        }
        _cachedAPILogs = nil
        _cachedConsoleLogs = nil
        print("[TTBDebug] 🧹 Pruned \(staleIds.count) stale offline session(s)")
    }

    // MARK: - Actions

    func clearAllLogs() {
        clearAPILogs()
        clearConsoleLogs()
    }

    /// Clear only network/API capture data (does not touch console).
    func clearAPILogs() {
        for session in sessions.values {
            totalAPILogs -= session.apiLogs.count
            session.apiLogs.removeAll()
        }
        totalAPILogs = max(0, totalAPILogs)
        // Drop not-yet-flushed logs too — otherwise they reappear on the next flush tick.
        pendingAPILogs.removeAll()
        _cachedAPILogs = nil
    }

    /// Clear only console logs (does not touch network capture).
    func clearConsoleLogs() {
        for session in sessions.values {
            totalConsoleLogs -= session.consoleLogs.count
            session.consoleLogs.removeAll()
        }
        totalConsoleLogs = max(0, totalConsoleLogs)
        pendingConsoleLogs.removeAll()
        _cachedConsoleLogs = nil
    }

    func clearLogs(for sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        totalAPILogs     = max(0, totalAPILogs     - session.apiLogs.count)
        totalConsoleLogs = max(0, totalConsoleLogs - session.consoleLogs.count)
        session.apiLogs.removeAll()
        session.consoleLogs.removeAll()
        pendingAPILogs.removeValue(forKey: sessionId)
        pendingConsoleLogs.removeValue(forKey: sessionId)
        _cachedAPILogs    = nil
        _cachedConsoleLogs = nil
    }

    func clearAPILogs(for sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        totalAPILogs = max(0, totalAPILogs - session.apiLogs.count)
        session.apiLogs.removeAll()
        pendingAPILogs.removeValue(forKey: sessionId)
        _cachedAPILogs = nil
    }

    func clearConsoleLogs(for sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        totalConsoleLogs = max(0, totalConsoleLogs - session.consoleLogs.count)
        session.consoleLogs.removeAll()
        pendingConsoleLogs.removeValue(forKey: sessionId)
        _cachedConsoleLogs = nil
    }

    func requestScreenshot(quality: Double = 0.7, maxWidth: Int? = 1170) {
        selectedDevice?.requestScreenshot(quality: quality, maxWidth: maxWidth)
    }

    func sendCommand(_ action: String) {
        selectedDevice?.sendCommand(action)
    }
}
