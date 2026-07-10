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
    @AppStorage("appearance") private var appearance: String = "dark"
    @AppStorage("maxLogEntries") private var maxLogEntries: Int = 10000
    @AppStorage("autoCleanupDays") private var autoCleanupDays: Int = 30
    @AppStorage("maskAuthHeaders") private var maskAuthHeaders: Bool = true
    @AppStorage("showTimestamps") private var showTimestamps: Bool = true
    @AppStorage("jsonIndentation") private var jsonIndentation: Int = 2

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
        .frame(width: 560, height: 480)
    }

    // MARK: - General
    private var generalSettings: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)

                Toggle("Show Timestamps", isOn: $showTimestamps)

                Stepper("JSON Indentation: \(jsonIndentation) spaces", value: $jsonIndentation, in: 1...8)
                Text("Used by JSON Editor format / Auto Fix pretty-print.")
                    .font(.caption)
                    .foregroundColor(.ttTextSecondary)
            }

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
    }

    // MARK: - Connection (read-only runtime facts — no dead steppers)
    private var connectionSettings: some View {
        Form {
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

                Text("Session data, templates, and tokens stay inside the macOS app sandbox under Application Support.")
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
}
