//
//  ContentView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Hardened 2026-07-10: full deviceId mirror, drive sync from ConnectionManager.uiNow
//  (no private 5s timer). Unified window chrome (no light titlebar strip).
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// One-time tip when launch lands with server stopped (tool-first default).
    @AppStorage("hasSeenServerStoppedTip") private var hasSeenServerStoppedTip: Bool = false
    @State private var showServerStoppedTip: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - Sidebar
            // Keep server chrome (Start/Stop) outside any split-view list chrome.
            // min width must fit full-width Start Server + tool icons.
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
                .background(Color.ttBackground)
        } detail: {
            // MARK: - Main Content Area
            VStack(spacing: 0) {
                // Top Tab Bar
                TabBarView()

                if showServerStoppedTip || appState.serverRequiredHint != nil {
                    serverGateBanner
                }

                // Content area based on selected tab
                mainContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Status Bar
                StatusBarView()
            }
            .background(Color.ttBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.ttBackground)
        // Empty system titles — they paint black on transparent titlebars.
        // Custom toolbar label uses explicit design-system white.
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                windowTitleLabel
            }
        }
        .toolbarBackground(Color.ttBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(colorScheme == .light ? .light : .dark, for: .windowToolbar)
        .appWindowChrome(
            prefersDark: colorScheme != .light,
            title: AppBrand.name,
            subtitle: AppBrand.tagline
        )
        .sheet(item: Binding(
            get: { appState.pendingTemplateDraft },
            set: { appState.pendingTemplateDraft = $0 }
        )) { draft in
            SaveTemplateSheet(draft: draft)
        }
        .onAppear {
            syncAppStateFromConnectionManager()
            // Defer tip + tab preference until after first split-view layout so the
            // server-stopped cold start does not measure sidebar under a shifting detail pane.
            DispatchQueue.main.async {
                applyServerStoppedDefaultsIfNeeded()
            }
        }
        .onChange(of: connectionManager.totalAPILogs) {
            syncAppStateFromConnectionManager()
        }
        .onChange(of: connectionManager.totalConsoleLogs) {
            syncAppStateFromConnectionManager()
        }
        .onChange(of: connectionManager.totalPerformanceMetrics) {
            syncAppStateFromConnectionManager()
        }
        .onChange(of: connectionManager.connectedDevices.count) {
            syncAppStateFromConnectionManager()
        }
        .onChange(of: connectionManager.selectedDeviceId) {
            syncAppStateFromConnectionManager()
        }
        .onChange(of: connectionManager.isServerRunning) {
            syncAppStateFromConnectionManager()
        }
        .onChange(of: connectionManager.isLifecycleActive) { _, active in
            if active {
                showServerStoppedTip = false
                appState.serverRequiredHint = nil
            }
            syncAppStateFromConnectionManager()
        }
        // Shared connection clock — refreshes isOnline / metrics without a private Timer
        .onChange(of: connectionManager.uiNow) {
            syncAppStateFromConnectionManager()
        }
    }

    // MARK: - Server-off banners

    private var serverGateBanner: some View {
        let message = appState.serverRequiredHint
            ?? "Server stopped — Start when you need device debug. Dev Tools work without the server."
        return TTBanner(
            kind: .info,
            message: message,
            title: connectionManager.isLifecycleActive ? nil : "Tools ready",
            trailing: AnyView(
                HStack(spacing: 8) {
                    if !connectionManager.isLifecycleActive {
                        Button("Start Server") {
                            connectionManager.startServer()
                            dismissServerBanners()
                        }
                        .buttonStyle(.ttPrimaryCompact)
                    }
                    Button {
                        dismissServerBanners()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TTBannerKind.info.foreground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            )
        )
        .padding(.horizontal, TTSpacing.sectionPadding)
        .padding(.top, TTSpacing.sm)
    }

    private func dismissServerBanners() {
        showServerStoppedTip = false
        hasSeenServerStoppedTip = true
        appState.serverRequiredHint = nil
    }

    /// Tool-first defaults when the debug bridge is not running.
    private func applyServerStoppedDefaultsIfNeeded() {
        guard !connectionManager.isLifecycleActive else { return }
        appState.preferDevToolsWhenServerStopped(serverActive: false)
        if !hasSeenServerStoppedTip {
            showServerStoppedTip = true
        }
    }

    /// Title + tagline for the window chrome — design-system adaptive tokens.
    private var windowTitleLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppBrand.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ttTextPrimary)
            Text(AppBrand.tagline)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.ttTextSecondary)
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppBrand.name), \(AppBrand.tagline)")
    }

    @ViewBuilder
    private var mainContentView: some View {
        switch appState.selectedTab {
        case .console:
            ConsoleView()
        case .network:
            NetworkView()
        case .device:
            DeviceView()
        case .performance:
            PerformanceView()
        case .devtools:
            DevToolsView()
        case .feedback:
            FeedbackView()
        case .connectionHealth:
            ConnectionHealthView()
        case .guide:
            GuideContainerView()
        }
    }

    /// Sync ConnectionManager's live data into AppState for views that still use it.
    /// Connection domain remains owned by ConnectionManager (single source of truth).
    private func syncAppStateFromConnectionManager() {
        appState.isServerRunning = connectionManager.isServerRunning
        appState.totalEvents = connectionManager.totalAPILogs + connectionManager.totalConsoleLogs
        appState.selectedDeviceId = connectionManager.selectedDeviceId

        // Use full deviceId — shortId is display-only (avoids prefix collisions)
        appState.connectedDevices = connectionManager.connectedDevices.map { session in
            ConnectedDevice(
                id: session.id,
                name: session.displayName,
                osVersion: session.osVersionString,
                appName: session.appNameString,
                appVersion: session.deviceInfo?.appVersion ?? "Unknown",
                isConnected: session.isOnline(relativeTo: connectionManager.uiNow),
                isSimulator: session.isSimulator
            )
        }

        if let perf = connectionManager.selectedDevice?.latestPerformance {
            appState.memoryUsage = perf.memoryUsedMB
            appState.cpuUsage = perf.cpuUsage
        } else {
            appState.memoryUsage = 0
            appState.cpuUsage = 0
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(ConnectionManager())
        .frame(width: 1200, height: 800)
}
