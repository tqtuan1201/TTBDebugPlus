//
//  DeviceSession.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Represents a connected iOS device session
//  Hardened 2026-07-10: soft/hard online helpers aligned with heartbeat policy.
//  Hardened 2026-07-10b: warning band < soft timeout; isOnline(relativeTo:).
//

import Foundation
import Network

// MARK: - Device Session
/// Represents a single connected iOS device and its WebSocket connection.
/// Tracks device info, connection state, heartbeat, and received logs.
@Observable
final class DeviceSession: Identifiable, Hashable {
    let id: String // deviceId from handshake
    var deviceInfo: DeviceInfoPayload?
    var connection: NWConnection?
    /// Set instead of `connection` when this device was discovered via Relay mode (Phase 3) —
    /// routes outbound messages through the shared RelayClient connection instead of a
    /// per-device socket. At most one of `connection` / `relaySend` is non-nil for a live
    /// session; `send()` below picks whichever is set.
    var relaySend: ((DebugMessage) -> Void)?
    var connectionState: ConnectionState = .connecting
    /// Which transport this session is currently reachable through (Phase 8) — set
    /// unconditionally on every `handleDeviceConnected` call (including reconnects), so it
    /// tracks a device that hops from Bonjour to Relay (or vice versa) without extra plumbing.
    /// Not reset on disconnect — keeps showing the last-known channel while offline, which
    /// pairs with `connectionState`'s own online/warning/offline signal for the full picture.
    var connectionChannel: ConnectionChannel = .bonjour
    var lastHeartbeat: Date = Date()
    var connectedAt: Date = Date()
    /// Reason the last disconnect happened (from WebSocketServer), for diagnostics/UI.
    var lastDisconnectReason: String?

    // Accumulated data
    var apiLogs: [APILogPayload] = []
    var consoleLogs: [ConsoleLogPayload] = []
    var latestScreenshot: ScreenshotResponsePayload? = nil
    var latestPerformance: PerformanceMetricsPayload? = nil
    var latestDiagnostics: ConnectionDiagnosticsPayload? = nil

    /// Soft online threshold (UI green/selection). Hard cancel is owned by ConnectionManager (~20s).
    /// Must be **greater than** `warningHeartbeatAge` so amber warning is reachable while still online.
    static let softOnlineTimeout: TimeInterval = 15
    /// Amber warning band starts here (still treated as online for selection).
    static let warningHeartbeatAge: TimeInterval = 8

    // Computed
    var displayName: String {
        deviceInfo?.deviceName ?? "Unknown Device"
    }

    var deviceModelString: String {
        guard let model = deviceInfo?.deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else {
            return isSimulator ? "iOS Simulator" : "iPhone"
        }
        return model
    }

    var osVersionString: String {
        deviceInfo?.osVersion ?? "Unknown"
    }

    var appNameString: String {
        deviceInfo?.appName ?? "Unknown App"
    }

    var isSimulator: Bool {
        deviceInfo?.isSimulator ?? false
    }

    /// Online for UI/selection: transport connected and heartbeat within soft window.
    var isOnline: Bool {
        isOnline(relativeTo: Date())
    }

    /// Prefer this when views share `ConnectionManager.uiNow` (consistent across the UI tick).
    func isOnline(relativeTo now: Date) -> Bool {
        connectionState == .connected
            && now.timeIntervalSince(lastHeartbeat) < Self.softOnlineTimeout
    }

    /// Heartbeat aging relative to a shared clock (avoids extra timers in views).
    func heartbeatAge(relativeTo now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(lastHeartbeat)
    }

    /// True when connected but heartbeat is in the warning band (amber UI).
    func isHeartbeatWarning(relativeTo now: Date = Date()) -> Bool {
        guard connectionState == .connected else { return false }
        let age = now.timeIntervalSince(lastHeartbeat)
        return age >= Self.warningHeartbeatAge && age < Self.softOnlineTimeout
    }

    var shortId: String {
        String(id.prefix(8)).uppercased()
    }

    init(id: String, connection: NWConnection? = nil) {
        self.id = id
        self.connection = connection
    }

    // MARK: - Hashable
    static func == (lhs: DeviceSession, rhs: DeviceSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Send message to this device
    func send(_ message: DebugMessage) {
        if let relaySend {
            relaySend(message)
            return
        }
        guard let data = message.toData(), let connection = connection else { return }

        // Length-prefixed framing: 4-byte big-endian length + payload
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)

        // Capture the label now (on the caller's thread) rather than reading `self`
        // inside the completion — that closure runs on WebSocketServer's private
        // background queue, while `deviceInfo`/`displayName` are written on main.
        let label = displayName
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("[TTBDebug] Send error to \(label): \(error)")
            }
        })
    }

    // MARK: - Request screenshot
    func requestScreenshot(quality: Double = 0.7, maxWidth: Int? = 1170) {
        let request = ScreenshotRequestPayload(quality: quality, maxWidth: maxWidth)
        if let message = DebugMessage.create(type: .screenshotRequest, payload: request) {
            send(message)
        }
    }

    // MARK: - Send app command
    func sendCommand(_ action: String) {
        let command = AppCommandPayload(action: action)
        if let message = DebugMessage.create(type: .appCommand, payload: command) {
            send(message)
        }
    }
}

// MARK: - Connection State
enum ConnectionState: String {
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnected = "Disconnected"
    case failed = "Failed"

    var isActive: Bool {
        self == .connecting || self == .connected
    }
}

// MARK: - Connection Channel (Phase 8)

/// Which of the 3 producer-facing paths a device is reachable through — mirrors the 3 call
/// sites of `ConnectionManager.handleDeviceConnected`: local `WebSocketServer` (Bonjour), this
/// Mac's own `RelayServer`, or this Mac's `RelayClient` viewing a device actually connected to
/// a DIFFERENT Mac's relay.
enum ConnectionChannel: Equatable {
    case bonjour
    case relay(isRemoteView: Bool)

    var badgeLabel: String {
        switch self {
        case .bonjour: return "Bonjour"
        case .relay(let isRemoteView): return isRemoteView ? "Relay Remote" : "Relay"
        }
    }

    /// Full sentence used where there's room to explain, not just label (Connection Health,
    /// tooltips) — Phase 9. Sidebar rows stay on `badgeLabel` alone; cramming this into a
    /// ~200pt-wide list row would wrap/clip instead of clarifying anything.
    var fullDescription: String {
        switch self {
        case .bonjour: return "Bonjour (Mạng nội bộ)"
        case .relay(let isRemoteView): return isRemoteView ? "Relay Remote (Relay qua Internet)" : "Relay (Relay nội bộ)"
        }
    }

    /// `globe` for remote-viewed relay — distinct from the local relay icon so the two are
    /// distinguishable at a glance, not just by opacity (Phase 9).
    var badgeIcon: String {
        switch self {
        case .bonjour: return "antenna.radiowaves.left.and.right"
        case .relay(let isRemoteView): return isRemoteView ? "globe" : "arrow.triangle.2.circlepath"
        }
    }
}
