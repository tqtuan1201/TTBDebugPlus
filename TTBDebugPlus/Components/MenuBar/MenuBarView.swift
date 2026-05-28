//
//  MenuBarView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Menu bar extra content — quick access to server status, devices, and actions
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager
    @Environment(\.openWindow) private var openWindow
    @State private var toolSearchText = ""
    @State private var selectedPopoverTool: DevTool?
    @State private var isToolPopoverPresented = false
    
    private var availableDevToolCount: Int {
        DevTool.allCases.filter(\.isAvailable).count
    }
    
    private var filteredDevTools: [DevTool] {
        let query = toolSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return DevTool.allCases }
        
        return DevTool.allCases.filter { tool in
            tool.menuTitle.lowercased().contains(query)
            || tool.rawValue.lowercased().contains(query)
            || tool.menuDescription.lowercased().contains(query)
        }
    }
    
    private var devToolListHeight: CGFloat {
        let visibleRows = min(max(filteredDevTools.count, 1), 5)
        return CGFloat(visibleRows * 46) + 12
    }
    
    private var serverStatusDetail: String {
        guard connectionManager.isServerRunning else {
            return "Tap Start to accept device connections"
        }
        
        let ports = connectionManager.serverPorts.values.sorted()
        guard !ports.isEmpty else {
            return "Waiting for network interface"
        }
        
        return ports.map { ":\($0)" }.joined(separator: "  ")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
            
            Divider()
                .padding(.vertical, 4)
            
            // MARK: - Server Status
            serverStatusSection
            
            Divider()
                .padding(.vertical, 4)
            
            // MARK: - Connected Devices
            devicesSection
            
            Divider()
                .padding(.vertical, 4)
            
            // MARK: - Dev Tools
            devToolsSection
            
            Divider()
                .padding(.vertical, 4)
            
            // MARK: - Quick Actions
            quickActionsSection
            
            Divider()
                .padding(.vertical, 4)
            
            // MARK: - App Actions
            appActionsSection
        }
        .padding(.vertical, 8)
        .frame(width: 340)
        .popover(isPresented: $isToolPopoverPresented, arrowEdge: .trailing) {
            if let selectedPopoverTool {
                MenuBarToolPopoverContent(
                    tool: selectedPopoverTool,
                    onOpenInMainWindow: {
                        openPopoverToolInMainWindow()
                    },
                    onClose: {
                        isToolPopoverPresented = false
                    }
                )
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.ttPrimary, Color.ttPrimaryDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("TTBDebugPlus")
                    .font(.system(size: 13, weight: .semibold))
                
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Connection count badge
            if connectionManager.onlineDevices.count > 0 {
                Text("\(connectionManager.onlineDevices.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.ttSuccess))
            }
        }
        .padding(.horizontal, 12)
    }
    
    // MARK: - Server Status
    
    private var serverStatusSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connectionManager.isServerRunning ? Color.ttSuccess : Color.ttError)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionManager.isServerRunning ? "Server Running" : "Server Offline")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(serverStatusDetail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            Button(action: toggleServer) {
                Text(connectionManager.isServerRunning ? "Stop" : "Start")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(connectionManager.isServerRunning ? .ttError : .ttSuccess)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(connectionManager.isServerRunning ? Color.ttError.opacity(0.14) : Color.ttSuccess.opacity(0.14))
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    
    // MARK: - Devices
    
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONNECTED DEVICES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 12)
            
            if connectionManager.connectedDevices.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("No devices connected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                ForEach(connectionManager.connectedDevices) { session in
                    MenuBarDeviceRow(session: session)
                }
            }
        }
    }
    
    // MARK: - Dev Tools
    
    private var devToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("DEV TOOLS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(availableDevToolCount)/\(DevTool.allCases.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.ttPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.ttPrimary.opacity(0.12)))
            }
            .padding(.horizontal, 12)
            
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                TextField("Search tools", text: $toolSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !toolSearchText.isEmpty {
                    Button(action: { toolSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 12)
            
            VStack(spacing: 0) {
                HStack {
                    Text(toolSearchText.isEmpty ? "All tools" : "Search results")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(filteredDevTools.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                
                Divider()
                    .background(Color.primary.opacity(0.08))
                
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        if filteredDevTools.isEmpty {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("No matching tools")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                        } else {
                            ForEach(filteredDevTools) { tool in
                                MenuBarDevToolRow(
                                    tool: tool,
                                    isSelected: selectedPopoverTool == tool && isToolPopoverPresented
                                ) {
                                    openDevToolPopover(tool)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(height: devToolListHeight + 29)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            
            MenuBarActionButton(
                icon: "square.grid.2x2",
                title: "All Dev Tools",
                shortcut: "⌘5"
            ) {
                openDevToolsMenu()
            }
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(spacing: 2) {
            MenuBarActionButton(
                icon: "trash",
                title: "Clear All Logs",
                shortcut: "⌘K"
            ) {
                connectionManager.clearAllLogs()
            }
            
            MenuBarActionButton(
                icon: "camera",
                title: "Capture Screenshot",
                shortcut: "⇧⌘C"
            ) {
                connectionManager.requestScreenshot()
            }
        }
    }
    
    // MARK: - App Actions
    
    private var appActionsSection: some View {
        VStack(spacing: 2) {
            MenuBarActionButton(
                icon: "macwindow",
                title: "Open Main Window",
                shortcut: ""
            ) {
                activateMainWindow()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            MenuBarActionButton(
                icon: "gearshape",
                title: "Preferences...",
                shortcut: "⌘,"
            ) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            MenuBarActionButton(
                icon: "power",
                title: "Quit TTBDebugPlus",
                shortcut: "⌘Q",
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    // MARK: - Navigation
    
    private func toggleServer() {
        if connectionManager.isServerRunning {
            connectionManager.stopServer()
        } else {
            connectionManager.startServer()
        }
    }
    
    private func openDevTool(_ tool: DevTool) {
        appState.openDevTool(tool)
        activateMainWindow()
    }
    
    private func openDevToolPopover(_ tool: DevTool) {
        guard tool.isAvailable else { return }
        selectedPopoverTool = tool
        isToolPopoverPresented = true
    }
    
    private func openPopoverToolInMainWindow() {
        guard let selectedPopoverTool else { return }
        isToolPopoverPresented = false
        openDevTool(selectedPopoverTool)
    }
    
    private func openDevToolsMenu() {
        appState.openDevToolsMenu()
        activateMainWindow()
    }
    
    private func activateMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main-window")
    }
}

// MARK: - Dev Tool Row

struct MenuBarDevToolRow: View {
    let tool: DevTool
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            guard tool.isAvailable else { return }
            action()
        }) {
            HStack(alignment: .center, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(iconBackgroundColor)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: tool.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tool.isAvailable ? .ttPrimary : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tool.menuTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(tool.isAvailable ? .primary : .secondary)
                            .lineLimit(1)
                        
                        Text(tool.statusText.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(tool.isAvailable ? .ttSuccess : .ttWarning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((tool.isAvailable ? Color.ttSuccess : Color.ttWarning).opacity(0.11))
                            )
                    }
                    
                    Text(tool.menuDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                Image(systemName: tool.isAvailable ? "chevron.right" : "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor((isHovered || isSelected) && tool.isAvailable ? .ttPrimary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(!tool.isAvailable)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tool.isAvailable ? "Open \(tool.menuTitle)" : "\(tool.menuTitle) — Coming Soon")
    }
    
    private var iconBackgroundColor: Color {
        if !tool.isAvailable { return Color.primary.opacity(0.05) }
        return Color.ttPrimary.opacity((isHovered || isSelected) ? 0.2 : 0.12)
    }
    
    private var rowBackgroundColor: Color {
        if isSelected { return Color.ttPrimary.opacity(0.12) }
        return isHovered ? Color.primary.opacity(0.08) : Color.clear
    }
}

// MARK: - Tool Popover

struct MenuBarToolPopoverContent: View {
    let tool: DevTool
    let onOpenInMainWindow: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
                .background(Color.ttBorder.opacity(0.3))
            
            toolContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: tool.menuBarPopoverSize.width, height: tool.menuBarPopoverSize.height)
        .background(Color.ttBackground)
    }
    
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.ttPrimary.opacity(0.16))
                    .frame(width: 32, height: 32)
                
                Image(systemName: tool.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ttPrimary)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.menuTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ttTextPrimary)
                
                Text("Menu Bar Tool")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onOpenInMainWindow) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("Open in main window")
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.ttSurface.opacity(0.22))
    }
    
    @ViewBuilder
    private var toolContent: some View {
        switch tool {
        case .json:
            MenuBarJSONToolPopoverView()
        case .qrCode:
            QRCodeToolView()
        case .caseConverter:
            CaseConverterToolView()
        default:
            MenuBarUnavailableToolView(tool: tool)
        }
    }
}

struct MenuBarJSONToolPopoverView: View {
    @State private var viewModel = JSONEditorViewModel()
    @State private var selectedJsonTool: JSONTool = .editor
    @State private var hoveredJsonTool: JSONTool?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(JSONTool.allCases) { tool in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                selectedJsonTool = tool
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tool.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(
                                selectedJsonTool == tool ? .white :
                                (hoveredJsonTool == tool ? .ttTextSecondary : .ttTextTertiary)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        selectedJsonTool == tool ? Color.ttPrimary.opacity(0.45) :
                                        (hoveredJsonTool == tool ? Color.ttSurface.opacity(0.45) : Color.clear)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            hoveredJsonTool = isHovered ? tool : nil
                        }
                        .help(tool.description)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color.ttSurface.opacity(0.1))
            
            Divider()
                .background(Color.ttBorder.opacity(0.25))
            
            jsonContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
    }
    
    @ViewBuilder
    private var jsonContent: some View {
        switch selectedJsonTool {
        case .editor:
            OnlineJsonEditorView(viewModel: viewModel)
        case .query:
            JSONQueryView(jsonString: viewModel.rawJSON)
        case .diff:
            JSONDiffView(initialLeft: viewModel.rawJSON)
        case .convert:
            JSONConvertView(jsonString: viewModel.rawJSON)
        case .graph:
            JSONGraphView(jsonString: viewModel.rawJSON)
        }
    }
}

struct MenuBarUnavailableToolView: View {
    let tool: DevTool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text(tool.menuTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("This tool is not available yet.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension DevTool {
    var menuBarPopoverSize: CGSize {
        switch self {
        case .json:
            return CGSize(width: 980, height: 640)
        case .qrCode:
            return CGSize(width: 1_040, height: 640)
        case .caseConverter:
            return CGSize(width: 920, height: 600)
        default:
            return CGSize(width: 520, height: 360)
        }
    }
}

// MARK: - Action Button

struct MenuBarActionButton: View {
    let icon: String
    let title: String
    let shortcut: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isDestructive ? .ttError : .primary)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(isDestructive ? .ttError : .primary)
                
                Spacer()
                
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
