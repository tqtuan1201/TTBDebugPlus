//
//  AppState.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//

import SwiftUI

// MARK: - App State
@Observable
class AppState {
    var selectedTab: AppTab = .console {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: "selectedTab") }
    }
    var selectedSidebarItem: SidebarSection = .devices
    var selectedDeviceId: String? = nil
    
    // Connection state
    var connectedDevices: [ConnectedDevice] = []
    var isServerRunning: Bool = false
    
    // Stats
    var totalEvents: Int = 0
    var memoryUsage: Double = 0
    var cpuUsage: Double = 0
    
    // JSON Editor payload (for "Open in JSON Editor" buttons)
    var jsonEditorPayload: JSONEditorPayload? = nil
    var requestedDevTool: DevTool? = nil
    var devToolsMenuRequestID = UUID()
    var devToolsToolRequestID = UUID()
    
    /// Navigate to the Dev Tools menu screen.
    func openDevToolsMenu() {
        requestedDevTool = nil
        devToolsMenuRequestID = UUID()
        selectedTab = .devtools
    }
    
    /// Navigate directly to a specific Dev Tool.
    func openDevTool(_ tool: DevTool) {
        requestedDevTool = tool
        devToolsToolRequestID = UUID()
        selectedTab = .devtools
    }
    
    /// Navigate to JSON Editor with a payload
    func openInJSONEditor(json: String, source: String) {
        jsonEditorPayload = JSONEditorPayload(json: json, sourceLabel: source)
        selectedTab = .devtools
    }
    
    init() {
        // Restore persisted tab selection
        if let saved = UserDefaults.standard.string(forKey: "selectedTab"),
           let tab = AppTab(rawValue: saved) {
            self.selectedTab = tab
        }
    }
}

// MARK: - Tab Navigation
enum AppTab: String, CaseIterable, Identifiable {
    case console            = "Console"
    case network            = "Network"
    case device             = "Device"
    case performance        = "Performance"
    case devtools           = "Dev Tools"
    case feedback           = "Feedback"
    case connectionHealth   = "Connection Health"
    case guide              = "Guide"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .console:           return "terminal"
        case .network:           return "network"
        case .device:            return "iphone"
        case .performance:       return "chart.xyaxis.line"
        case .devtools:          return "wrench.and.screwdriver"
        case .feedback:          return "bubble.left.and.text.bubble.right"
        case .connectionHealth:  return "network.badge.shield.half.filled"
        case .guide:             return "book.fill"
        }
    }
    
    /// Tabs shown in the main tab bar (excludes guide and connectionHealth — sidebar-only)
    static var tabBarCases: [AppTab] {
        allCases.filter { $0 != .guide && $0 != .connectionHealth }
    }
}

// MARK: - Sidebar Sections
enum SidebarSection: String, CaseIterable, Identifiable {
    case devices          = "DEVICES"
    case logs             = "LOGS"
    case network          = "NETWORK"
    case performance      = "PERFORMANCE"
    case devtools         = "DEV TOOLS"
    case connectionHealth = "CONNECTION HEALTH"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .devices:          return "desktopcomputer"
        case .logs:             return "doc.text"
        case .network:          return "antenna.radiowaves.left.and.right"
        case .performance:      return "chart.xyaxis.line"
        case .devtools:         return "wrench.and.screwdriver"
        case .connectionHealth: return "network.badge.shield.half.filled"
        }
    }
}

// MARK: - Connected Device Model
struct ConnectedDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var osVersion: String
    var appName: String
    var appVersion: String
    var isConnected: Bool
    var isSimulator: Bool
    
    var displayName: String {
        isSimulator ? "\(name) (Simulator)" : name
    }
    
    var statusText: String {
        isConnected ? "READY" : "OFFLINE"
    }
}
