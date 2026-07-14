//
//  MenuBarView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Menu bar extra content — quick access to server status, devices, and actions
//

import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var toolSearchText = ""
    @State private var selectedPopoverTool: DevTool?
    @State private var isToolPopoverPresented = false
    @State private var launchAtLoginStatus = SMAppService.mainApp.status
    @State private var launchAtLoginErrorMessage: String?
    
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
        if connectionManager.isServerRunning {
            let ports = connectionManager.serverPorts.values.sorted()
            guard !ports.isEmpty else {
                return "Waiting for network interface"
            }
            return ports.map { ":\($0)" }.joined(separator: "  ")
        }
        if connectionManager.isLifecycleActive {
            return "Binding ports…"
        }
        // Match main sidebar copy — tools-first default
        return "Tools ready · start when you need a device"
    }
    
    private var serverModeTitle: String {
        if connectionManager.isServerRunning {
            return "Server Active"
        }
        if connectionManager.isLifecycleActive {
            return "Server Starting…"
        }
        return "Server Stopped"
    }
    
    private var serverModeColor: Color {
        if connectionManager.isServerRunning {
            return .ttSuccess
        }
        if connectionManager.isLifecycleActive {
            return .ttWarning
        }
        return .ttError
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
            
            // MARK: - Server Status (primary control — full-width Start/Stop + tools)
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
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: 300)
        // Match app canvas — solid design token (no system/primary wash)
        .background(Color.ttBackground)
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
        .onAppear {
            refreshLaunchAtLoginStatus()
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
                
                Image(systemName: AppIcon.app)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ttTextOnAccent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(AppBrand.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)
                
                Text(AppBrand.versionLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ttTextTertiary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
            
            // Connection count badge
            if connectionManager.onlineDevices.count > 0 {
                Text("\(connectionManager.onlineDevices.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.ttTextOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.ttSuccess))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
    
    // MARK: - Server Status
    // Vertical stack matching main-window sidebar + attached design:
    // title → status line → full-width Start/Stop → icon tool row (never clipped).
    
    private var serverStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(serverModeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)
                
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(serverModeColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 3)
                    
                    Text(serverStatusDetail)
                        .font(.system(size: 11))
                        .foregroundColor(.ttTextSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Primary Start / Stop — reserved height for both styles (stable cold start)
            Group {
                if connectionManager.isLifecycleActive {
                    Button(action: toggleServer) {
                        Label("Stop Server", systemImage: AppIcon.stopServer)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttOutlined)
                    .accessibilityLabel("Stop Server")
                    .help("Stop the debug bridge server")
                } else {
                    Button(action: toggleServer) {
                        Label("Start Server", systemImage: AppIcon.startServer)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.ttPrimary)
                    .accessibilityLabel("Start Server")
                    .help("Start the debug bridge when you need a device connection")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            
            // Secondary server tools — fixed min height so icons never clip at panel edge
            HStack(spacing: 6) {
                DeviceSessionMenuButton()
                NetworkInterfaceMenuButton()
                
                Button(action: { connectionManager.forceReconnect() }) {
                    Image(systemName: AppIcon.reconnect)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(connectionManager.isLifecycleActive ? .ttWarning : .ttTextMuted)
                        .frame(width: 28, height: 28)
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
                .disabled(!connectionManager.isLifecycleActive)
                .help("Force Reconnect (restart Bonjour, keep logs)")
                .accessibilityLabel("Force Reconnect")
                
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ttSurface.opacity(0.45))
    }
    
    // MARK: - Devices
    
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONNECTED DEVICES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ttTextSecondary)
                .tracking(0.5)
                .padding(.horizontal, 12)
            
            if connectionManager.connectedDevices.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: AppIcon.connectionOffline)
                        .font(.system(size: 11))
                        .foregroundColor(.ttTextSecondary)
                    Text("No devices connected")
                        .font(.system(size: 11))
                        .foregroundColor(.ttTextSecondary)
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
                    .foregroundColor(.ttTextSecondary)
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
                    .foregroundColor(.ttTextSecondary)
                
                TextField("Search tools", text: $toolSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.ttTextPrimary)
                
                if !toolSearchText.isEmpty {
                    Button(action: { toolSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.ttTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.ttSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.ttBorder.opacity(0.6), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            
            VStack(spacing: 0) {
                HStack {
                    Text(toolSearchText.isEmpty ? "All tools" : "Search results")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.ttTextTertiary)
                    
                    Spacer()
                    
                    Text("\(filteredDevTools.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.ttTextTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                
                Divider()
                    .overlay(Color.ttBorder)
                
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        if filteredDevTools.isEmpty {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                    .foregroundColor(.ttTextTertiary)
                                Text("No matching tools")
                                    .font(.system(size: 11))
                                    .foregroundColor(.ttTextTertiary)
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
                    .fill(Color.ttSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.ttBorder.opacity(0.6), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            
            MenuBarActionButton(
                icon: AppIcon.devTools,
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
                icon: AppIcon.clearLogs,
                title: "Clear All Logs",
                shortcut: "⌘K"
            ) {
                connectionManager.clearAllLogs()
            }
            
            MenuBarActionButton(
                icon: AppIcon.screenshot,
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
                icon: AppIcon.mainWindow,
                title: "Open Full App",
                shortcut: ""
            ) {
                activateMainWindow(preferDevToolsIfServerStopped: true)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            launchAtLoginSetting
            
            Divider()
                .padding(.vertical, 4)
            
            MenuBarActionButton(
                icon: AppIcon.settings,
                title: "Preferences...",
                shortcut: "⌘,"
            ) {
                openAppSettings()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            MenuBarActionButton(
                icon: AppIcon.quit,
                title: "Quit TTBDebugPlus",
                shortcut: "⌘Q",
                isDestructive: true
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private var launchAtLoginSetting: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuBarToggleRow(
                icon: "power",
                title: "Open at Login",
                detail: launchAtLoginDetail,
                isOn: isLaunchAtLoginEnabled,
                isEnabled: isLaunchAtLoginToggleAvailable
            ) {
                setLaunchAtLoginEnabled(!isLaunchAtLoginEnabled)
            }
            
            if let launchAtLoginErrorMessage {
                Text(launchAtLoginErrorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.ttError)
                    .lineLimit(2)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - Navigation
    
    private func toggleServer() {
        connectionManager.toggleServer()
    }
    
    private func openDevTool(_ tool: DevTool) {
        appState.openDevTool(tool)
        activateMainWindow(preferDevToolsIfServerStopped: false)
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
        activateMainWindow(preferDevToolsIfServerStopped: false)
    }
    
    /// Opens the main window. When the server is stopped, optionally land on Dev Tools.
    private func activateMainWindow(preferDevToolsIfServerStopped: Bool) {
        if preferDevToolsIfServerStopped {
            appState.preferDevToolsWhenServerStopped(serverActive: connectionManager.isLifecycleActive)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main-window")
    }

    /// Open the SwiftUI `Settings` scene (reliable vs. private `showSettingsWindow:` selector).
    private func openAppSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
    
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                isLaunchAtLoginEnabled
            },
            set: { isEnabled in
                setLaunchAtLoginEnabled(isEnabled)
            }
        )
    }
    
    private var isLaunchAtLoginEnabled: Bool {
        switch launchAtLoginStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    private var isLaunchAtLoginToggleAvailable: Bool {
        switch launchAtLoginStatus {
        case .notFound:
            return false
        case .enabled, .requiresApproval, .notRegistered:
            return true
        @unknown default:
            return true
        }
    }
    
    private var launchAtLoginDetail: String? {
        switch launchAtLoginStatus {
        case .enabled:
            return "TTBDebugPlus will start when macOS opens."
        case .requiresApproval:
            return "Allow this app in System Settings > Login Items."
        case .notFound:
            return "Login item is unavailable for this build."
        case .notRegistered:
            return nil
        @unknown default:
            return nil
        }
    }
    
    private func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginErrorMessage = error.localizedDescription
        }
        
        refreshLaunchAtLoginStatus()
    }
    
    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = SMAppService.mainApp.status
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
                        .foregroundColor(tool.isAvailable ? .ttPrimary : .ttTextMuted)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tool.menuTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(tool.isAvailable ? .ttTextPrimary : .ttTextMuted)
                            .lineLimit(1)
                        
                        TTStatusPill(
                            text: tool.statusText.uppercased(),
                            kind: tool.isAvailable ? .success : .warning
                        )
                    }
                    
                    Text(tool.menuDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.ttTextSecondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                Image(systemName: tool.isAvailable ? "chevron.right" : "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor((isHovered || isSelected) && tool.isAvailable ? .ttPrimary : .ttTextMuted)
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
        if !tool.isAvailable { return Color.ttSurfaceLight.opacity(0.35) }
        return Color.ttPrimary.opacity((isHovered || isSelected) ? 0.2 : 0.12)
    }
    
    private var rowBackgroundColor: Color {
        if isSelected { return Color.ttPrimary.opacity(0.12) }
        return isHovered ? Color.ttSurfaceHover : Color.clear
    }
}

// MARK: - Tool Popover

struct MenuBarToolPopoverContent: View {
    let tool: DevTool
    let onOpenInMainWindow: () -> Void
    let onClose: () -> Void

    @State private var popoverSize: CGSize
    @State private var dragStartSize: CGSize?

    init(
        tool: DevTool,
        onOpenInMainWindow: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.tool = tool
        self.onOpenInMainWindow = onOpenInMainWindow
        self.onClose = onClose
        _popoverSize = State(initialValue: tool.savedMenuBarPopoverSize)
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                
                Divider()
                    .overlay(Color.ttBorder)
                
                toolContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: popoverSize.width, height: popoverSize.height)
            .background(Color.ttBackground)

            resizeHandle
        }
        .onChange(of: tool) { _, newTool in
            popoverSize = newTool.savedMenuBarPopoverSize
            dragStartSize = nil
        }
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
                    .foregroundColor(.ttTextSecondary)
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
        .background(Color.ttSurface)
    }

    private var resizeHandle: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 34, height: 34)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ttTextTertiary)
                .rotationEffect(.degrees(-45))
                .padding(.trailing, 5)
                .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .help("Drag to resize")
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let startSize = dragStartSize ?? popoverSize
                    dragStartSize = startSize
                    popoverSize = tool.clampedMenuBarPopoverSize(
                        CGSize(
                            width: startSize.width + value.translation.width,
                            height: startSize.height + value.translation.height
                        )
                    )
                }
                .onEnded { _ in
                    tool.saveMenuBarPopoverSize(popoverSize)
                    dragStartSize = nil
                }
        )
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
        case .jwt:
            JWTToolView()
        case .localhostServers:
            LocalhostServersView()
        case .colorPicker:
            ColorPickerToolView()
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
            .background(Color.ttSurface)
            
            Divider()
                .overlay(Color.ttBorder)
            
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
                .foregroundColor(.ttTextSecondary)
            
            Text(tool.menuTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ttTextPrimary)
            
            Text("This tool is not available yet.")
                .font(.system(size: 12))
                .foregroundColor(.ttTextSecondary)
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
        case .jwt:
            return CGSize(width: 1_020, height: 680)
        case .localhostServers:
            return CGSize(width: 1_040, height: 700)
        case .colorPicker:
            return CGSize(width: 980, height: 700)
        default:
            return CGSize(width: 520, height: 360)
        }
    }

    var minimumMenuBarPopoverSize: CGSize {
        switch self {
        case .json:
            return CGSize(width: 720, height: 480)
        case .qrCode:
            return CGSize(width: 900, height: 560)
        case .caseConverter:
            return CGSize(width: 860, height: 540)
        case .jwt:
            return CGSize(width: 760, height: 520)
        case .localhostServers:
            return CGSize(width: 800, height: 560)
        case .colorPicker:
            return CGSize(width: 760, height: 520)
        default:
            return CGSize(width: 420, height: 300)
        }
    }

    var maximumMenuBarPopoverSize: CGSize {
        CGSize(width: 1_600, height: 1_100)
    }

    var savedMenuBarPopoverSize: CGSize {
        let width = UserDefaults.standard.double(forKey: menuBarPopoverWidthKey)
        let height = UserDefaults.standard.double(forKey: menuBarPopoverHeightKey)

        guard width > 0, height > 0 else {
            return menuBarPopoverSize
        }

        return clampedMenuBarPopoverSize(CGSize(width: width, height: height))
    }

    func clampedMenuBarPopoverSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumMenuBarPopoverSize.width), maximumMenuBarPopoverSize.width),
            height: min(max(size.height, minimumMenuBarPopoverSize.height), maximumMenuBarPopoverSize.height)
        )
    }

    func saveMenuBarPopoverSize(_ size: CGSize) {
        let size = clampedMenuBarPopoverSize(size)
        UserDefaults.standard.set(size.width, forKey: menuBarPopoverWidthKey)
        UserDefaults.standard.set(size.height, forKey: menuBarPopoverHeightKey)
    }

    private var menuBarPopoverWidthKey: String {
        "menuBarPopoverSize.\(rawValue).width"
    }

    private var menuBarPopoverHeightKey: String {
        "menuBarPopoverSize.\(rawValue).height"
    }
}

// MARK: - Action Button

struct MenuBarToggleRow: View {
    let icon: String
    let title: String
    let detail: String?
    let isOn: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isEnabled ? .ttTextPrimary : .ttTextMuted)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isEnabled ? .ttTextPrimary : .ttTextMuted)
                        .lineLimit(1)

                    if let detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundColor(.ttTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                CompactSwitch(isOn: isOn, isEnabled: isEnabled)
            }
            .frame(minHeight: detail == nil ? 30 : 38)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered && isEnabled ? Color.ttSurfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct CompactSwitch: View {
    let isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(trackColor)
                .frame(width: 34, height: 20)

            Circle()
                .fill(isEnabled ? Color.ttTextPrimary : Color.ttTextTertiary)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                .padding(.horizontal, 2)
        }
        .animation(.easeInOut(duration: 0.12), value: isOn)
    }

    private var trackColor: Color {
        guard isEnabled else { return Color.ttSurfaceLight.opacity(0.45) }
        return isOn ? Color.ttPrimary : Color.ttSurfaceLight
    }
}

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
                    .foregroundColor(isDestructive ? .ttError : .ttTextPrimary)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(isDestructive ? .ttError : .ttTextPrimary)
                
                Spacer()
                
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.ttTextTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.ttSurfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
