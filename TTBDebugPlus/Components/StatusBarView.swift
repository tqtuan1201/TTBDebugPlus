//
//  StatusBarView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Bottom status bar — increased height, conditional metrics
//  2026-07-15: Phase 2 — spacing/typography tokens.
//

import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager

    private var hasDevice: Bool {
        connectionManager.selectedDevice?.isOnline(relativeTo: connectionManager.uiNow) == true
    }

    private var serverStatusColor: Color {
        if connectionManager.isServerRunning { return .ttSuccess }
        if connectionManager.isLifecycleActive { return .ttWarning }
        return .ttError
    }

    private var serverStatusText: String {
        if connectionManager.isServerRunning { return "ONLINE" }
        if connectionManager.isLifecycleActive { return "STARTING" }
        return "OFFLINE"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side: Server status + device metrics
            HStack(spacing: TTSpacing.lg) {
                // Server status (lifecycle + advertise honesty)
                HStack(spacing: TTSpacing.xs) {
                    Circle()
                        .fill(serverStatusColor)
                        .frame(width: TTSpacing.xs, height: TTSpacing.xs)
                    Text(serverStatusText)
                        .font(TTFont.statusBar)
                        .foregroundColor(serverStatusColor)
                }

                // Only show metrics when a device is connected (no more "--" values)
                if hasDevice, let perf = connectionManager.selectedDevice?.latestPerformance {
                    // Divider
                    Rectangle()
                        .fill(Color.ttBorder.opacity(0.4))
                        .frame(width: 1, height: TTIcon.xl)

                    // Memory
                    HStack(spacing: TTSpacing.tight) {
                        Image(systemName: "memorychip")
                            .font(.ttIcon(TTIcon.sm))
                            .foregroundColor(.ttTextTertiary)
                        Text(String(format: "%.0f MB", perf.memoryUsedMB))
                            .font(TTFont.statusBar)
                            .foregroundColor(.ttTextSecondary)
                    }

                    // CPU
                    HStack(spacing: TTSpacing.tight) {
                        Image(systemName: "cpu")
                            .font(.ttIcon(TTIcon.sm))
                            .foregroundColor(.ttTextTertiary)
                        Text(String(format: "%.1f%%", perf.cpuUsage))
                            .font(TTFont.statusBar)
                            .foregroundColor(perf.cpuUsage > 80 ? .ttWarning : .ttTextSecondary)
                    }
                }
            }
            .padding(.leading, TTSpacing.lg)

            Spacer()

            // Right side: Connection + events
            HStack(spacing: TTSpacing.md) {
                let totalEvents = connectionManager.totalAPILogs + connectionManager.totalConsoleLogs
                if totalEvents > 0 {
                    Text("\(totalEvents.formatted()) events")
                        .font(TTFont.statusBar)
                        .foregroundColor(.ttTextTertiary)

                    Rectangle()
                        .fill(Color.ttBorder.opacity(0.4))
                        .frame(width: 1, height: TTIcon.xl)
                }

                if let device = connectionManager.selectedDevice,
                   device.isOnline(relativeTo: connectionManager.uiNow) {
                    HStack(spacing: TTSpacing.xs) {
                        ConnectionIndicator(isConnected: true)
                        Text(device.displayName)
                            .font(TTFont.statusBar)
                            .foregroundColor(.ttTextSecondary)
                    }
                } else if connectionManager.onlineDevices.isEmpty {
                    ConnectionIndicator(isConnected: false, label: "No device")
                }
            }
            .padding(.trailing, TTSpacing.lg)
        }
        .frame(height: TTSpacing.statusBarHeight)
        .background(Color.ttBackground)
        .overlay(
            Rectangle()
                .fill(Color.ttBorder.opacity(0.3))
                .frame(height: 1),
            alignment: .top
        )
    }
}

#Preview {
    StatusBarView()
        .environment(AppState())
        .environment(ConnectionManager())
        .preferredColorScheme(.dark)
}
