//
//  TTBDebugPlusApp.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Production hardening 2026-07-10: safe UTType, appearance, session lifecycle, export UX.
//

import SwiftUI
import AppKit
import SwiftData
import UniformTypeIdentifiers

@main
struct TTBDebugPlusApp: App {
    @State private var appState = AppState()
    @State private var connectionManager = ConnectionManager()
    @State private var sessionManager = SessionManager()
    @State private var storageManager = StorageManager()
    @State private var libraryStore = LibraryStore()
    @State private var tokenStore = TokenStore()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    /// Default follows macOS System Settings (user can force light/dark in app Settings).
    /// Key `appAppearance` supersedes legacy `appearance` (which defaulted to forced dark).
    @AppStorage("appAppearance") private var appearance: String = "system"
    /// On by default — start the debug bridge when the app launches so devices can
    /// connect immediately. Toggle lives in Settings → Connection.
    @AppStorage("autoStartServer") private var autoStartServer: Bool = true
    // Relay Server (Phase 4) — no separate enable toggle; starts automatically with the main
    // Server above. Only its port is a standalone setting, restored on launch.
    @AppStorage("relayServerPort") private var relayServerPort: Int = 51820
    @AppStorage("relayClientEnabled") private var relayClientEnabled: Bool = false
    @AppStorage("relayClientHost") private var relayClientHost: String = ""
    @AppStorage("relayClientPort") private var relayClientPort: Int = 51820
    @State private var showWelcome: Bool = false
    @State private var appErrorMessage: String?
    @State private var didRegisterTerminateObserver = false

    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView()
                .environment(appState)
                .environment(connectionManager)
                .environment(sessionManager)
                .environment(storageManager)
                .environment(libraryStore)
                .environment(tokenStore)
                .modelContainer(libraryStore.container)
                .preferredColorScheme(preferredScheme)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    connectionManager.sessionRecorder = sessionManager
                    if !hasSeenWelcome {
                        showWelcome = true
                    }
                    registerAppTerminateHandlerIfNeeded()
                    // Set before startServer() so the very first relay listener binds to the
                    // persisted port instead of the in-memory default.
                    connectionManager.relayServerPort = UInt16(clamping: relayServerPort)
                    if autoStartServer && !connectionManager.isLifecycleActive {
                        connectionManager.startServer()
                    }
                    if relayClientEnabled, !relayClientHost.isEmpty {
                        connectionManager.setRelayClientEnabled(true, host: relayClientHost, port: UInt16(clamping: relayClientPort))
                    }
                }
                .sheet(isPresented: $showWelcome) {
                    hasSeenWelcome = true
                } content: {
                    WelcomeSheet(isPresented: $showWelcome)
                }
                .alert("Operation Failed", isPresented: Binding(
                    get: { appErrorMessage != nil },
                    set: { if !$0 { appErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { appErrorMessage = nil }
                } message: {
                    Text(appErrorMessage ?? "")
                }
        }
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentMinSize)
        // Compact unified titlebar so content canvas meets traffic lights without a light strip
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Navigate") {
                Button("Console") { appState.selectedTab = .console }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Network") { appState.selectedTab = .network }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Device") { appState.selectedTab = .device }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Performance") { appState.selectedTab = .performance }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Dev Tools") { appState.openDevToolsMenu() }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Feedback") { appState.selectedTab = .feedback }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Connection Health") { appState.selectedTab = .connectionHealth }
                    .keyboardShortcut("7", modifiers: .command)
            }

            CommandMenu("Debug") {
                Button("Clear Console") {
                    connectionManager.clearConsoleLogs()
                    NotificationCenter.default.post(name: .clearConsole, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Capture Screenshot") {
                    connectionManager.requestScreenshot()
                    NotificationCenter.default.post(name: .captureScreenshot, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button("Export Session...") {
                    exportCurrentSession()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import Session...") {
                    importSession()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button(connectionManager.isLifecycleActive ? "Stop Server" : "Start Server") {
                    connectionManager.toggleServer()
                }

                Button("Force Reconnect") {
                    connectionManager.forceReconnect()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!connectionManager.isLifecycleActive)

                Button("Restart Server") {
                    connectionManager.restartServer()
                }
                .disabled(!connectionManager.isLifecycleActive)
            }

            CommandGroup(replacing: .help) {
                Button("Show Welcome Guide") {
                    showWelcome = true
                }

                Button("Integration Guide") {
                    appState.selectedTab = .guide
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        MenuBarExtra(
            connectionManager.isServerRunning
                ? "TTBDebugPlus Server Running"
                : (connectionManager.isLifecycleActive
                   ? "TTBDebugPlus Server Starting"
                   : "TTBDebugPlus · Tools ready · Server stopped"),
            systemImage: connectionManager.isServerRunning
                ? AppIcon.connectionHealth
                : (connectionManager.isLifecycleActive ? AppIcon.reconnect : AppIcon.devToolsMode)
        ) {
            MenuBarView()
                .environment(appState)
                .environment(connectionManager)
                .environment(tokenStore)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(connectionManager)
                .environment(storageManager)
                .preferredColorScheme(preferredScheme)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        case "system": return nil // follow macOS appearance
        default: return nil // unknown → system (safe default)
        }
    }

    /// End session only on real app quit — not when a single window disappears.
    private func registerAppTerminateHandlerIfNeeded() {
        guard !didRegisterTerminateObserver else { return }
        didRegisterTerminateObserver = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [sessionManager, connectionManager] _ in
            sessionManager.endSession()
            if connectionManager.isLifecycleActive {
                connectionManager.stopServer()
            }
            connectionManager.relayServer.stop()
            connectionManager.relayClient.stop()
        }
    }

    // MARK: - Session Export/Import

    private func exportCurrentSession() {
        guard let session = sessionManager.currentSession else {
            appErrorMessage = "No active debug session to export. Connect a device and generate logs first, then try again."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.deviceName)_\(session.formattedDate).ttbdebug"
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try sessionManager.exportSession(session, to: url)
                } catch {
                    DispatchQueue.main.async {
                        appErrorMessage = "Could not export session: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func importSession() {
        let panel = NSOpenPanel()
        if let ttbType = UTType(filenameExtension: "ttbdebug") {
            panel.allowedContentTypes = [ttbType, .json, .data]
        } else {
            panel.allowedContentTypes = [.json, .data]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    _ = try sessionManager.importSession(from: url)
                } catch {
                    DispatchQueue.main.async {
                        appErrorMessage = "Could not import session: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let clearConsole = Notification.Name("clearConsole")
    static let captureScreenshot = Notification.Name("captureScreenshot")
    static let exportSession = Notification.Name("exportSession")
}
