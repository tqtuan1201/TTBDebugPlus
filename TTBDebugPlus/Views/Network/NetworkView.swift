//
//  NetworkView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Network traffic inspector with device-aware filtering, pro UI, live/pause, keyboard nav
//

import SwiftUI

struct NetworkView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager
    @State private var viewModel = NetworkViewModel()
    @State private var showDetail: Bool = true
    @State private var showCURLCopied: Bool = false
    @State private var showPostmanExported: Bool = false
    @State private var showHARExported: Bool = false
    @State private var exportErrorMessage: String?
    @State private var viewMode: NetworkViewMode = .requests
    @State private var hoveredRowId: String? = nil
    
    enum NetworkViewMode: String, CaseIterable {
        case requests = "Requests"
        case analytics = "Analytics"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // View mode segmented control
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(NetworkViewMode.allCases, id: \.self) { mode in
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { viewMode = mode } }) {
                            HStack(spacing: 5) {
                                Image(systemName: mode == .requests ? "list.bullet" : "chart.bar.xaxis")
                                    .font(.ttIcon(TTIcon.md))
                                Text(mode.rawValue)
                                    .font(TTFont.tabLabel)
                            }
                            .foregroundColor(viewMode == mode ? .white : .ttTextSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(viewMode == mode ? Color.ttPrimary.opacity(0.6) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.ttSurface.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ttBorder.opacity(0.3), lineWidth: 1))
                )
                
                Spacer()
                
                // Device filter picker
                if !viewModel.availableDevices.isEmpty {
                    deviceFilterPicker
                }

                if !viewModel.availableApps.isEmpty {
                    appFilterPicker
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.ttBackground)
            .overlay(
                Rectangle().fill(Color.ttBorder.opacity(0.3)).frame(height: 1),
                alignment: .bottom
            )
            
            // Content
            switch viewMode {
            case .requests:
                requestsContent
            case .analytics:
                NetworkStatsView(viewModel: viewModel)
            }
        }
        .focusable()
        .onKeyPress(.upArrow) { viewModel.selectPrevious(); showDetail = true; return .handled }
        .onKeyPress(.downArrow) { viewModel.selectNext(); showDetail = true; return .handled }
        .onAppear {
            viewModel.syncFromConnectionManager(connectionManager)
        }
        .onChange(of: connectionManager.totalAPILogs) {
            viewModel.syncFromConnectionManager(connectionManager)
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }
    
    // MARK: - Device Filter Picker
    private var deviceFilterPicker: some View {
        Menu {
            Button(action: { viewModel.selectedDeviceFilter = nil }) {
                HStack {
                    Text("All Devices")
                    if viewModel.selectedDeviceFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            ForEach(viewModel.availableDevices, id: \.id) { device in
                Button(action: { viewModel.selectedDeviceFilter = device.id }) {
                    HStack {
                        Circle()
                            .fill(Color.forDevice(device.id))
                            .frame(width: 8, height: 8)
                        Text(device.name)
                        if viewModel.selectedDeviceFilter == device.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let deviceId = viewModel.selectedDeviceFilter,
                   let device = viewModel.availableDevices.first(where: { $0.id == deviceId }) {
                    Circle()
                        .fill(Color.forDevice(deviceId))
                        .frame(width: 6, height: 6)
                    Text(device.name)
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextPrimary)
                } else {
                    Image(systemName: "desktopcomputer")
                        .font(.ttIcon(TTIcon.md))
                    Text("All Devices")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextSecondary)
                }
                Image(systemName: "chevron.down")
                    .font(.ttIcon(TTIcon.xxs))
                    .foregroundColor(.ttTextTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.ttSurface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var appFilterPicker: some View {
        Menu {
            Button(action: { viewModel.selectedAppFilter = nil }) {
                HStack {
                    Text("All Apps")
                    if viewModel.selectedAppFilter == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(viewModel.availableApps, id: \.key) { app in
                Button(action: { viewModel.selectedAppFilter = app.key }) {
                    HStack {
                        Text(app.displayName)
                        Text("\(app.count)")
                            .foregroundColor(.secondary)
                        if viewModel.selectedAppFilter == app.key {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "app.badge")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(viewModel.selectedAppFilter == nil ? .ttTextTertiary : .ttPrimary)

                Text(selectedAppFilterTitle)
                    .font(TTFont.labelSmall)
                    .foregroundColor(viewModel.selectedAppFilter == nil ? .ttTextSecondary : .ttTextPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.ttIcon(TTIcon.xxs))
                    .foregroundColor(.ttTextTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.ttSurface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var selectedAppFilterTitle: String {
        guard let appKey = viewModel.selectedAppFilter,
              let app = viewModel.availableApps.first(where: { $0.key == appKey }) else {
            return "All Apps"
        }
        return app.displayName
    }
    
    // MARK: - Requests Content
    private var requestsContent: some View {
        HSplitView {
            // MARK: - Request List (Left)
            VStack(spacing: 0) {
                networkFilterBar
                requestColumnHeaders
                requestList
                networkBottomBar
            }
            .frame(minWidth: 500)
            .background(Color.ttBackground)
            
            // MARK: - Detail Pane (Right)
            if showDetail, let request = viewModel.selectedEntry {
                NetworkDetailPaneView(
                    request: request,
                    selectedTab: $viewModel.selectedDetailTab,
                    onClose: { showDetail = false },
                    onOpenInEditor: { json, source in
                        appState.openInJSONEditor(json: json, source: source)
                    },
                    onSaveAsTemplate: { json, source in
                        appState.requestSaveAsTemplate(json: json, source: source)
                    },
                    onDecodeJWT: { token, source in
                        appState.openJWTTool(token: token, source: source)
                    }
                )
                .frame(minWidth: 350, idealWidth: 500)
            }
        }
    }
    
    // MARK: - Filter Bar
    private var networkFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
            // Search field with inline scope
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(.ttTextTertiary)
                
                TextField("Filter requests...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(TTFont.codeMedium)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ttIcon(TTIcon.md))
                            .foregroundColor(.ttTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Inline scope picker
                Menu {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Button(action: { viewModel.searchScope = scope }) {
                            HStack {
                                Text(scope.rawValue)
                                if viewModel.searchScope == scope {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(viewModel.searchScope.rawValue)
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.ttSurface.opacity(0.6))
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.ttSurface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder.opacity(0.6), lineWidth: 1))
            )
            .frame(minWidth: 140, maxWidth: 260)
            
            // Status filter dropdown
            Menu {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    Button(action: { viewModel.selectedStatusFilter = filter }) {
                        HStack {
                            if filter != .all {
                                Circle()
                                    .fill(statusFilterColor(filter))
                                    .frame(width: 6, height: 6)
                            }
                            Text(filter.rawValue)
                            if viewModel.selectedStatusFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if viewModel.selectedStatusFilter != .all {
                        Circle()
                            .fill(statusFilterColor(viewModel.selectedStatusFilter))
                            .frame(width: 6, height: 6)
                    }
                    Text(viewModel.selectedStatusFilter == .all ? "Status" : viewModel.selectedStatusFilter.rawValue)
                        .font(TTFont.labelSmall)
                        .foregroundColor(viewModel.selectedStatusFilter != .all ? .ttTextPrimary : .ttTextTertiary)
                    Image(systemName: "chevron.down")
                        .font(.ttIcon(TTIcon.xxxs))
                        .foregroundColor(.ttTextTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedStatusFilter != .all ? statusFilterColor(viewModel.selectedStatusFilter).opacity(0.1) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder.opacity(0.4), lineWidth: 0.5))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Method filter dropdown
            Menu {
                Button("All Methods") { viewModel.selectedMethodFilter = nil }
                Divider()
                ForEach(viewModel.availableMethods, id: \.self) { method in
                    Button(action: { viewModel.selectedMethodFilter = method }) {
                        HStack {
                            Circle().fill(Color.forHTTPMethod(method)).frame(width: 6, height: 6)
                            Text(method)
                            if viewModel.selectedMethodFilter == method {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let method = viewModel.selectedMethodFilter {
                        Circle().fill(Color.forHTTPMethod(method)).frame(width: 6, height: 6)
                        Text(method)
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttTextPrimary)
                    } else {
                        Text("Method")
                            .font(TTFont.labelSmall)
                            .foregroundColor(.ttTextTertiary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.ttIcon(TTIcon.xxxs))
                        .foregroundColor(.ttTextTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((viewModel.selectedMethodFilter.map { Color.forHTTPMethod($0).opacity(0.1) }) ?? Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder.opacity(0.4), lineWidth: 0.5))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Domain filter dropdown
            Menu {
                Button("All Domains") { viewModel.selectedDomainFilter = nil }
                Divider()
                ForEach(viewModel.availableDomains.prefix(20), id: \.domain) { item in
                    Button(action: { viewModel.selectedDomainFilter = item.domain }) {
                        HStack {
                            Text(item.domain)
                            Text("\(item.count)")
                                .foregroundColor(.secondary)
                            if viewModel.selectedDomainFilter == item.domain {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(viewModel.selectedDomainFilter == nil ? .ttTextTertiary : .ttPrimary)
                    Text(viewModel.selectedDomainFilter ?? "Domain")
                        .font(TTFont.labelSmall)
                        .foregroundColor(viewModel.selectedDomainFilter == nil ? .ttTextTertiary : .ttTextPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.ttIcon(TTIcon.xxxs))
                        .foregroundColor(.ttTextTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedDomainFilter == nil ? Color.clear : Color.ttPrimary.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder.opacity(0.4), lineWidth: 0.5))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Duration filter dropdown
            Menu {
                ForEach(DurationFilter.allCases, id: \.self) { filter in
                    Button(action: { viewModel.selectedDurationFilter = filter }) {
                        HStack {
                            Text(filter == .all ? "All Durations" : filter.rawValue)
                            if viewModel.selectedDurationFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(viewModel.selectedDurationFilter == .all ? .ttTextTertiary : .ttWarning)
                    Text(viewModel.selectedDurationFilter == .all ? "Duration" : viewModel.selectedDurationFilter.rawValue)
                        .font(TTFont.labelSmall)
                        .foregroundColor(viewModel.selectedDurationFilter == .all ? .ttTextTertiary : .ttTextPrimary)
                    Image(systemName: "chevron.down")
                        .font(.ttIcon(TTIcon.xxxs))
                        .foregroundColor(.ttTextTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedDurationFilter == .all ? Color.clear : Color.ttWarning.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ttBorder.opacity(0.4), lineWidth: 0.5))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Pin filter
            Button(action: { viewModel.showOnlyPinned.toggle() }) {
                Image(systemName: viewModel.showOnlyPinned ? "star.fill" : "star")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(viewModel.showOnlyPinned ? .yellow : .ttTextTertiary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(viewModel.showOnlyPinned ? Color.yellow.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(viewModel.showOnlyPinned ? "Show all requests" : "Show pinned only")
            .accessibilityLabel(viewModel.showOnlyPinned ? "Show All Requests" : "Show Pinned Requests")
            
            Spacer()
            
            // Active filters indicator
            if hasActiveFilters {
                Button(action: clearAllFilters) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ttIcon(TTIcon.xs))
                        Text("Clear")
                            .font(TTFont.labelSmall)
                    }
                    .foregroundColor(.ttTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.ttSurface.opacity(0.5))
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Live/Pause toggle
            Button(action: { viewModel.toggleLiveStreaming(connectionManager) }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isLiveStreaming ? Color.ttSuccess : Color.ttWarning)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isLiveStreaming ? "LIVE" : "PAUSED")
                        .font(TTFont.badge)
                        .foregroundColor(viewModel.isLiveStreaming ? .ttSuccess : .ttWarning)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(viewModel.isLiveStreaming ? Color.ttSuccess.opacity(0.12) : Color.ttWarning.opacity(0.12))
                        .overlay(Capsule().stroke(viewModel.isLiveStreaming ? Color.ttSuccess.opacity(0.3) : Color.ttWarning.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .help(viewModel.isLiveStreaming ? "Click to pause" : "Click to resume")
            .accessibilityLabel(viewModel.isLiveStreaming ? "Pause Live Updates" : "Resume Live Updates")
            
            // Refresh
            Button(action: { viewModel.forceRefresh(connectionManager) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(.ttTextTertiary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Refresh data")
            .accessibilityLabel("Refresh Network Data")
            
            // Clear all requests
            Button(action: { viewModel.clearAll(connectionManager) }) {
                Image(systemName: "trash")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(.ttTextTertiary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Clear all requests")
            .accessibilityLabel("Clear All Requests")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.ttSurface.opacity(0.15))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var hasActiveFilters: Bool {
        viewModel.selectedStatusFilter != .all ||
        viewModel.selectedMethodFilter != nil ||
        viewModel.selectedDeviceFilter != nil ||
        viewModel.selectedAppFilter != nil ||
        viewModel.selectedDomainFilter != nil ||
        viewModel.selectedDurationFilter != .all ||
        viewModel.showOnlyPinned ||
        !viewModel.searchText.isEmpty
    }
    
    private func clearAllFilters() {
        viewModel.selectedStatusFilter = .all
        viewModel.selectedMethodFilter = nil
        viewModel.selectedDeviceFilter = nil
        viewModel.selectedAppFilter = nil
        viewModel.selectedDomainFilter = nil
        viewModel.selectedDurationFilter = .all
        viewModel.showOnlyPinned = false
        viewModel.searchText = ""
    }
    
    private func statusFilterColor(_ filter: StatusFilter) -> Color {
        switch filter {
        case .all: return .ttTextTertiary
        case .success: return .ttStatus2xx
        case .redirect: return .ttStatus3xx
        case .clientError: return .ttStatus4xx
        case .serverError: return .ttStatus5xx
        }
    }
    
    // MARK: - Column Headers
    private var requestColumnHeaders: some View {
        HStack(spacing: 0) {
            Text("STATUS")
                .frame(width: 55, alignment: .leading)
            Text("METHOD")
                .frame(width: 60, alignment: .leading)
            Text("URL")
                .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.availableDevices.count > 1 {
                Text("DEVICE")
                    .frame(width: 100, alignment: .leading)
            }
            if viewModel.availableApps.count > 1 {
                Text("APP")
                    .frame(width: 130, alignment: .leading)
            }
            Text("TIME")
                .frame(width: 65, alignment: .trailing)
            Text("SIZE")
                .frame(width: 70, alignment: .trailing)
            Text("WATERFALL")
                .frame(width: 100, alignment: .leading)
                .padding(.leading, 12)
        }
        .font(TTFont.sidebarHeader)
        .foregroundColor(.ttTextTertiary)
        .tracking(0.8)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.ttSurface.opacity(0.3))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.3)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Request List
    private var requestList: some View {
        Group {
            if viewModel.filteredEntries.isEmpty {
                EmptyStateView(
                    icon: "network",
                    title: "No Network Requests",
                    subtitle: viewModel.entries.isEmpty
                        ? "Network requests from the connected device will appear here.\nMake sure your app uses TTDebugBridge to intercept API calls."
                        : "No requests match the current filter."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.filteredEntries.enumerated()), id: \.element.id) { index, request in
                                NetworkRequestRowView(
                                    request: request,
                                    maxDuration: viewModel.maxDuration,
                                    isSelected: viewModel.selectedEntry?.id == request.id,
                                    isPinned: viewModel.isPinned(request.id),
                                    isHovered: hoveredRowId == request.id,
                                    isAlternate: index % 2 == 1,
                                    showDeviceColumn: viewModel.availableDevices.count > 1,
                                    showAppColumn: viewModel.availableApps.count > 1
                                )
                                .id(request.id)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.selectedEntry = request
                                        showDetail = true
                                    }
                                }
                                .onHover { isHover in
                                    hoveredRowId = isHover ? request.id : nil
                                }
                                .contextMenu {
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(request.url, forType: .string)
                                    }) {
                                        Label("Copy URL", systemImage: "link")
                                    }
                                    
                                    Button(action: {
                                        viewModel.selectedEntry = request
                                        if let curl = viewModel.generateCURL() {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(curl, forType: .string)
                                        }
                                    }) {
                                        Label("Copy cURL", systemImage: "terminal")
                                    }
                                    
                                    Divider()
                                    
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(request.requestBody, forType: .string)
                                    }) {
                                        Label("Copy Request Body", systemImage: "arrow.up.doc")
                                    }
                                    .disabled(request.requestBody.isEmpty)
                                    
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(request.responseBody, forType: .string)
                                    }) {
                                        Label("Copy Response Body", systemImage: "arrow.down.doc")
                                    }
                                    .disabled(request.responseBody.isEmpty)
                                    
                                    Divider()
                                    
                                    Button(action: { viewModel.togglePin(request.id) }) {
                                        Label(viewModel.isPinned(request.id) ? "Unpin" : "Pin", systemImage: viewModel.isPinned(request.id) ? "star.slash" : "star")
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedEntry?.id) { _, newId in
                        if let id = newId {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Bottom Bar
    private var networkBottomBar: some View {
        HStack(spacing: 12) {
            // Request count
            Text("\(viewModel.filteredEntries.count) of \(viewModel.totalRequests) requests")
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
            
            Spacer()
            
            // HAR export
            Button(action: exportHAR) {
                HStack(spacing: 4) {
                    Image(systemName: showHARExported ? "checkmark.circle.fill" : "doc.text")
                    Text(showHARExported ? "Exported!" : "HAR")
                }
                .font(TTFont.labelMedium)
            }
            .buttonStyle(.ttSecondaryCompact)
            .disabled(viewModel.entries.isEmpty)
            
            // Postman export
            Button(action: exportPostman) {
                HStack(spacing: 4) {
                    Image(systemName: showPostmanExported ? "checkmark.circle.fill" : "shippingbox")
                    Text(showPostmanExported ? "Exported!" : "Postman")
                }
                .font(TTFont.labelMedium)
            }
            .buttonStyle(.ttSecondaryCompact)
            .disabled(viewModel.entries.isEmpty)
            
            // cURL export
            Button(action: copyCURL) {
                HStack(spacing: 4) {
                    Image(systemName: showCURLCopied ? "checkmark.circle.fill" : "square.and.arrow.up")
                    Text(showCURLCopied ? "Copied!" : "Share cURL")
                }
                .font(TTFont.labelMedium)
            }
            .buttonStyle(.ttPrimaryCompact)
            .disabled(viewModel.selectedEntry == nil)
            .opacity(viewModel.selectedEntry == nil ? 0.5 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.ttBackground)
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.3)).frame(height: 1),
            alignment: .top
        )
    }
    
    private func copyCURL() {
        guard let curl = viewModel.generateCURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curl, forType: .string)
        showCURLCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCURLCopied = false }
    }
    
    private func exportPostman() {
        let json = viewModel.generatePostmanExport()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TTBDebugPlus_Collection.postman_collection.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    showPostmanExported = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showPostmanExported = false }
                } catch {
                    exportErrorMessage = "Could not export Postman collection: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func exportHAR() {
        let har = viewModel.generateHARExport(stripAuth: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TTBDebugPlus_Export.har"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try har.write(to: url, atomically: true, encoding: .utf8)
                    showHARExported = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showHARExported = false }
                } catch {
                    exportErrorMessage = "Could not export HAR file: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NetworkView()
        .environment(AppState())
        .environment(ConnectionManager())
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.dark)
}
