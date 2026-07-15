//
//  ConnectionHealthView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-30.
//  Connection diagnostics & waiting screen — replaces empty state when no device connected
//

import SwiftUI

// MARK: - Connection Health View
/// Shown when no iOS device is connected. Displays server status, network info,
/// troubleshooting checklist, and connected device diagnostics (if available).
struct ConnectionHealthView: View {
    @Environment(ConnectionManager.self) var connectionManager
    /// Same UserDefaults key as `SettingsView` — Relay Client's "enabled" flag lives in
    /// `@AppStorage` only (RelayClientStatus itself has no `isEnabled`, just
    /// `isConnected`/`lastError`), so this is the only way to tell "off" apart from
    /// "on but still connecting" (Phase 9).
    @AppStorage("relayClientEnabled") private var relayClientEnabled: Bool = false

    /// Derived from shared ConnectionManager clock — no private Timer.
    private var refreshTick: Int {
        Int(connectionManager.uiNow.timeIntervalSince1970 / 5)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: TTSpacing.xxl) {
                // Hero section
                heroSection
                
                // Status cards grid
                HStack(alignment: .top, spacing: TTSpacing.lg) {
                    // Left: Server + Network
                    VStack(spacing: TTSpacing.lg) {
                        serverStatusCard
                        networkInfoCard
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right: Relay status + Troubleshooting + Device diagnostics
                    VStack(spacing: TTSpacing.lg) {
                        relayStatusCard
                        troubleshootingCard
                        if let device = connectionManager.selectedDevice,
                           let diag = device.latestDiagnostics {
                            deviceDiagnosticsCard(device: device, diag: diag)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 800)
                
                // Quick start code + QR pairing
                HStack(alignment: .top, spacing: TTSpacing.lg) {
                    quickStartCard
                    qrPairingCard
                }
                .frame(maxWidth: 800)
                
                // ── NEW: Multi-Interface Sections ─────────────────────────
                VStack(spacing: TTSpacing.lg) {
                    networkInterfacesCard
                    bonjourStatusCard
                    if !connectionManager.connectedDevices.isEmpty {
                        connectedDevicesCard
                    }
                }
                .frame(maxWidth: 800)
            }
            .padding(TTSpacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ttBackground)
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: TTSpacing.lg) {
            // Animated icon
            ZStack {
                // Outer ring pulse
                Circle()
                    .stroke(Color.ttPrimary.opacity(0.15), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(connectionManager.isServerRunning ? 1.3 : 1.0)
                    .opacity(connectionManager.isServerRunning ? 0 : 0.3)
                    .animation(
                        connectionManager.isServerRunning
                            ? .easeInOut(duration: 2.0).repeatForever(autoreverses: false)
                            : .default,
                        value: refreshTick
                    )
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.ttPrimary.opacity(0.15), Color.ttPrimary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(Color.ttPrimary.opacity(0.3), lineWidth: 1)
                    )
                
                Image(systemName: AppIcon.connectionHealth)
                    .font(TTFont.lightDisplay(base: 36))
                    .foregroundColor(.ttPrimary)
                    .symbolEffect(.variableColor.iterative, options: .repeating, value: refreshTick)
            }
            
            VStack(spacing: TTSpacing.xs) {
                Text("Waiting for iOS Device")
                    .font(TTFont.heading1)
                    .foregroundColor(.ttTextPrimary)
                
                Text("Ensure your iOS app is running with TTDebugBridge.shared.start()")
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Server Status Card
    
    private var serverStatusCard: some View {
        CardView(title: "SERVER STATUS") {
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                statusRow(
                    icon: connectionManager.isServerRunning
                        ? "checkmark.circle.fill"
                        : (connectionManager.isLifecycleActive ? "exclamationmark.triangle.fill" : "xmark.circle.fill"),
                    iconColor: connectionManager.isServerRunning
                        ? .ttSuccess
                        : (connectionManager.isLifecycleActive ? .ttWarning : .ttError),
                    label: "Bonjour Service",
                    value: connectionManager.isServerRunning
                        ? "Running"
                        : (connectionManager.isLifecycleActive ? "Active (no ports)" : "Stopped")
                )
                
                if let port = connectionManager.serverPort {
                    statusRow(
                    icon: AppIcon.network,
                        iconColor: .ttPrimary,
                        label: "Port",
                        value: String(port)
                    )
                }
                
                statusRow(
                    icon: AppIcon.connectionHealth,
                    iconColor: connectionManager.isServerRunning ? .ttSuccess : .ttTextTertiary,
                    label: "Advertising",
                    value: connectionManager.isServerRunning ? "_ttbdebug._tcp" : "Inactive"
                )
                
                statusRow(
                    icon: AppIcon.device,
                    iconColor: .ttPrimary,
                    label: "Connected",
                    value: "\(connectionManager.onlineDevices.count) device(s)"
                )
                
                // ── Action Buttons ──────────────────────────────────────
                // Lifecycle (isLifecycleActive) drives Start/Stop; isServerRunning is port-bound advertise.
                HStack(spacing: TTSpacing.sm) {
                    if connectionManager.isLifecycleActive {
                        // Force Reconnect — restart Bonjour without clearing sessions
                        Button(action: { connectionManager.forceReconnect() }) {
                            HStack(spacing: TTSpacing.tight) {
                                Image(systemName: AppIcon.reconnect)
                                Text(connectionManager.isServerRunning ? "Force Reconnect" : "Recover Advertise")
                            }
                        }
                        .buttonStyle(.ttSecondary)

                        // Full Restart — tear down everything and start fresh
                        Button(action: { connectionManager.restartServer() }) {
                            HStack(spacing: TTSpacing.tight) {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart Server")
                            }
                        }
                        .buttonStyle(.ttGhost)

                        Button(action: { connectionManager.stopServer() }) {
                            HStack(spacing: TTSpacing.tight) {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Server")
                            }
                        }
                        .buttonStyle(.ttGhost)
                    } else {
                        Button(action: { connectionManager.startServer() }) {
                            HStack(spacing: TTSpacing.tight) {
                                Image(systemName: "play.circle.fill")
                                Text("Start Server")
                            }
                        }
                        .buttonStyle(.ttPrimary)
                    }
                }
                .padding(.top, TTSpacing.xxs)
            }
        }
    }
    
    // MARK: - Network Info Card
    
    private var networkInfoCard: some View {
        CardView(title: "NETWORK") {
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                if let ip = connectionManager.macLocalIP {
                    statusRow(
                        icon: "globe",
                        iconColor: .ttInfo,
                        label: "Mac IP",
                        value: ip
                    )
                } else {
                    statusRow(
                        icon: "wifi.slash",
                        iconColor: .ttError,
                        label: "Wi-Fi",
                        value: "Not connected"
                    )
                }
                
                if let mask = connectionManager.macSubnetMask {
                    statusRow(
                        icon: "rectangle.split.3x1",
                        iconColor: .ttTextTertiary,
                        label: "Subnet",
                        value: mask
                    )
                }
                
                if let prefix = connectionManager.macNetworkPrefix {
                    statusRow(
                        icon: "network",
                        iconColor: .ttPrimary,
                        label: "Network",
                        value: prefix
                    )
                }
                
                let primaryIface = connectionManager.activeInterfaces
                    .first(where: { $0.ipAddress != nil })
                statusRow(
                    icon: "desktopcomputer",
                    iconColor: .ttTextTertiary,
                    label: "Interface",
                    value: primaryIface.map { "\($0.name) (\($0.kind.rawValue))" } ?? "Unknown"
                )
            }
        }
    }
    
    // MARK: - Relay Status Card (Phase 9)

    /// Connection Health previously showed ZERO relay information (Bonjour/local-network only)
    /// even though Relay Server/Client is a full second connection path (Phase 3/4/7) — this
    /// mirrors `connectionManager.relayServer.status` / `.relayClient.status` (already computed
    /// elsewhere, no new plumbing) as a health-check card: icon + color + plain-language
    /// explanation + what to do next, instead of raw settings controls.
    private var relayStatusCard: some View {
        CardView(title: "RELAY STATUS") {
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                relayServerBanner
                relayClientBanner
            }
        }
    }

    private var relayServerBanner: some View {
        let status = connectionManager.relayServer.status
        let kind: TTBannerKind
        let title: String
        let message: String
        if let error = status.lastError {
            kind = .error
            title = "Relay Server — Error"
            message = error
        } else if !connectionManager.isLifecycleActive {
            kind = .info
            title = "Relay Server — Off"
            message = "Off because the main Server is off (Relay shares the Server On/Off switch — there's no separate toggle). Start the Server above to enable it."
        } else if status.isRunning {
            kind = .success
            title = "Relay Server — Listening"
            message = "\(status.producerCount) iOS device(s) via relay · \(status.viewerCount) remote viewer(s) watching this Mac."
        } else {
            kind = .warning
            title = "Relay Server — Starting…"
            message = "Server is on; the relay listener is still coming up. Give it a moment."
        }
        return TTBanner(kind: kind, message: message, title: title)
    }

    private var relayClientBanner: some View {
        let status = connectionManager.relayClient.status
        let kind: TTBannerKind
        let title: String
        let message: String
        if !relayClientEnabled {
            kind = .info
            title = "Relay Client — Off"
            message = "Not watching another Mac's relay. Turn this on in Settings → Relay to view devices connected to a different Mac (e.g. a teammate's, or yours over a different network)."
        } else if let error = status.lastError {
            kind = .error
            title = "Relay Client — Error"
            message = error
        } else if status.isConnected {
            kind = .success
            title = "Relay Client — Connected"
            message = "Watching a remote relay. Its devices appear in the sidebar exactly like local ones."
        } else {
            kind = .warning
            title = "Relay Client — Connecting…"
            message = "Attempting to reach the configured relay host. Check the host/port in Settings → Relay if this doesn't resolve."
        }
        return TTBanner(kind: kind, message: message, title: title)
    }

    // MARK: - Troubleshooting Card

    private var troubleshootingCard: some View {
        CardView(title: "TROUBLESHOOTING CHECKLIST") {
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                checklistItem(
                    checked: connectionManager.isServerRunning,
                    text: "TTBDebugPlus server is running"
                )
                
                checklistItem(
                    checked: !connectionManager.onlineDevices.isEmpty,
                    text: "iOS device connected & sending data"
                )
                
                checklistItem(
                    checked: connectionManager.macLocalIP != nil,
                    text: "Mac is connected to Wi-Fi"
                )
                
                // Static hints (can't auto-check from macOS side)
                Divider().background(Color.ttBorder.opacity(0.3))
                
                Text("On your iOS device, verify:")
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextTertiary)
                    .padding(.top, TTSpacing.xxs)
                
                hintItem(icon: "swift", text: "TTDebugBridge.shared.start() is called")
                hintItem(icon: "wifi", text: "Both devices on the same Wi-Fi network")
                hintItem(icon: "lock.shield", text: "Local Network permission is granted")
                hintItem(icon: "shield.slash", text: "No VPN blocking mDNS (port 5353)")
                hintItem(icon: "shippingbox", text: "SDK version >= 4.2.0")
            }
        }
    }
    
    // MARK: - Device Diagnostics Card (when data exists)
    
    private func deviceDiagnosticsCard(device: DeviceSession, diag: ConnectionDiagnosticsPayload) -> some View {
        CardView(title: "iOS DEVICE DIAGNOSTICS") {
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                statusRow(
                    icon: AppIcon.device,
                    iconColor: .ttSuccess,
                    label: "Device",
                    value: device.displayName
                )
                
                if let ip = diag.localIP {
                    statusRow(
                        icon: "globe",
                        iconColor: .ttInfo,
                        label: "iOS IP",
                        value: ip
                    )
                }
                
                // Same network comparison
                if let iosPrefix = diag.networkPrefix,
                   let macPrefix = connectionManager.macNetworkPrefix {
                    let sameNetwork = iosPrefix == macPrefix
                    statusRow(
                        icon: sameNetwork ? "checkmark.circle.fill" : "xmark.circle.fill",
                        iconColor: sameNetwork ? .ttSuccess : .ttError,
                        label: "Same Network",
                        value: sameNetwork ? "✅ Yes (\(iosPrefix))" : "❌ No (iOS: \(iosPrefix), Mac: \(macPrefix))"
                    )
                }
                
                if diag.isVPN {
                    statusRow(
                        icon: "shield.lefthalf.filled",
                        iconColor: .ttWarning,
                        label: "iOS VPN",
                        value: "⚠️ Active"
                    )
                }
                
                statusRow(
                    icon: "shippingbox",
                    iconColor: .ttTextTertiary,
                    label: "SDK",
                    value: "v\(diag.sdkVersion)"
                )
            }
        }
    }
    
    // MARK: - Quick Start Card
    
    private var quickStartCard: some View {
        CardView(title: "QUICK START") {
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                Text("Add this to your AppDelegate or SceneDelegate:")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                
                codeBlock("""
                #if DEBUG
                TTDebugBridge.shared.start()
                LogInterceptor.shared.install()
                #endif
                """)
                
                Text("For manual diagnostics, call in Xcode console:")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .padding(.top, TTSpacing.xxs)
                
                codeBlock("po TTDebugBridge.shared.printDiagnosticReport()")
            }
        }
    }
    
    // MARK: - QR Pairing Card

    /// Renders a scannable `ttbdebug://<ip>:<port>` code (reuses the Dev Tools QR
    /// generator) — the fastest path for the iOS "Scan QR" fallback to auto-fill
    /// manual-connect fields when Bonjour/mDNS discovery fails or is just slow.
    private var qrPairingCard: some View {
        CardView(title: "PAIR BY QR CODE") {
            VStack(spacing: TTSpacing.inputPaddingH) {
                if let ip = connectionManager.macLocalIP, let port = connectionManager.serverPort {
                    let pairingString = "ttbdebug://\(ip):\(port)"
                    if let qrImage = QRCodeEngine.generate(
                        payload: pairingString,
                        correction: .medium,
                        foreground: .black,
                        background: .white,
                        size: 240
                    ) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 150, height: 150)
                            .padding(TTSpacing.sm)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    }
                    Text("iOS → Debug Bridge panel → Scan QR")
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                        .multilineTextAlignment(.center)
                    // Shows which Mac this code belongs to — matters once a team has more
                    // than one Mac advertising on the same LAN (each has a unique Bonjour
                    // name since Phase 4; this reuses that exact same string).
                    Text(BonjourAdvertiser.advertiseName)
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextSecondary)
                    Text(pairingString)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextSecondary)
                        .textSelection(.enabled)
                } else {
                    Text("Start the server to generate a pairing code")
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Reusable Components

    private func statusRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: TTSpacing.inputPaddingH) {
            Image(systemName: icon)
                .font(.ttIcon(TTIcon.lg))
                .foregroundColor(iconColor)
                .frame(width: 20, alignment: .center)
            
            Text(label)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .lineLimit(2)
            
            Spacer()
        }
    }
    
    private func checklistItem(checked: Bool, text: String) -> some View {
        HStack(spacing: TTSpacing.sm) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(TTFont.codeLarge)
                .foregroundColor(checked ? .ttSuccess : .ttTextTertiary)
            
            Text(text)
                .font(TTFont.bodySmall)
                .foregroundColor(checked ? .ttTextPrimary : .ttTextSecondary)
        }
    }
    
    private func hintItem(icon: String, text: String) -> some View {
        HStack(spacing: TTSpacing.sm) {
            Image(systemName: icon)
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
                .frame(width: 16, alignment: .center)
            
            Text(text)
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextSecondary)
        }
        .padding(.leading, TTSpacing.xs)
    }
    
    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(TTFont.codeSmall)
            .foregroundColor(.ttJsonString)
            .padding(TTSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ttBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                    )
            )
            .textSelection(.enabled)
    }
}

// MARK: - Multi-Interface Extension

extension ConnectionHealthView {

    // MARK: Network Interfaces Card

    var networkInterfacesCard: some View {
        CardView(title: "NETWORK INTERFACES") {
            VStack(spacing: 0) {
                if connectionManager.activeInterfaces.isEmpty {
                    HStack {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.ttTextMuted)
                        Text("No active interfaces detected")
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextTertiary)
                    }
                    .padding(.vertical, TTSpacing.xs)
                } else {
                    ForEach(connectionManager.activeInterfaces) { iface in
                        VStack(spacing: 0) {
                            HStack(spacing: TTSpacing.md) {
                                // Toggle
                                Toggle("", isOn: Binding(
                                    get: { connectionManager.isInterfaceEnabled(iface.name) },
                                    set: { connectionManager.setInterfaceEnabled(iface.name, $0) }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .scaleEffect(0.8)

                                // Kind badge
                                ifaceBadge(iface.kind)

                                // Name + IP
                                VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                                    Text(iface.name)
                                        .font(TTFont.codeMedium)
                                        .foregroundColor(.ttTextPrimary)
                                    Text(iface.ipAddress ?? "No IP assigned")
                                        .font(TTFont.codeSmall)
                                        .foregroundColor(iface.ipAddress != nil ? .ttTextSecondary : .ttTextTertiary)
                                }

                                Spacer()

                                Circle()
                                    .fill(connectionManager.isInterfaceEnabled(iface.name)
                                          ? (iface.ipAddress != nil ? Color.ttSuccess : Color.ttWarning)
                                          : Color.ttTextMuted)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(.vertical, TTSpacing.sm)
                            .animation(.easeInOut(duration: 0.2), value: connectionManager.isInterfaceEnabled(iface.name))

                            if iface.id != connectionManager.activeInterfaces.last?.id {
                                Divider().background(Color.ttBorder)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Bonjour Status Card

    var bonjourStatusCard: some View {
        CardView(title: "BONJOUR STATUS") {
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                HStack(spacing: TTSpacing.sm) {
                    Text("Service")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextTertiary)
                    Text(BonjourAdvertiser.serviceType)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextSecondary)
                }

                Divider().background(Color.ttBorder)

                let enabledIfaces = connectionManager.activeInterfaces
                    .filter { connectionManager.isInterfaceEnabled($0.name) }

                if enabledIfaces.isEmpty {
                    TTBanner(
                        kind: .warning,
                        message: "All interfaces disabled — enable at least one above"
                    )
                } else {
                    ForEach(enabledIfaces) { iface in
                        HStack(spacing: TTSpacing.md) {
                            let port = connectionManager.serverPorts[iface.name]
                            let kind: TTBannerKind = port != nil ? .success : .warning
                            Image(systemName: port != nil ? "checkmark.circle.fill" : "clock.fill")
                                .font(TTFont.labelLarge)
                                .foregroundColor(kind.foreground)

                            Text(iface.name)
                                .font(TTFont.codeMedium)
                                .foregroundColor(.ttTextPrimary)

                            if let port {
                                Text("→ :" + String(port))
                                    .font(TTFont.codeSmall)
                                    .foregroundColor(.ttTextSecondary)
                            }

                            Spacer()

                            TTStatusPill(
                                text: port != nil ? "Advertising" : "Waiting…",
                                kind: kind
                            )
                        }
                        .padding(.vertical, TTSpacing.xxs)
                    }
                }
            }
        }
    }

    // MARK: Connected Devices Card

    var connectedDevicesCard: some View {
        CardView(title: "DEVICE NETWORK DETAILS") {
            VStack(spacing: 0) {
                ForEach(connectionManager.connectedDevices) { session in
                    VStack(alignment: .leading, spacing: TTSpacing.sm) {
                        HStack(spacing: TTSpacing.inputPaddingH) {
                            Image(systemName: session.isSimulator ? AppIcon.simulator : AppIcon.device)
                                .font(TTFont.codeLarge)
                                .foregroundColor(session.isOnline(relativeTo: connectionManager.uiNow) ? .ttSuccess : .ttTextTertiary)
                            Text(session.displayName)
                                .font(TTFont.labelLarge)
                                .foregroundColor(.ttTextPrimary)
                            // Same chip as Sidebar (Phase 9) — same device must read the same
                            // channel wherever it's shown.
                            ChannelChip(channel: session.connectionChannel, style: .full)
                            Spacer()
                            let elapsed = Int(session.heartbeatAge(relativeTo: connectionManager.uiNow))
                            Text("♥ \(elapsed)s ago")
                                .font(TTFont.codeSmall)
                                .foregroundColor(
                                    session.isOnline(relativeTo: connectionManager.uiNow)
                                        ? (session.isHeartbeatWarning(relativeTo: connectionManager.uiNow) ? .ttWarning : .ttSuccess)
                                        : .ttError
                                )
                        }

                        HStack(spacing: TTSpacing.lg) {
                            if let ip = session.latestDiagnostics?.localIP {
                                Label(ip, systemImage: "network")
                                    .font(TTFont.codeSmall)
                                    .foregroundColor(.ttTextSecondary)

                                // Subnet match
                                let devicePrefix = ip.split(separator: ".").prefix(3).joined(separator: ".")
                                let matched = connectionManager.allNetworkPrefixes.values.contains(devicePrefix)
                                Label(matched ? "Same subnet" : "Different subnet",
                                      systemImage: matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(TTFont.labelSmall)
                                    .foregroundColor(matched ? .ttSuccess : .ttError)
                            } else {
                                Text("Waiting for diagnostics...")
                                    .font(TTFont.bodySmall)
                                    .foregroundColor(.ttTextTertiary)
                            }
                        }
                        .padding(.leading, TTSpacing.xxl)
                    }
                    .padding(.vertical, TTSpacing.sm)

                    if session.id != connectionManager.connectedDevices.last?.id {
                        Divider().background(Color.ttBorder)
                    }
                }
            }
        }
    }

    // MARK: Interface Kind Badge

    func ifaceBadge(_ kind: InterfaceKind) -> some View {
        let bannerKind: TTBannerKind
        switch kind {
        case .wifi:     bannerKind = .success
        case .ethernet: bannerKind = .info
        case .vpn:      bannerKind = .info
        case .other:    bannerKind = .info
        }
        return HStack(spacing: TTSpacing.xxs) {
            Image(systemName: kind.icon)
                .font(TTFont.badge)
            Text(kind.rawValue.uppercased())
                .font(TTFont.badge)
        }
        .foregroundColor(bannerKind.foreground)
        .padding(.horizontal, TTSpacing.rowVertical)
        .padding(.vertical, TTSpacing.inlineGapSmall)
        .background(
            Capsule()
                .fill(bannerKind.background)
                .overlay(Capsule().stroke(bannerKind.border.opacity(0.55), lineWidth: 1))
        )
    }
}

#Preview {
    ConnectionHealthView()
        .environment(ConnectionManager())
        .frame(width: 900, height: 800)
        .preferredColorScheme(.dark)
}
