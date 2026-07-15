//
//  SettingsView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Production hardening: honest connection settings (no dead controls), accurate shortcuts.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager
    @Environment(DesignSystemConfig.self) private var designConfig
    @AppStorage("appAppearance") private var appearance: String = "system"
    @AppStorage("maxLogEntries") private var maxLogEntries: Int = 10000
    @AppStorage("autoCleanupDays") private var autoCleanupDays: Int = 30
    @AppStorage("maskAuthHeaders") private var maskAuthHeaders: Bool = true
    @AppStorage("showTimestamps") private var showTimestamps: Bool = true
    @AppStorage("jsonIndentation") private var jsonIndentation: Int = 2
    @AppStorage("autoStartServer") private var autoStartServer: Bool = false
    // Relay Server no longer has its own enable toggle (Phase 4) — it starts/stops with the
    // main Server above. Only its port remains a separate setting.
    @AppStorage("relayServerPort") private var relayServerPort: Int = 51820
    @AppStorage("relayClientEnabled") private var relayClientEnabled: Bool = false
    @AppStorage("relayClientHost") private var relayClientHost: String = ""
    @AppStorage("relayClientPort") private var relayClientPort: Int = 51820

    // Draft layout metrics — applied only when the user taps Apply.
    @State private var draftFontScale: Double = 1.0
    @State private var draftSpacingScale: Double = 1.0
    @State private var draftLineHeightExtra: Double = 0
    @State private var draftTextEmphasis: TTTextEmphasis = .regular
    @State private var launchAtLogin = LaunchAtLoginService.shared

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: AppIcon.settings)
                }

            connectionSettings
                .tabItem {
                    Label("Connection", systemImage: AppIcon.connectionHealth)
                }

            relaySettings
                .tabItem {
                    Label("Relay", systemImage: "arrow.triangle.branch")
                }

            PermissionsView()
                .tabItem {
                    Label("Permissions", systemImage: AppIcon.permissions)
                }

            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: AppIcon.storage)
                }

            devToolsSettings
                .tabItem {
                    Label("Dev Tools", systemImage: AppIcon.devTools)
                }

            privacySettings
                .tabItem {
                    Label("Privacy", systemImage: AppIcon.privacy)
                }
        }
        .frame(width: 580, height: 620)
    }

    // MARK: - General
    private var generalSettings: some View {
        Form {
            Section("Startup") {
                Toggle("Open at Login", isOn: launchAtLoginBinding)
                    .disabled(!launchAtLogin.isToggleAvailable)
                if let detail = launchAtLogin.detailMessage {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.ttTextSecondary)
                }
                if launchAtLogin.shouldOfferSystemSettingsLink {
                    Button("Open Login Items…") {
                        launchAtLogin.openSystemSettingsLoginItems()
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Text("System matches macOS Appearance (Light/Dark).")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)

                Toggle("Show Timestamps", isOn: $showTimestamps)

                Stepper("JSON Indentation: \(jsonIndentation) spaces", value: $jsonIndentation, in: 1...8)
                Text("Used by JSON Editor format / Auto Fix pretty-print.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

            typographySpacingSection

            Section("Keyboard Shortcuts") {
                shortcutRow("Clear Console", "⌘K")
                shortcutRow("Capture Screenshot", "⇧⌘C")
                shortcutRow("Export Session", "⇧⌘E")
                shortcutRow("Import Session", "⇧⌘I")
                shortcutRow("Force Reconnect", "⇧⌘R")
                shortcutRow("JSON Format", "⌘B")
                shortcutRow("JSON Auto Fix", "⇧⌘.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadLayoutDraftFromApplied()
            launchAtLogin.refresh()
        }
        .onChange(of: designConfig.appliedRevision) { _, _ in
            loadLayoutDraftFromApplied()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    // MARK: - Typography & Spacing (draft → Apply)

    private var typographySpacingSection: some View {
        Section {
            // Density presets
            Picker("Density", selection: densityPresetBinding) {
                ForEach(TTDensityPreset.allCases) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
                Text("Custom").tag(Optional<TTDensityPreset>.none)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("UI density preset")
            .accessibilityHint("Choose Compact, Default, Comfortable, or Large layout density")

            if let preset = selectedDensityPreset {
                Text(preset.detail)
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
                    .accessibilityLabel(preset.detail)
            } else {
                Text("Custom values — outside the named density presets.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

            // Text emphasis
            Picker("Text Emphasis", selection: $draftTextEmphasis) {
                ForEach(TTTextEmphasis.allCases) { emphasis in
                    Text(emphasis.title).tag(emphasis)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Text emphasis")
            .accessibilityHint("Regular keeps default weights; Medium slightly strengthens body and labels")
            Text("Medium slightly strengthens label and body weights without changing sizes.")
                .font(.caption)
                .foregroundColor(.ttTextSecondary)

            // Advanced sliders
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                Text("Advanced")
                    .font(.headline)

                layoutSlider(
                    title: "Font Size",
                    value: $draftFontScale,
                    range: fontScaleSliderRange,
                    format: { String(format: "%.2f×", $0) }
                )

                layoutSlider(
                    title: "Spacing",
                    value: $draftSpacingScale,
                    range: spacingScaleSliderRange,
                    format: { String(format: "%.2f×", $0) }
                )

                layoutSlider(
                    title: "Line Height",
                    value: $draftLineHeightExtra,
                    range: lineHeightSliderRange,
                    format: { String(format: "+%.1f pt", $0) }
                )
            }
            .padding(.vertical, TTSpacing.xxs)

            // Live preview of draft (does not affect the rest of the app until Apply)
            layoutPreviewCard

            HStack {
                Button("Reset to Default") {
                    draftFontScale = Double(TTDensityPreset.default.fontScale)
                    draftSpacingScale = Double(TTDensityPreset.default.spacingScale)
                    draftLineHeightExtra = Double(TTDensityPreset.default.lineHeightExtra)
                    draftTextEmphasis = .regular
                }
                .disabled(!hasLayoutDraftChanges && isDraftAtDefault)
                .accessibilityLabel("Reset typography and spacing to default")
                .accessibilityHint("Restores Default density and Regular text emphasis in the draft")

                Spacer()

                Button("Apply") {
                    designConfig.apply(
                        fontScale: CGFloat(draftFontScale),
                        spacingScale: CGFloat(draftSpacingScale),
                        lineHeightExtra: CGFloat(draftLineHeightExtra),
                        textEmphasis: draftTextEmphasis
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasLayoutDraftChanges)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Apply typography and spacing")
                .accessibilityHint("Applies draft layout metrics to the main window and menu bar")
            }

            if hasLayoutDraftChanges {
                Text("Changes are not applied until you press Apply. Main window and menu bar update together.")
                    .font(.caption)
                    .foregroundColor(.ttWarning)
            } else {
                Text("Typography and spacing use the shared design system with safe min/max clamps to protect layout.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }
        } header: {
            Text("Typography & Spacing")
        }
    }

    private var fontScaleSliderRange: ClosedRange<Double> {
        Double(DesignSystemConfig.fontScaleRange.lowerBound)...Double(DesignSystemConfig.fontScaleRange.upperBound)
    }

    private var spacingScaleSliderRange: ClosedRange<Double> {
        Double(DesignSystemConfig.spacingScaleRange.lowerBound)...Double(DesignSystemConfig.spacingScaleRange.upperBound)
    }

    private var lineHeightSliderRange: ClosedRange<Double> {
        Double(DesignSystemConfig.lineHeightExtraRange.lowerBound)...Double(DesignSystemConfig.lineHeightExtraRange.upperBound)
    }

    private var selectedDensityPreset: TTDensityPreset? {
        TTDensityPreset.allCases.first {
            abs($0.fontScale - CGFloat(draftFontScale)) < 0.001
                && abs($0.spacingScale - CGFloat(draftSpacingScale)) < 0.001
                && abs($0.lineHeightExtra - CGFloat(draftLineHeightExtra)) < 0.001
        }
    }

    private var densityPresetBinding: Binding<TTDensityPreset?> {
        Binding(
            get: { selectedDensityPreset },
            set: { newValue in
                guard let preset = newValue else { return }
                draftFontScale = Double(preset.fontScale)
                draftSpacingScale = Double(preset.spacingScale)
                draftLineHeightExtra = Double(preset.lineHeightExtra)
            }
        )
    }

    private var hasLayoutDraftChanges: Bool {
        abs(CGFloat(draftFontScale) - designConfig.fontScale) > 0.0005
            || abs(CGFloat(draftSpacingScale) - designConfig.spacingScale) > 0.0005
            || abs(CGFloat(draftLineHeightExtra) - designConfig.lineHeightExtra) > 0.0005
            || draftTextEmphasis != designConfig.textEmphasis
    }

    private var isDraftAtDefault: Bool {
        abs(draftFontScale - 1.0) < 0.0005
            && abs(draftSpacingScale - 1.0) < 0.0005
            && abs(draftLineHeightExtra) < 0.0005
            && draftTextEmphasis == .regular
    }

    private func loadLayoutDraftFromApplied() {
        draftFontScale = Double(designConfig.fontScale)
        draftSpacingScale = Double(designConfig.spacingScale)
        draftLineHeightExtra = Double(designConfig.lineHeightExtra)
        draftTextEmphasis = designConfig.textEmphasis
    }

    private func layoutSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: TTSpacing.xxs) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(TTFont.codeMedium)
                    .foregroundColor(.ttTextSecondary)
                    .monospacedDigit()
                    .accessibilityLabel("\(title) value \(format(value.wrappedValue))")
            }
            Slider(value: value, in: range, step: title == "Line Height" ? 0.5 : 0.01)
                .accessibilityLabel(title)
                .accessibilityValue(format(value.wrappedValue))
                .accessibilityHint("Adjusts draft \(title.lowercased()); press Apply to commit")
        }
    }

    /// Draft-only preview: temporarily scales sample metrics without mutating applied config.
    private var layoutPreviewCard: some View {
        let previewFont = Font.system(
            size: DesignSystemConfig.shared.scaledFontPreview(
                base: 13,
                fontScale: CGFloat(draftFontScale)
            ),
            weight: draftTextEmphasis == .medium ? .medium : .regular
        )
        let previewCode = Font.system(
            size: DesignSystemConfig.shared.scaledFontPreview(
                base: 12,
                fontScale: CGFloat(draftFontScale)
            ),
            weight: .regular,
            design: .monospaced
        )
        let gap = max(4, 8 * CGFloat(draftSpacingScale))

        return VStack(alignment: .leading, spacing: gap) {
            Text("Preview")
                .font(.caption)
                .foregroundColor(.ttTextSecondary)
            Text("Sidebar · Network · JSON")
                .font(previewFont)
                .lineSpacing(CGFloat(draftLineHeightExtra))
                .foregroundColor(.ttTextPrimary)
            Text("{ \"status\": 200 }")
                .font(previewCode)
                .lineSpacing(CGFloat(draftLineHeightExtra))
                .foregroundColor(.ttTextSecondary)
            HStack(spacing: gap) {
                Text("GET")
                    .font(.system(size: DesignSystemConfig.shared.scaledFontPreview(base: 10, fontScale: CGFloat(draftFontScale)), weight: .bold, design: .monospaced))
                    .padding(.horizontal, max(6, 8 * CGFloat(draftSpacingScale)))
                    .padding(.vertical, max(2, 3 * CGFloat(draftSpacingScale)))
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.ttPrimary.opacity(0.2)))
                Text("Label")
                    .font(previewFont)
                    .foregroundColor(.ttTextSecondary)
            }
        }
        .padding(max(10, 12 * CGFloat(draftSpacingScale)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ttSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.ttBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Connection (read-only runtime facts — no dead steppers)
    private var connectionSettings: some View {
        Form {
            Section("Startup") {
                Toggle("Start server automatically when TTBDebugPlus opens", isOn: $autoStartServer)
                Text("Off by default (tools-first). Dev Tools work without the server; turn this on if you want the debug bridge ready as soon as the app launches.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

            Section("Bonjour Service") {
                LabeledContent("Service Type") {
                    Text("_ttbdebug._tcp")
                        .font(.body.monospaced())
                        .foregroundColor(.ttTextSecondary)
                }

                LabeledContent("Status") {
                    Text(connectionStatusLabel)
                        .foregroundColor(connectionStatusColor)
                }

                if connectionManager.serverPorts.isEmpty {
                    Text("Ports are assigned by the system when the server starts (dynamic bind).")
                        .font(.caption)
                        .foregroundColor(.ttTextSecondary)
                } else {
                    ForEach(connectionManager.serverPorts.sorted(by: { $0.key < $1.key }), id: \.key) { name, port in
                        LabeledContent(name) {
                            Text(":\(port)")
                                .font(.body.monospaced())
                                .foregroundColor(.ttTextSecondary)
                        }
                    }
                }
            }

            Section("Heartbeat Policy") {
                LabeledContent("UI online window") {
                    Text("15s")
                        .foregroundColor(.ttTextSecondary)
                }
                LabeledContent("Hard disconnect") {
                    Text("20s without heartbeat")
                        .foregroundColor(.ttTextSecondary)
                }
                Text("iOS SDK sends heartbeats; macOS cancels the socket after the hard timeout and waits for reconnect.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

            Section("Tips") {
                Text("Start the server from the sidebar or menu bar, keep Mac and iOS on the same Wi‑Fi (or use simulator), and allow Local Network when prompted.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var connectionStatusLabel: String {
        if connectionManager.isServerRunning { return "Advertising" }
        if connectionManager.isLifecycleActive { return "Starting / recovering" }
        return "Stopped"
    }

    private var connectionStatusColor: Color {
        if connectionManager.isServerRunning { return .ttSuccess }
        if connectionManager.isLifecycleActive { return .ttWarning }
        return .ttTextMuted
    }

    // MARK: - Relay (Phase 3, simplified Phase 4)

    /// Relay Server is folded into the main Server On/Off (`ConnectionManager.startServer`) —
    /// no separate enable toggle. This one Mac is automatically both the relay AND its own
    /// viewer, with no loopback and no second machine needed. See
    /// plans/2026-07-13-connection-reliability/phase-04-single-app-relay-and-fanout-proposal.md.
    private var relaySettings: some View {
        Form {
            Section("Relay Server") {
                Text("Starts automatically with the main Server. Other Macs join via \"Connect to a Relay Server\" below, using this Mac's address — no separate Mac or app needed just to relay.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)

                Stepper("Port: \(relayServerPort)", value: $relayServerPort, in: 1024...65535)
                    .onChange(of: relayServerPort) { _, newValue in
                        connectionManager.setRelayServerPort(UInt16(clamping: newValue))
                    }

                if connectionManager.isLifecycleActive {
                    LabeledContent("Status") {
                        Text(connectionManager.relayServer.status.isRunning ? "Listening" : "Starting…")
                            .foregroundColor(connectionManager.relayServer.status.isRunning ? .ttSuccess : .ttWarning)
                    }
                    LabeledContent("Producers (iOS devices)") {
                        Text("\(connectionManager.relayServer.status.producerCount)")
                    }
                    LabeledContent("Remote viewers (other Macs)") {
                        Text("\(connectionManager.relayServer.status.viewerCount)")
                    }
                    if let error = connectionManager.relayServer.status.lastError {
                        Text(error).font(.caption).foregroundColor(.ttError)
                    }

                    relayPairingQRSection
                } else {
                    LabeledContent("Status") {
                        Text("Off — start the Server to enable relay")
                            .foregroundColor(.ttTextMuted)
                    }
                }
            }

            Section("Relay Client") {
                Toggle("Connect to a Relay Server", isOn: Binding(
                    get: { relayClientEnabled },
                    set: { newValue in
                        relayClientEnabled = newValue
                        if newValue {
                            connectionManager.setRelayClientEnabled(true, host: relayClientHost, port: UInt16(clamping: relayClientPort))
                        } else {
                            connectionManager.setRelayClientEnabled(false, host: relayClientHost, port: UInt16(clamping: relayClientPort))
                        }
                    }
                ))
                TextField("Relay host or IP", text: $relayClientHost)
                    .disabled(relayClientEnabled)
                    .onSubmit { restartRelayClientIfEnabled() }
                Stepper("Port: \(relayClientPort)", value: $relayClientPort, in: 1024...65535)
                    .disabled(relayClientEnabled)
                    .onChange(of: relayClientPort) { _, _ in restartRelayClientIfEnabled() }

                if relayClientEnabled {
                    LabeledContent("Status") {
                        Text(connectionManager.relayClient.status.isConnected ? "Connected" : "Connecting…")
                            .foregroundColor(connectionManager.relayClient.status.isConnected ? .ttSuccess : .ttWarning)
                    }
                    if let error = connectionManager.relayClient.status.lastError {
                        Text(error).font(.caption).foregroundColor(.ttError)
                    }
                }

                Text("See devices connected to a relay elsewhere — useful when you're not on the same network as the iPhone (remote/WFH testing). Devices show up in the sidebar exactly like local ones.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func restartRelayClientIfEnabled() {
        guard relayClientEnabled else { return }
        connectionManager.setRelayClientEnabled(true, host: relayClientHost, port: UInt16(clamping: relayClientPort))
    }

    // MARK: - Relay Pairing QR (Phase 8)

    /// Distinct from the LAN-pairing QR in Connection Health (`ttbdebug://<ip>:<port>`, no
    /// query string) — this one uses `ttbdebug://pair?type=relay&...`, scanned via the iOS SDK's
    /// `TTDebugBridge.applyRelayConfig(fromQRPayload:)` to persist `config.relayHost`/`relayPort`
    /// across app launches, instead of a one-off manual connect.
    private var relayPairingQRSection: some View {
        Group {
            if let ip = connectionManager.macLocalIP {
                let pairingString = "ttbdebug://pair?type=relay&host=\(ip)&port=\(relayServerPort)&v=1"
                VStack(alignment: .leading, spacing: TTSpacing.sm) {
                    Text("Scan to configure a relay-only app (Settings won't need editing again after this):")
                        .font(.caption)
                        .foregroundColor(.ttTextSecondary)

                    if let qrImage = QRCodeEngine.generate(
                        payload: pairingString,
                        correction: .medium, foreground: .black, background: .white, size: 200
                    ) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 140, height: 140)
                            .padding(TTSpacing.xs)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                    }

                    Text(pairingString)
                        .font(.caption2.monospaced())
                        .foregroundColor(.ttTextTertiary)
                        .textSelection(.enabled)
                }
                .padding(.top, TTSpacing.xxs)
            }
        }
    }

    // MARK: - Dev Tools
    private var devToolsSettings: some View {
        Form {
            Section("JSON Editor") {
                Stepper("Default Indentation: \(jsonIndentation) spaces", value: $jsonIndentation, in: 1...8)

                Text("Shared with General → JSON Indentation.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

            Section("Available Tools") {
                toolStatusRow(icon: AppIcon.json, title: "JSON Editor", available: true)
                toolStatusRow(icon: AppIcon.templateLibrary, title: "Template Library", available: true)
                toolStatusRow(icon: AppIcon.qrCode, title: "QR Code", available: true)
                toolStatusRow(icon: AppIcon.caseConverter, title: "Case Converter", available: true)
                toolStatusRow(icon: AppIcon.jwt, title: "JWT Debugger", available: true)
                toolStatusRow(icon: AppIcon.base64, title: "Base64 Encoder/Decoder", available: false)
                toolStatusRow(icon: AppIcon.urlEncode, title: "URL Encoder/Decoder", available: false)
            }

            Section("Shortcuts") {
                shortcutRow("Open Dev Tools", "⌘5")
                shortcutRow("Format JSON", "⌘B")
                shortcutRow("Auto Format JSON", "⇧⌘F")
                shortcutRow("Auto Fix JSON", "⇧⌘.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Privacy
    private var privacySettings: some View {
        Form {
            Section("Data Masking") {
                Toggle("Mask Authorization Headers in HAR export", isOn: $maskAuthHeaders)
                Text("When enabled, Authorization headers are redacted when exporting HAR from the Network inspector.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

            Section("Security") {
                Text("All device communication is local network only — no telemetry or remote analytics are sent by TTBDebugPlus.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)

                Text("Session data, templates, and tokens stay local under Application Support. This build runs without App Sandbox (DMG/dev-tool distribution) so Live Ports can inspect local listeners.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Helpers

    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextSecondary)
        }
    }

    private func toolStatusRow(icon: String, title: String, available: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(available ? .ttPrimary : .ttTextMuted)
            Text(title)
            Spacer()
            Text(available ? "Available" : "Coming Soon")
                .font(.caption)
                .foregroundColor(available ? .ttSuccess : .ttTextMuted)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(ConnectionManager())
        .environment(StorageManager())
        .environment(DesignSystemConfig.shared)
}
