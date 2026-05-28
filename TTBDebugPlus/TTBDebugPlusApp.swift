//
//  TTBDebugPlusApp.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//

import SwiftUI
import AppKit

@main
struct TTBDebugPlusApp: App {
    @State private var appState = AppState()
    @State private var connectionManager = ConnectionManager()
    @State private var sessionManager = SessionManager()
    @State private var storageManager = StorageManager()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @State private var showWelcome: Bool = false
    @State private var appErrorMessage: String?
    
    var body: some Scene {
        WindowGroup(id: "main-window") {
            ContentView()
                .environment(appState)
                .environment(connectionManager)
                .environment(sessionManager)
                .environment(storageManager)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1200, minHeight: 800)
                .onAppear {
                    // Show welcome on first launch  
                    if !hasSeenWelcome {
                        showWelcome = true
                    }
                }
                .onDisappear {
                    sessionManager.endSession()
                }
                .sheet(isPresented: $showWelcome) {
                    // Mark as seen when welcome is dismissed
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
        .commands {
            CommandGroup(replacing: .newItem) { }
            
            // Navigation menu
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
                    connectionManager.clearAllLogs()
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
                
                Button(connectionManager.isServerRunning ? "Stop Server" : "Start Server") {
                    if connectionManager.isServerRunning {
                        connectionManager.stopServer()
                    } else {
                        connectionManager.startServer()
                    }
                }
                
                Button("Force Reconnect") {
                    connectionManager.forceReconnect()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!connectionManager.isServerRunning)
                
                Button("Restart Server") {
                    connectionManager.restartServer()
                }
                .disabled(!connectionManager.isServerRunning)
            }
            
            // Help menu
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
        
        // MARK: - Menu Bar Extra
        MenuBarExtra(
            connectionManager.isServerRunning ? "TTBDebugPlus Server Running" : "TTBDebugPlus Server Offline",
            systemImage: connectionManager.isServerRunning
                ? AppIcon.connectionHealth
                : AppIcon.connectionOffline
        ) {
            MenuBarView()
                .environment(appState)
                .environment(connectionManager)
        }
        .menuBarExtraStyle(.window)
        
        // MARK: - Settings
        Settings {
            SettingsView()
                .environment(appState)
                .environment(connectionManager)
                .environment(storageManager)
        }
    }
    
    // MARK: - Session Export/Import
    
    private func exportCurrentSession() {
        guard let session = sessionManager.currentSession else {
            NotificationCenter.default.post(name: .exportSession, object: nil)
            return
        }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.deviceName)_\(session.formattedDate).ttbdebug"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try sessionManager.exportSession(session, to: url)
                } catch {
                    appErrorMessage = "Could not export session: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func importSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ttbdebug")!]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    _ = try sessionManager.importSession(from: url)
                } catch {
                    appErrorMessage = "Could not import session: \(error.localizedDescription)"
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
