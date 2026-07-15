//
//  NetworkInterfaceMenuView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-09.
//  Popover menu for managing active network interfaces inline from sidebar.
//

import SwiftUI

// MARK: - Network Interface Menu Button

/// A compact button that opens a popover for managing network interfaces.
/// Lives in the sidebar server status bar area.
struct NetworkInterfaceMenuButton: View {
    @Environment(ConnectionManager.self) var connectionManager
    @State private var showPopover = false

    private var activeCount: Int {
        connectionManager.activeInterfaces.filter {
            connectionManager.isInterfaceEnabled($0.name) && $0.ipAddress != nil
        }.count
    }

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(TTFont.labelMedium)
                .foregroundColor(activeCount > 0 ? .ttPrimary : .ttTextTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(Color.ttSurface.opacity(showPopover ? 0.9 : 1.0))
                        .overlay(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .help(
            connectionManager.activeInterfaces.isEmpty
                ? "Manage Network Interfaces"
                : "Network Interfaces (\(activeCount)/\(connectionManager.activeInterfaces.count))"
        )
        .accessibilityLabel("Network Interfaces")
        .accessibilityValue("\(activeCount) active")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            NetworkInterfaceMenuView()
                .environment(connectionManager)
        }
    }
}

// MARK: - Network Interface Menu View (Popover Content)

struct NetworkInterfaceMenuView: View {
    @Environment(ConnectionManager.self) var connectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: TTSpacing.sm) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttPrimary)
                Text("Network Interfaces")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                Spacer()
                Button(action: { connectionManager.rescanInterfaces() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(TTFont.labelMedium)
                        .foregroundColor(.ttPrimary)
                }
                .buttonStyle(.plain)
                .help("Rescan interfaces")
                Text("_ttbdebug._tcp")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
            }
            .padding(.horizontal, TTSpacing.lg)
            .padding(.top, TTSpacing.chromeInsetH)
            .padding(.bottom, TTSpacing.inputPaddingH)

            Divider().background(Color.ttBorder)

            // Interface list
            if connectionManager.activeInterfaces.isEmpty {
                HStack(spacing: TTSpacing.sm) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.ttTextMuted)
                    Text("No interfaces detected")
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                }
                .padding(TTSpacing.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(connectionManager.activeInterfaces) { iface in
                        InterfaceMenuRow(
                            interface: iface,
                            port: connectionManager.serverPorts[iface.name],
                            isEnabled: connectionManager.isInterfaceEnabled(iface.name),
                            onToggle: { connectionManager.setInterfaceEnabled(iface.name, $0) }
                        )

                        if iface.id != connectionManager.activeInterfaces.last?.id {
                            Divider()
                                .background(Color.ttBorder.opacity(0.5))
                                .padding(.leading, TTSpacing.menuRowIndent)
                        }
                    }
                }
            }

            Divider().background(Color.ttBorder)

            // Footer summary
            HStack(spacing: TTSpacing.xs) {
                // Bonjour status dot
                Circle()
                    .fill(connectionManager.isServerRunning ? Color.ttSuccess : Color.ttError)
                    .frame(width: 6, height: 6)

                if connectionManager.isServerRunning {
                    let ports = connectionManager.serverPorts.values.sorted()
                    if ports.isEmpty {
                        Text("Waiting for listeners...")
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttTextTertiary)
                    } else {
                        Text("Advertising on \(ports.count) interface\(ports.count > 1 ? "s" : "")")
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttTextSecondary)
                        Text("· ports: " + ports.map { String($0) }.joined(separator: ", "))
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextMuted)
                    }
                } else {
                    Text("Server stopped")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttError)
                }

                Spacer()

                // Enable all / disable all
                Button("All On") {
                    for iface in connectionManager.activeInterfaces {
                        connectionManager.setInterfaceEnabled(iface.name, true)
                    }
                }
                .font(TTFont.labelSmall)
                .foregroundColor(.ttPrimary)
                .buttonStyle(.plain)

                Text("·")
                    .foregroundColor(.ttTextMuted)
                    .font(TTFont.labelSmall)

                Button("All Off") {
                    for iface in connectionManager.activeInterfaces {
                        connectionManager.setInterfaceEnabled(iface.name, false)
                    }
                }
                .font(TTFont.labelSmall)
                .foregroundColor(.ttError)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TTSpacing.lg)
            .padding(.vertical, TTSpacing.inputPaddingH)
        }
        .frame(width: 340)
        .background(Color.ttSurface)
    }
}

// MARK: - Interface Menu Row

struct InterfaceMenuRow: View {
    let interface: NetworkInterface
    let port: UInt16?
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: TTSpacing.md) {

            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.75)

            // Interface icon
            Image(systemName: interface.kind.icon)
                .font(TTFont.sidebarItem)
                .foregroundColor(isEnabled ? kindColor : .ttTextMuted)
                .frame(width: 18)

            // Name + IP
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                HStack(spacing: TTSpacing.xs) {
                    Text(interface.name)
                        .font(TTFont.codeMedium)
                        .foregroundColor(isEnabled ? .ttTextPrimary : .ttTextTertiary)

                    // Kind tag
                    Text(interface.kind.rawValue.uppercased())
                        .font(TTFont.badge)
                        .foregroundColor(isEnabled ? kindColor : .ttTextMuted)
                        .padding(.horizontal, TTSpacing.tight)
                        .padding(.vertical, TTSpacing.xxxs)
                        .background(
                            Capsule().fill((isEnabled ? kindColor : Color.ttTextMuted).opacity(0.12))
                        )
                }

                Text(interface.ipAddress ?? "No IP")
                    .font(TTFont.codeSmall)
                    .foregroundColor(isEnabled ? .ttTextSecondary : .ttTextMuted)
            }

            Spacer()

            // Bonjour port — high-contrast soft pills
            if isEnabled {
                if let port {
                    VStack(alignment: .trailing, spacing: TTSpacing.inlineGapSmall) {
                        Text(":" + String(port))
                            .font(TTFont.codeSmall)
                            .foregroundColor(TTBannerKind.success.foreground)
                        TTStatusPill(text: "Advertising", kind: .success)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: TTSpacing.inlineGapSmall) {
                        Image(systemName: "clock")
                            .font(TTFont.labelMedium)
                            .foregroundColor(TTBannerKind.warning.foreground)
                        TTStatusPill(text: "Waiting", kind: .warning)
                    }
                }
            } else {
                Text("Disabled")
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextMuted)
            }
        }
        .padding(.horizontal, TTSpacing.lg)
        .padding(.vertical, TTSpacing.inputPaddingH)
        .opacity(isEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }

    private var kindColor: Color {
        switch interface.kind {
        case .wifi:     return .ttSuccess
        case .ethernet: return .ttInfo
        case .vpn:      return Color(hex: "#A855F7")
        case .other:    return .ttTextSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    NetworkInterfaceMenuView()
        .environment(ConnectionManager())
        .preferredColorScheme(.dark)
}
