//
//  SidebarView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Branding Header
            brandingHeader
            
            Divider()
                .overlay(Color.ttBorder)
            
            // MARK: - Server Status
            serverStatusBar
            
            Divider()
                .overlay(Color.ttBorder)
            
            // MARK: - Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Connected Devices
                    connectedDevicesSection
                    
                    // Navigation Items
                    navigationSection
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
            
            Spacer()
            
            // MARK: - Bottom Actions
            bottomActions
        }
        // Solid design-system canvas — matches main content `ttBackground`
        .background(Color.ttBackground)
    }
    
    // MARK: - Branding
    private var brandingHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.ttPrimary, Color.ttPrimaryDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: AppIcon.app)
                    .font(.ttIcon(TTIcon.xxl))
                    .foregroundColor(.ttTextOnAccent)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(AppBrand.name)
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)

                Text(AppBrand.tagline)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppBrand.versionLabel)
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.3)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
    
    @State private var pulseActive = false
    
    // MARK: - Server Status
    private var serverStatusBar: some View {
        HStack(spacing: 8) {
            ZStack {
                // Pulse glow behind the dot when server is active
                if connectionManager.isServerRunning {
                    Circle()
                        .fill(Color.ttSuccess.opacity(0.4))
                        .frame(width: 14, height: 14)
                        .opacity(pulseActive ? 0.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: pulseActive
                        )
                        .onAppear { pulseActive = true }
                        .onDisappear { pulseActive = false }
                }
                Circle()
                    .fill(connectionManager.isServerRunning ? Color.ttSuccess : Color.ttError)
                    .frame(width: 8, height: 8)
            }
            
            Text(
                connectionManager.isServerRunning
                    ? "Server Active"
                    : (connectionManager.isLifecycleActive ? "Server Starting…" : "Server Offline")
            )
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextSecondary)
            
            Spacer()

            // Session management menu
            DeviceSessionMenuButton()

            // Network interface management menu button
            NetworkInterfaceMenuButton()

            // Force reconnect (restart Bonjour only, keep logs)
            Button(action: { connectionManager.forceReconnect() }) {
                Image(systemName: AppIcon.reconnect)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(connectionManager.isLifecycleActive ? .ttWarning : .ttTextMuted)
            }
            .buttonStyle(.plain)
            .disabled(!connectionManager.isLifecycleActive)
            .help("Force Reconnect (restart Bonjour, keep logs)")
            .accessibilityLabel("Force Reconnect")
            
            // Toggle server lifecycle (not just port-bound advertise state)
            Button(action: {
                connectionManager.toggleServer()
            }) {
                Image(systemName: connectionManager.isLifecycleActive ? AppIcon.stopServer : AppIcon.startServer)
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(connectionManager.isLifecycleActive ? .ttError : .ttSuccess)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(connectionManager.isLifecycleActive ? "Stop Server" : "Start Server")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // No strip fill — keep sidebar flat; dividers separate sections
    }
    
    // MARK: - Connected Devices
    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONNECTED DEVICES")
                    .font(TTFont.sidebarHeader)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.8)
                
                Spacer()
                
                Text("\(connectionManager.onlineDevices.count)")
                    .font(TTFont.badge)
                    .foregroundColor(.ttPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.ttPrimary.opacity(0.15))
                    )
            }
            
            if connectionManager.connectedDevices.isEmpty {
                // No devices — show network hint
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: AppIcon.connectionOffline)
                            .font(.ttIcon(TTIcon.lg))
                            .foregroundColor(.ttTextTertiary)
                        Text("No devices found")
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextTertiary)
                    }
                    
                    if let ip = connectionManager.macLocalIP {
                        HStack(spacing: 4) {
                            Image(systemName: AppIcon.network)
                                .font(.system(size: 9))
                                .foregroundColor(.ttTextMuted)
                            Text("Mac IP: \(ip)")
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextMuted)
                        }
                        .padding(.leading, 28)
                    }
                    
                    Button(action: { appState.selectedTab = .connectionHealth }) {
                        Text("View Diagnostics →")
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttPrimary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 28)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            } else {
                ForEach(connectionManager.connectedDevices) { session in
                    DeviceRowView(
                        session: session,
                        isSelected: connectionManager.selectedDeviceId == session.id,
                        now: connectionManager.uiNow
                    )
                    .onTapGesture {
                        connectionManager.selectedDeviceId = session.id
                        appState.selectedTab = .device
                    }
                }
            }
        }
    }
    
    // MARK: - Navigation
    private var navigationSection: some View {
        VStack(spacing: 4) {
            ForEach(SidebarSection.allCases) { section in
                SidebarItemView(
                    section: section,
                    isSelected: appState.selectedSidebarItem == section,
                    badge: badgeCount(for: section)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.selectedSidebarItem = section
                        switch section {
                        case .devices:          appState.selectedTab = .device
                        case .logs:             appState.selectedTab = .console
                        case .network:          appState.selectedTab = .network
                        case .performance:      appState.selectedTab = .performance
                        case .devtools:         appState.openDevToolsMenu()
                        case .connectionHealth: appState.selectedTab = .connectionHealth
                        }
                    }
                }
            }
        }
    }
    
    private func badgeCount(for section: SidebarSection) -> Int? {
        switch section {
        case .devices:          return connectionManager.onlineDevices.count > 0 ? connectionManager.onlineDevices.count : nil
        case .logs:             return connectionManager.totalConsoleLogs > 0 ? connectionManager.totalConsoleLogs : nil
        case .network:          return connectionManager.totalAPILogs > 0 ? connectionManager.totalAPILogs : nil
        case .performance:      return nil
        case .devtools:         return nil
        case .connectionHealth: return nil
        }
    }
    
    // MARK: - Bottom Actions
    private var bottomActions: some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(Color.ttBorder)
            
            // Use SettingsLink / openSettings — private showSettingsWindow: is unreliable
            HStack(spacing: 0) {
                SettingsLink {
                    Label("SETTINGS", systemImage: AppIcon.settings)
                        .font(TTFont.sidebarItem)
                        .foregroundColor(.ttTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Settings (⌘,)")
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            
            HStack(spacing: 0) {
                Button(action: {
                    appState.selectedTab = .guide
                }) {
                    Label("INTEGRATION GUIDE", systemImage: AppTab.guide.icon)
                        .font(TTFont.sidebarItem)
                        .foregroundColor(appState.selectedTab == .guide ? .ttPrimary : .ttTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Device Row
struct DeviceRowView: View {
    let session: DeviceSession
    var isSelected: Bool = false
    /// Shared connection clock from ConnectionManager (optional; falls back to Date()).
    var now: Date = Date()

    private var online: Bool { session.isOnline(relativeTo: now) }
    private var warning: Bool { session.isHeartbeatWarning(relativeTo: now) }

    var body: some View {
        HStack(spacing: 10) {
            // Device icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(online ? Color.ttSuccess.opacity(0.12) : Color.ttSurface.opacity(0.55))
                    .frame(width: 32, height: 32)
                
                Image(systemName: session.isSimulator ? AppIcon.simulator : AppIcon.device)
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(online ? .ttSuccess : .ttTextTertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(TTFont.labelMedium)
                    .foregroundColor(isSelected ? .ttPrimary : .ttTextPrimary)
                    .lineLimit(1)
                
                Text(session.osVersionString)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextTertiary)
            }
            
            Spacer()

            // Connection channel (Phase 9) — Bonjour vs Relay, kept even while offline so the
            // last-known channel stays visible alongside the status dot below. Hover for the
            // full "Bonjour (Mạng nội bộ)"-style explanation (ChannelChip's `.help()`).
            ChannelChip(channel: session.connectionChannel, style: .compact)
                .opacity(online ? 1.0 : 0.45)

            // Status: green / amber / offline
            Circle()
                .fill(online ? (warning ? Color.ttWarning : Color.ttSuccess) : Color.ttTextTertiary)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.ttPrimary.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Updated Sidebar Item with Badge
struct SidebarItemView: View {
    let section: SidebarSection
    let isSelected: Bool
    var badge: Int? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(isSelected ? .ttPrimary : .ttTextTertiary)
                    .frame(width: 20)
                
                Text(section.rawValue)
                    .font(TTFont.sidebarItem)
                    .foregroundColor(isSelected ? .ttPrimary : .ttTextSecondary)
                
                Spacer()
                
                if let badge = badge {
                    Text("\(badge)")
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.ttSurface)
                        )
                }
            }
        }
        .buttonStyle(TTSidebarItemStyle(isSelected: isSelected))
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
        .environment(ConnectionManager())
        .frame(width: 230, height: 800)
        .preferredColorScheme(.dark)
}
