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
    @State private var pulseActive = false
    /// One-shot flag after window chrome settles (does not remount the view).
    @State private var chromeLayoutSettled = false

    /// Unified-compact titlebar + traffic lights sit over the sidebar when
    /// `fullSizeContentView` is on. Real layout child (not padding) so first
    /// NavigationSplitView pass cannot collapse clearance to zero.
    private static let titlebarClearance: CGFloat = 38
    
    var body: some View {
        // No GeometryReader: first-pass size is often 0×0 in NavigationSplitView while
        // server is still stopped, which collapsed branding + Start Server until a
        // lifecycle toggle forced remeasure.
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Self.titlebarClearance)
                .accessibilityHidden(true)

            // Fixed chrome — always visible, never collapses.
            // Pulled out of ScrollView because NavigationSplitView's
            // first layout pass can propose zero height to ScrollView
            // before fullSizeContentView is applied by AppWindowChrome.
            brandingHeader
            Divider().overlay(Color.ttBorder)
            serverStatusBar
            Divider().overlay(Color.ttBorder)

            // Scrollable section — devices, navigation, bottom actions
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: TTSpacing.md) {
                        connectedDevicesSection
                        navigationSection
                    }
                    .padding(.horizontal, TTSpacing.md)
                    .padding(.top, TTSpacing.chromeInsetV)
                    .padding(.bottom, TTSpacing.sm)

                    bottomActions
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.ttBackground)
        // Harmless dependency so a post-chrome settle triggers one extra layout pass
        // without destroying @State (unlike .id remount).
        .opacity(chromeLayoutSettled ? 1.0 : 0.999)
        .onAppear {
            scheduleChromeSettleLayoutPass()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttbWindowChromeDidApply)) { _ in
            scheduleChromeSettleLayoutPass()
        }
        .onChange(of: connectionManager.isLifecycleActive) { _, _ in
            if !connectionManager.isServerRunning {
                pulseActive = false
            }
        }
    }

    /// After `fullSizeContentView` is applied asynchronously, force SwiftUI layout passes.
    /// Two passes: immediate (catches most cases) + 200ms delayed (catches late window chrome).
    private func scheduleChromeSettleLayoutPass() {
        guard !chromeLayoutSettled else { return }
        DispatchQueue.main.async {
            chromeLayoutSettled = true
        }
    }
    
    // MARK: - Branding (compact — secondary to server controls)
    private var brandingHeader: some View {
        HStack(spacing: TTSpacing.inputPaddingH) {
            ZStack {
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(
                        LinearGradient(
                            colors: [Color.ttPrimary, Color.ttPrimaryDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: TTSpacing.statusBarHeight, height: TTSpacing.statusBarHeight)
                
                Image(systemName: AppIcon.app)
                    .font(.ttIcon(TTIcon.xxl))
                    .foregroundColor(.ttTextOnAccent)
            }
            
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                Text(AppBrand.name)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)

                Text(AppBrand.versionLabel)
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.3)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpacing.chromeInsetH)
        .padding(.vertical, TTSpacing.sm)
    }
    
    // MARK: - Server Status (Start / Stop — reserved height for both styles)
    private var serverStatusBar: some View {
        let lifecycleOn = connectionManager.isLifecycleActive

        return VStack(alignment: .leading, spacing: TTSpacing.sm) {
            HStack(spacing: TTSpacing.sm) {
                ZStack {
                    if connectionManager.isServerRunning {
                        Circle()
                            .fill(Color.ttSuccess.opacity(0.4))
                            .frame(width: TTIcon.xl, height: TTIcon.xl)
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
                        .frame(width: TTSpacing.sm, height: TTSpacing.sm)
                }
                .frame(width: TTIcon.xl, height: TTIcon.xl)
                
                VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                    Text(serverStatusTitle)
                        .font(TTFont.labelMedium)
                        .foregroundColor(.ttTextPrimary)
                        .lineLimit(1)
                    Text(serverStatusSubtitle)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: TTSpacing.xxs)
            }
            
            // Reserved height so Primary vs Outlined style swap cannot collapse chrome.
            Group {
                if lifecycleOn {
                    Button(action: { connectionManager.toggleServer() }) {
                        Label("Stop Server", systemImage: AppIcon.stopServer)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttOutlined)
                    .accessibilityLabel("Stop Server")
                    .help("Stop the debug bridge server")
                } else {
                    Button(action: { connectionManager.toggleServer() }) {
                        Label("Start Server", systemImage: AppIcon.startServer)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttPrimary)
                    .accessibilityLabel("Start Server")
                    .help("Start the debug bridge when you need a device connection")
                }
            }
            .frame(maxWidth: .infinity, minHeight: TTSpacing.controlMinHeight, alignment: .center)
            
            // Secondary server tools — fixed 28pt row (never half-clipped)
            HStack(spacing: TTSpacing.xs) {
                DeviceSessionMenuButton()
                NetworkInterfaceMenuButton()
                
                Button(action: { connectionManager.forceReconnect() }) {
                    Image(systemName: AppIcon.reconnect)
                        .font(.ttIcon(TTIcon.md))
                        .fontWeight(.medium)
                        .foregroundColor(lifecycleOn ? .ttWarning : .ttTextMuted)
                        .frame(width: TTSpacing.controlHit, height: TTSpacing.controlHit)
                        .background(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .fill(Color.ttSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: TTRadius.sm)
                                        .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!lifecycleOn)
                .help("Force Reconnect (restart Bonjour, keep logs)")
                .accessibilityLabel("Force Reconnect")
                
                Spacer(minLength: 0)
            }
            .frame(height: TTSpacing.controlHit, alignment: .center)
        }
        .padding(.horizontal, TTSpacing.md)
        .padding(.vertical, TTSpacing.chromeInsetV)
        .background(Color.ttSurface.opacity(0.45))
    }

    private var serverStatusTitle: String {
        if connectionManager.isServerRunning {
            return "Server Active"
        }
        if connectionManager.isLifecycleActive {
            return "Server Starting…"
        }
        return "Server Stopped"
    }

    private var serverStatusSubtitle: String {
        if connectionManager.isServerRunning {
            let ports = connectionManager.serverPorts.values.sorted()
            if ports.isEmpty {
                return "Waiting for network interface"
            }
            return ports.map { ":\($0)" }.joined(separator: "  ")
        }
        if connectionManager.isLifecycleActive {
            return "Binding ports…"
        }
        return "Tools ready · start when you need a device"
    }
    
    // MARK: - Connected Devices
    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            HStack {
                Text("CONNECTED DEVICES")
                    .font(TTFont.sidebarHeader)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.8)
                
                Spacer()
                
                Text("\(connectionManager.onlineDevices.count)")
                    .font(TTFont.badge)
                    .foregroundColor(.ttPrimary)
                    .padding(.horizontal, TTSpacing.xs)
                    .padding(.vertical, TTSpacing.xxxs)
                    .background(
                        Capsule()
                            .fill(Color.ttPrimary.opacity(0.15))
                    )
            }
            
            if connectionManager.connectedDevices.isEmpty {
                // No devices — show network hint
                VStack(alignment: .leading, spacing: TTSpacing.xs) {
                    HStack(spacing: TTSpacing.sm) {
                        Image(systemName: AppIcon.connectionOffline)
                            .font(.ttIcon(TTIcon.lg))
                            .foregroundColor(.ttTextTertiary)
                        Text("No devices found")
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextTertiary)
                    }
                    
                    if let ip = connectionManager.macLocalIP {
                        HStack(spacing: TTSpacing.xxs) {
                            Image(systemName: AppIcon.network)
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextMuted)
                            Text("Mac IP: \(ip)")
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextMuted)
                        }
                        .padding(.leading, TTSpacing.controlHit)
                    }
                    
                    Button(action: { appState.selectedTab = .connectionHealth }) {
                        Text("View Diagnostics →")
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttPrimary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, TTSpacing.controlHit)
                }
                .padding(.vertical, TTSpacing.sm)
                .padding(.horizontal, TTSpacing.xxs)
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
        VStack(spacing: TTSpacing.xxs) {
            ForEach(SidebarSection.allCases) { section in
                let gated = section.requiresLiveServer && !connectionManager.isLifecycleActive
                SidebarItemView(
                    section: section,
                    isSelected: appState.selectedSidebarItem == section,
                    badge: badgeCount(for: section),
                    isGated: gated
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if gated {
                            appState.serverRequiredHint =
                                "Start Server to use \(section.rawValue.capitalized). Dev Tools stay available without the server."
                            return
                        }
                        appState.serverRequiredHint = nil
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
        VStack(spacing: TTSpacing.sm) {
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
                .padding(.horizontal, TTSpacing.lg)
                .padding(.vertical, TTSpacing.xs)
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
                .padding(.horizontal, TTSpacing.lg)
                .padding(.vertical, TTSpacing.xs)
            }
        }
        .padding(.bottom, TTSpacing.md)
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
        HStack(spacing: TTSpacing.inputPaddingH) {
            // Device icon
            ZStack {
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(online ? Color.ttSuccess.opacity(0.12) : Color.ttSurface.opacity(0.55))
                    .frame(width: TTSpacing.statusBarHeight, height: TTSpacing.statusBarHeight)
                
                Image(systemName: session.isSimulator ? AppIcon.simulator : AppIcon.device)
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(online ? .ttSuccess : .ttTextTertiary)
            }
            
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
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
                .frame(width: TTSpacing.xs, height: TTSpacing.xs)
        }
        .padding(.horizontal, TTSpacing.sm)
        .padding(.vertical, TTSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
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
    var isGated: Bool = false
    let action: () -> Void

    private var iconColor: Color {
        if isGated { return .ttTextMuted }
        return isSelected ? .ttPrimary : .ttTextTertiary
    }

    private var titleColor: Color {
        if isGated { return .ttTextMuted }
        return isSelected ? .ttPrimary : .ttTextSecondary
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: TTSpacing.inputPaddingH) {
                Image(systemName: section.icon)
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                
                Text(section.rawValue)
                    .font(TTFont.sidebarItem)
                    .foregroundColor(titleColor)
                
                Spacer()
                
                if let badge = badge, !isGated {
                    Text("\(badge)")
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, TTSpacing.xs)
                        .padding(.vertical, TTSpacing.xxxs)
                        .background(
                            Capsule()
                                .fill(Color.ttSurface)
                        )
                }
            }
            .opacity(isGated ? 0.55 : 1)
        }
        .buttonStyle(TTSidebarItemStyle(isSelected: isSelected && !isGated))
        .help(isGated ? "Start Server to use this section" : section.rawValue)
    }
}

#Preview("Sidebar · tall") {
    SidebarView()
        .environment(AppState())
        .environment(ConnectionManager())
        .frame(width: 240, height: 800)
        .preferredColorScheme(.dark)
}

#Preview("Sidebar · short · server stopped") {
    SidebarView()
        .environment(AppState())
        .environment(ConnectionManager())
        .frame(width: 240, height: 520)
        .preferredColorScheme(.dark)
}
