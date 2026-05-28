//
//  DeviceSessionMenuView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-09.
//  Popover menu for managing active device sessions (connections) from the sidebar.
//

import SwiftUI

// MARK: - Session Menu Button

struct DeviceSessionMenuButton: View {
    @Environment(ConnectionManager.self) var connectionManager
    @State private var showPopover = false

    private var onlineCount: Int { connectionManager.onlineDevices.count }
    private var totalCount:  Int { connectionManager.connectedDevices.count }

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: AppIcon.deviceSessions)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(onlineCount > 0 ? .ttSuccess : .ttTextTertiary)

                if totalCount > 0 {
                    Text("\(onlineCount)/\(totalCount)")
                        .font(TTFont.codeSmall)
                        .foregroundColor(onlineCount > 0 ? .ttSuccess : .ttTextTertiary)
                } else {
                    Text("0")
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextMuted)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.ttSurface.opacity(showPopover ? 0.8 : 0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.ttBorder.opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Manage Device Sessions")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            DeviceSessionMenuView()
                .environment(connectionManager)
        }
    }
}

// MARK: - Session Menu View (Popover Content)

struct DeviceSessionMenuView: View {
    @Environment(ConnectionManager.self) var connectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: AppIcon.deviceSessions)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ttSuccess)
                Text("Device Sessions")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                Spacer()
                if !connectionManager.connectedDevices.isEmpty {
                    Button(action: { connectionManager.clearAllLogs() }) {
                        Label("Clear Logs", systemImage: "trash")
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttError)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(Color.ttBorder)

            // ── Session list ───────────────────────────────────────────────────
            if connectionManager.connectedDevices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(connectionManager.connectedDevices) { session in
                            SessionRow(session: session)
                            if session.id != connectionManager.connectedDevices.last?.id {
                                Divider()
                                    .background(Color.ttBorder.opacity(0.4))
                                    .padding(.leading, 52)
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }

            Divider().background(Color.ttBorder)

            // ── Footer summary ─────────────────────────────────────────────────
            HStack(spacing: 8) {
                // Live indicator
                Circle()
                    .fill(connectionManager.onlineDevices.isEmpty ? Color.ttTextMuted : Color.ttSuccess)
                    .frame(width: 6, height: 6)

                let online = connectionManager.onlineDevices.count
                let total  = connectionManager.connectedDevices.count

                if total == 0 {
                    Text("No devices seen")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextTertiary)
                } else {
                    Text("\(online) online · \(total - online) offline")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextSecondary)
                }

                Spacer()

                // API / Console log counts
                if connectionManager.totalAPILogs > 0 || connectionManager.totalConsoleLogs > 0 {
                    HStack(spacing: 6) {
                        Label(String(connectionManager.totalAPILogs), systemImage: "network")
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextMuted)
                        Label(String(connectionManager.totalConsoleLogs), systemImage: "terminal")
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextMuted)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
        .background(Color.ttSurface)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: AppIcon.deviceUnavailable)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.ttTextMuted)

            VStack(spacing: 4) {
                Text("No Devices Connected")
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextSecondary)
                Text("Open your iOS app and call\nTTDebugBridge.shared.start()")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    @Environment(ConnectionManager.self) var connectionManager
    let session: DeviceSession

    @State private var isHovered  = false
    @State private var tickCount  = 0   // refreshes heartbeat display every second
    @State private var ticker: Timer?

    private var heartbeatText: String {
        _ = tickCount  // Consume tick to force re-evaluation
        let s = Int(Date().timeIntervalSince(session.lastHeartbeat))
        if s < 5  { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }

    private var heartbeatColor: Color {
        _ = tickCount  // Consume tick to force re-evaluation
        let s = Int(Date().timeIntervalSince(session.lastHeartbeat))
        if s < 8  { return .ttSuccess }
        if s < 15 { return .ttWarning }
        return .ttError
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Main row ──────────────────────────────────────────────────
            HStack(spacing: 12) {

                // Device icon + online dot
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: session.isSimulator ? AppIcon.simulator : AppIcon.device)
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(session.isOnline ? .ttTextPrimary : .ttTextTertiary)
                        .frame(width: 28)

                    Circle()
                        .fill(session.isOnline ? Color.ttSuccess : Color.ttTextMuted)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.ttSurface, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.displayName)
                            .font(TTFont.labelLarge)
                            .foregroundColor(session.isOnline ? .ttTextPrimary : .ttTextTertiary)
                            .lineLimit(1)

                        if session.isOnline {
                            // Selected indicator
                            if connectionManager.selectedDeviceId == session.id {
                                Text("ACTIVE")
                                    .font(TTFont.badge)
                                    .foregroundColor(.ttPrimary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.ttPrimary.opacity(0.12)))
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        // OS version
                        Text(session.osVersionString)
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextTertiary)

                        // App name
                        if let appName = session.deviceInfo?.appName, !appName.isEmpty {
                            Text("·")
                                .foregroundColor(.ttTextMuted)
                            Text(appName)
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextTertiary)
                                .lineLimit(1)
                        }
                    }

                    // IP + heartbeat
                    HStack(spacing: 8) {
                        if let ip = session.latestDiagnostics?.localIP {
                            Label(ip, systemImage: "network")
                                .font(.system(size: 10))
                                .foregroundColor(.ttTextMuted)
                        }

                        Label(heartbeatText, systemImage: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(heartbeatColor)
                    }
                }

                Spacer()

                // Log counts
                VStack(alignment: .trailing, spacing: 3) {
                    if session.apiLogs.count > 0 {
                        Label(String(session.apiLogs.count), systemImage: "network")
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttInfo)
                    }
                    if session.consoleLogs.count > 0 {
                        Label(String(session.consoleLogs.count), systemImage: "terminal")
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isHovered ? Color.ttSurface.opacity(0.5) : Color.clear)

            // ── Actions (show on hover) ───────────────────────────────────
            if isHovered {
                HStack(spacing: 0) {
                    Spacer()

                    // Select as active
                    if session.isOnline {
                        SessionActionButton(
                            title: "Set Active",
                            icon: "checkmark.circle",
                            color: .ttPrimary
                        ) {
                            connectionManager.selectedDeviceId = session.id
                        }
                    }

                    // Clear this session's logs
                    SessionActionButton(
                        title: "Clear Logs",
                        icon: "trash",
                        color: .ttError
                    ) {
                        connectionManager.clearLogs(for: session.id)
                    }

                    // Screenshot
                    if session.isOnline {
                        SessionActionButton(
                            title: "Screenshot",
                            icon: "camera",
                            color: .ttInfo
                        ) {
                            session.requestScreenshot()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            ticker = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                tickCount += 1   // force heartbeat re-render via computed property
            }
        }
        .onDisappear {
            ticker?.invalidate()
            ticker = nil
        }
    }
}

// MARK: - Session Action Button

struct SessionActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(TTFont.labelSmall)
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
    }
}

// MARK: - Preview

#Preview {
    DeviceSessionMenuView()
        .environment(ConnectionManager())
        .preferredColorScheme(.dark)
}
