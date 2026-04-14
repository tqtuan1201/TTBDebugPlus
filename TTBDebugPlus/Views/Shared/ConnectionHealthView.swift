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
    @State private var refreshTick: Int = 0
    @State private var timer: Timer?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero section
                heroSection
                
                // Status cards grid
                HStack(alignment: .top, spacing: 16) {
                    // Left: Server + Network
                    VStack(spacing: 16) {
                        serverStatusCard
                        networkInfoCard
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right: Troubleshooting + Device diagnostics
                    VStack(spacing: 16) {
                        troubleshootingCard
                        if let device = connectionManager.selectedDevice,
                           let diag = device.latestDiagnostics {
                            deviceDiagnosticsCard(device: device, diag: diag)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 800)
                
                // Quick start code
                quickStartCard
                    .frame(maxWidth: 800)
                
                // ── NEW: Multi-Interface Sections ─────────────────────────
                VStack(spacing: 16) {
                    networkInterfacesCard
                    bonjourStatusCard
                    if !connectionManager.connectedDevices.isEmpty {
                        connectedDevicesCard
                    }
                }
                .frame(maxWidth: 800)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ttBackground)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                refreshTick += 1
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
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
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.ttPrimary)
                    .symbolEffect(.variableColor.iterative, options: .repeating, value: refreshTick)
            }
            
            VStack(spacing: 6) {
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
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    icon: connectionManager.isServerRunning ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: connectionManager.isServerRunning ? .ttSuccess : .ttError,
                    label: "Bonjour Service",
                    value: connectionManager.isServerRunning ? "Running" : "Stopped"
                )
                
                if let port = connectionManager.serverPort {
                    statusRow(
                        icon: "network",
                        iconColor: .ttPrimary,
                        label: "Port",
                        value: String(port)
                    )
                }
                
                statusRow(
                    icon: "antenna.radiowaves.left.and.right",
                    iconColor: connectionManager.isServerRunning ? .ttSuccess : .ttTextTertiary,
                    label: "Advertising",
                    value: connectionManager.isServerRunning ? "_ttbdebug._tcp" : "Inactive"
                )
                
                statusRow(
                    icon: "iphone",
                    iconColor: .ttPrimary,
                    label: "Connected",
                    value: "\(connectionManager.onlineDevices.count) device(s)"
                )
                
                // ── Action Buttons ──────────────────────────────────────
                HStack(spacing: 8) {
                    if connectionManager.isServerRunning {
                        // Force Reconnect — restart Bonjour without clearing sessions
                        Button(action: { connectionManager.forceReconnect() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Force Reconnect")
                            }
                        }
                        .buttonStyle(.ttSecondary)

                        // Full Restart — tear down everything and start fresh
                        Button(action: { connectionManager.restartServer() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                Text("Restart Server")
                            }
                        }
                        .buttonStyle(.ttGhost)
                    } else {
                        Button(action: { connectionManager.startServer() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "play.circle.fill")
                                Text("Start Server")
                            }
                        }
                        .buttonStyle(.ttPrimary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Network Info Card
    
    private var networkInfoCard: some View {
        CardView(title: "NETWORK") {
            VStack(alignment: .leading, spacing: 10) {
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
    
    // MARK: - Troubleshooting Card
    
    private var troubleshootingCard: some View {
        CardView(title: "TROUBLESHOOTING CHECKLIST") {
            VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.top, 4)
                
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
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    icon: "iphone",
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Add this to your AppDelegate or SceneDelegate:")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                
                codeBlock("""
                #if DEBUG
                TTDebugBridge.shared.start()
                LogInterceptor.shared.install()
                
                // Optional: Show floating diagnostic pill
                TTDebugBridge.shared.showDiagnosticOverlay()
                #endif
                """)
                
                Text("For manual diagnostics, call in Xcode console:")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .padding(.top, 4)
                
                codeBlock("po TTDebugBridge.shared.printDiagnosticReport()")
            }
        }
    }
    
    // MARK: - Reusable Components
    
    private func statusRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
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
        HStack(spacing: 8) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(checked ? .ttSuccess : .ttTextTertiary)
            
            Text(text)
                .font(TTFont.bodySmall)
                .foregroundColor(checked ? .ttTextPrimary : .ttTextSecondary)
        }
    }
    
    private func hintItem(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.ttTextTertiary)
                .frame(width: 16, alignment: .center)
            
            Text(text)
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextSecondary)
        }
        .padding(.leading, 6)
    }
    
    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(TTFont.codeSmall)
            .foregroundColor(.ttJsonString)
            .padding(12)
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
                    .padding(.vertical, 6)
                } else {
                    ForEach(connectionManager.activeInterfaces) { iface in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
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
                                VStack(alignment: .leading, spacing: 2) {
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
                            .padding(.vertical, 8)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
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
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.ttWarning)
                        Text("All interfaces disabled — enable at least one above")
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttWarning)
                    }
                } else {
                    ForEach(enabledIfaces) { iface in
                        HStack(spacing: 12) {
                            let port = connectionManager.serverPorts[iface.name]
                            Image(systemName: port != nil ? "checkmark.circle.fill" : "clock.fill")
                                .font(.system(size: 13))
                                .foregroundColor(port != nil ? .ttSuccess : .ttWarning)

                            Text(iface.name)
                                .font(TTFont.codeMedium)
                                .foregroundColor(.ttTextPrimary)

                            if let port {
                                Text("→ :" + String(port))
                                    .font(TTFont.codeSmall)
                                    .foregroundColor(.ttTextSecondary)
                            }

                            Spacer()

                            Text(port != nil ? "Advertising" : "Waiting...")
                                .font(TTFont.labelSmall)
                                .foregroundColor(port != nil ? .ttSuccess : .ttWarning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill((port != nil ? Color.ttSuccess : Color.ttWarning).opacity(0.12)))
                        }
                        .padding(.vertical, 4)
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: session.isSimulator ? "laptopcomputer" : "iphone")
                                .font(.system(size: 14))
                                .foregroundColor(session.isOnline ? .ttSuccess : .ttTextTertiary)
                            Text(session.displayName)
                                .font(TTFont.labelLarge)
                                .foregroundColor(.ttTextPrimary)
                            Spacer()
                            let elapsed = Int(Date().timeIntervalSince(session.lastHeartbeat))
                            Text("♥ \(elapsed)s ago")
                                .font(TTFont.codeSmall)
                                .foregroundColor(elapsed < 10 ? .ttSuccess : .ttWarning)
                        }

                        HStack(spacing: 16) {
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
                        .padding(.leading, 24)
                    }
                    .padding(.vertical, 8)

                    if session.id != connectionManager.connectedDevices.last?.id {
                        Divider().background(Color.ttBorder)
                    }
                }
            }
        }
    }

    // MARK: Interface Kind Badge

    func ifaceBadge(_ kind: InterfaceKind) -> some View {
        let color: Color
        switch kind {
        case .wifi:     color = .ttSuccess
        case .ethernet: color = .ttInfo
        case .vpn:      color = Color(hex: "#A855F7")
        case .other:    color = .ttTextTertiary
        }
        return HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(kind.rawValue.uppercased())
                .font(TTFont.badge)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

#Preview {
    ConnectionHealthView()
        .environment(ConnectionManager())
        .frame(width: 900, height: 800)
        .preferredColorScheme(.dark)
}
