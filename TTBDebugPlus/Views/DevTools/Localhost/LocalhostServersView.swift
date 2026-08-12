//
//  LocalhostServersView.swift
//  DebugKit
//
//  Dev Tools workbench: Live Ports + My Servers lifecycle manager.
//

import AppKit
import SwiftUI

struct LocalhostServersView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var viewModel = LocalhostServersViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.ttBorder.opacity(0.35))
            if let status = viewModel.statusMessage {
                HStack(spacing: TTSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.ttSuccess)
                    Text(status)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextPrimary)
                    Spacer()
                }
                .padding(.horizontal, TTSpacing.lg)
                .padding(.vertical, TTSpacing.xs)
                .background(Color.ttSuccess.opacity(0.12))
            }
            content
        }
        .background(Color.ttBackground)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            viewModel.onAppear(protectedPorts: protectedPortSet)
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: connectionManager.serverPorts) { _, _ in
            viewModel.updateProtectedPorts(protectedPortSet)
        }
        .sheet(isPresented: $viewModel.isEditorPresented) {
            if let draft = viewModel.editorDraft {
                LocalhostServerEditorSheet(
                    draft: draft,
                    onSave: { viewModel.saveEditorDraft($0) },
                    onCancel: {
                        viewModel.isEditorPresented = false
                        viewModel.editorDraft = nil
                    }
                )
            }
        }
        .sheet(item: $viewModel.pendingConflict) { conflict in
            LocalhostConflictSheet(
                conflict: conflict,
                onFreeSoft: { viewModel.resolveConflictByKillingOccupant(soft: true) },
                onFreeForce: { viewModel.resolveConflictByKillingOccupant(soft: false) },
                onCancel: { viewModel.cancelConflict() }
            )
        }
        .alert(
            "Force Kill Process?",
            isPresented: Binding(
                get: { viewModel.pendingForceKill != nil },
                set: { if !$0 { viewModel.cancelForceKill() } }
            )
        ) {
            Button("Cancel", role: .cancel) { viewModel.cancelForceKill() }
            Button("Force Kill", role: .destructive) { viewModel.confirmForceKill() }
        } message: {
            if let req = viewModel.pendingForceKill {
                if req.definitionIDToStartAfter != nil {
                    Text("Send SIGKILL to \(req.processName) (PID \(req.pid)) on port \(req.port), then start your server? This cannot be undone.")
                } else {
                    Text("Send SIGKILL to \(req.processName) (PID \(req.pid)) on port \(req.port)? This cannot be undone.")
                }
            }
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    private var protectedPortSet: Set<Int> {
        Set(connectionManager.serverPorts.values.map { Int($0) })
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: TTSpacing.md) {
            Picker("Pane", selection: $viewModel.pane) {
                Text("Live Ports (\(viewModel.livePortsCountLabel))")
                    .tag(LocalhostServersViewModel.Pane.livePorts)
                Text("My Servers (\(viewModel.myServersCountLabel))")
                    .tag(LocalhostServersViewModel.Pane.myServers)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .accessibilityLabel("Localhost panes")

            Spacer()

            Text(viewModel.lastScanLabel)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)

            Button {
                Task { await viewModel.refreshPorts() }
            } label: {
                Label(
                    viewModel.isScanning ? "Scanning…" : "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.ttSecondary)
            .disabled(viewModel.isScanning)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh listening ports (⌘R)")

            if viewModel.pane == .myServers {
                Button {
                    viewModel.beginAddServer()
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
                .buttonStyle(.ttPrimary)
            }
        }
        .padding(.horizontal, TTSpacing.lg)
        .padding(.vertical, TTSpacing.inputPaddingH)
        .background(Color.ttSurface.opacity(0.25))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.pane {
        case .livePorts:
            livePortsSplit
        case .myServers:
            myServersSplit
        }
    }

    private var livePortsSplit: some View {
        HSplitView {
            livePortsList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
            livePortDetail
                .frame(minWidth: 360)
        }
    }

    private var myServersSplit: some View {
        HSplitView {
            myServersList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
            myServerDetail
                .frame(minWidth: 360)
        }
    }

    // MARK: - Live ports list

    private var livePortsList: some View {
        VStack(spacing: 0) {
            HStack(spacing: TTSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.ttTextSecondary)
                    .font(TTFont.bodyMedium)
                TextField("Filter name, port, PID…", text: $viewModel.portSearchText)
                    .textFieldStyle(.plain)
                    .font(TTFont.bodySmall)
                if !viewModel.portSearchText.isEmpty {
                    Button {
                        viewModel.portSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.ttTextMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, TTSpacing.inputPaddingH)
            .padding(.vertical, TTSpacing.sm)
            .background(Color.ttSurface.opacity(0.35))

            if let scanError = viewModel.scanError {
                TTBanner(
                    kind: viewModel.scanErrorIsHardFailure ? .error : .warning,
                    message: scanError,
                    title: viewModel.scanErrorIsHardFailure ? "Port discovery blocked" : "Limited discovery"
                )
                .padding(.horizontal, TTSpacing.inputPaddingH)
                .padding(.top, TTSpacing.sm)
            }

            if viewModel.endpoints.isEmpty && !viewModel.isScanning {
                EmptyStateView(
                    icon: "network",
                    title: "No Listening Ports",
                    subtitle: viewModel.scanError == nil
                        ? "No TCP LISTEN sockets were found, or discovery is restricted. Try Refresh."
                        : "Port discovery failed. You can still manage My Servers and use Terminal as fallback."
                )
            } else if viewModel.filteredEndpoints.isEmpty {
                EmptyStateView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No Matches",
                    subtitle: "No ports match “\(viewModel.portSearchText)”. Clear the filter or try another query."
                )
            } else {
                List(selection: $viewModel.selectedEndpointID) {
                    ForEach(viewModel.filteredEndpoints) { endpoint in
                        livePortRow(endpoint)
                            .tag(endpoint.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color.ttBackground)
    }

    private func livePortRow(_ endpoint: ListeningEndpoint) -> some View {
        HStack(spacing: TTSpacing.inputPaddingH) {
            Circle()
                .fill(classColor(endpoint.classification))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                Text(endpoint.displayTitle)
                    .font(TTFont.labelMedium)
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)
                Text("PID \(endpoint.pid) · \(endpoint.addressPortLabel) · \(endpoint.classification.displayName)")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, TTSpacing.xxxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(endpoint.processName), port \(endpoint.port), \(endpoint.classification.displayName)")
    }

    private var livePortDetail: some View {
        Group {
            if let endpoint = viewModel.selectedEndpoint {
                VStack(alignment: .leading, spacing: TTSpacing.lg) {
                    HStack {
                        VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                            Text(endpoint.processName)
                                .font(TTFont.heading2)
                                .foregroundColor(.ttTextPrimary)
                                .textSelection(.enabled)
                            Text(endpoint.addressPortLabel)
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextSecondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        TTStatusPill(text: endpoint.classification.displayName, kind: classKind(endpoint.classification))
                    }

                    metaGrid([
                        ("PID", "\(endpoint.pid)"),
                        ("Port", "\(endpoint.port)"),
                        ("Addresses", endpoint.addressesLabel),
                        ("Open host", endpoint.preferredOpenHost)
                    ])

                    if endpoint.classification == .ttbdebug {
                        TTBanner(
                            kind: .info,
                            message: "Protected — DebugKit debug bridge or this app. Use sidebar Server controls to stop the debug stack."
                        )
                    } else if endpoint.classification == .system {
                        TTBanner(
                            kind: .warning,
                            message: "System process. Soft stop and force kill are blocked. macOS often uses ports 5000/7000 (AirPlay / Control Center)."
                        )
                    }

                    HStack(spacing: TTSpacing.inputPaddingH) {
                        Button("Soft Stop") {
                            viewModel.softStopEndpoint(endpoint)
                        }
                        .buttonStyle(.ttSecondary)
                        .disabled(!LocalhostProcessClassifier.canSoftStop(endpoint.classification))
                        .help(LocalhostProcessClassifier.canSoftStop(endpoint.classification)
                              ? "Send SIGTERM"
                              : "Not allowed for system or protected processes")

                        Button("Force Kill…") {
                            viewModel.requestForceKill(endpoint)
                        }
                        .buttonStyle(.ttSecondary)
                        .disabled(!LocalhostProcessClassifier.canForceKill(endpoint.classification))
                        .help(LocalhostProcessClassifier.canForceKill(endpoint.classification)
                              ? "Send SIGKILL after confirmation"
                              : "Force kill blocked for system or protected processes")

                        Button("Copy kill command") {
                            viewModel.copyKillCommand(for: endpoint)
                        }
                        .buttonStyle(.ttSecondary)

                        Button("Open URL") {
                            viewModel.openURL(for: endpoint)
                        }
                        .buttonStyle(.ttSecondary)
                    }

                    // Same-PID siblings help when one process holds many ports.
                    let siblings = viewModel.endpoints.filter {
                        $0.pid == endpoint.pid && $0.id != endpoint.id
                    }
                    if !siblings.isEmpty {
                        VStack(alignment: .leading, spacing: TTSpacing.sm) {
                            Text("Other ports for this PID")
                                .font(TTFont.labelSmall)
                                .foregroundColor(.ttTextSecondary)
                            ForEach(siblings) { sibling in
                                Button {
                                    viewModel.selectedEndpointID = sibling.id
                                } label: {
                                    HStack {
                                        Text(":\(sibling.port)")
                                            .font(TTFont.codeSmall)
                                            .foregroundColor(.ttPrimary)
                                        Text(sibling.addressesLabel)
                                            .font(TTFont.codeSmall)
                                            .foregroundColor(.ttTextSecondary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(TTSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.ttSurface.opacity(0.4))
                        )
                    }

                    Spacer()
                }
                .padding(TTSpacing.xl)
            } else {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "Select a Port",
                    subtitle: "Choose a listening endpoint to inspect process details and free the port safely."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ttBackground)
    }

    // MARK: - My servers

    private var myServersList: some View {
        VStack(spacing: 0) {
            if viewModel.definitions.isEmpty {
                EmptyStateView(
                    icon: AppIcon.localhostServers,
                    title: "No Servers Yet",
                    subtitle: "Add a project server with a working directory and launch command (for example npm run dev).",
                    actionTitle: "Add Server",
                    action: { viewModel.beginAddServer() }
                )
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedDefinitionID },
                    set: { viewModel.selectedDefinitionID = $0 }
                )) {
                    ForEach(viewModel.definitions) { def in
                        myServerRow(def)
                            .tag(def.id)
                            .contextMenu {
                                Button("Edit") { viewModel.beginEditServer(def) }
                                Button("Start") { viewModel.startServer(id: def.id) }
                                Button("Stop") { viewModel.stopServer(id: def.id) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteServer(def.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color.ttBackground)
    }

    private func myServerRow(_ def: LocalServerDefinition) -> some View {
        let rt = viewModel.runtime(for: def.id)
        return HStack(spacing: TTSpacing.inputPaddingH) {
            Circle()
                .fill(stateColor(rt.state))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                Text(def.name.isEmpty ? "Untitled" : def.name)
                    .font(TTFont.labelMedium)
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)
                Text(subtitle(for: def, runtime: rt))
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            TTStatusPill(text: rt.state.displayName, kind: stateKind(rt.state))
        }
        .padding(.vertical, TTSpacing.xxxs)
        .contentShape(Rectangle())
    }

    private func subtitle(for def: LocalServerDefinition, runtime: ManagedServerRuntime) -> String {
        var parts: [String] = []
        if let port = def.preferredPort {
            parts.append(":\(port)")
        }
        if let pid = runtime.pid {
            parts.append("pid \(pid)")
        }
        parts.append(def.launchCommand)
        return parts.joined(separator: " · ")
    }

    private var myServerDetail: some View {
        Group {
            if let def = viewModel.selectedDefinition {
                let rt = viewModel.runtime(for: def.id)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
                        HStack {
                            VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                                Text(def.name.isEmpty ? "Untitled" : def.name)
                                    .font(TTFont.heading2)
                                    .foregroundColor(.ttTextPrimary)
                                Text(def.workingDirectory)
                                    .font(TTFont.codeSmall)
                                    .foregroundColor(.ttTextSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            TTStatusPill(text: rt.state.displayName, kind: stateKind(rt.state))
                        }

                        metaGrid([
                            ("Command", def.launchCommand),
                            ("Preferred port", def.preferredPort.map(String.init) ?? "—"),
                            ("PID", rt.pid.map(String.init) ?? "—"),
                            ("Shell", def.useLoginShell ? "zsh -lc" : "direct")
                        ])

                        if let err = rt.lastError {
                            TTBanner(kind: .error, message: err, title: "Server error")
                        }

                        HStack(spacing: TTSpacing.inputPaddingH) {
                            Button {
                                viewModel.startServer(id: def.id)
                            } label: {
                                Label("Start", systemImage: AppIcon.startServer)
                            }
                            .buttonStyle(.ttPrimary)
                            .disabled(rt.state == .running || rt.state == .starting)

                            Button {
                                viewModel.stopServer(id: def.id, force: false)
                            } label: {
                                Label("Stop", systemImage: AppIcon.stopServer)
                            }
                            .buttonStyle(.ttSecondary)
                            .disabled(rt.state == .stopped || rt.state == .stopping)

                            Button {
                                viewModel.restartServer(id: def.id)
                            } label: {
                                Label("Restart", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.ttSecondary)

                            Button("Edit") {
                                viewModel.beginEditServer(def)
                            }
                            .buttonStyle(.ttSecondary)

                            Button("Open URL") {
                                viewModel.openURLIfConfigured(for: def)
                            }
                            .buttonStyle(.ttSecondary)

                            Spacer()

                            Button("Clear logs") {
                                viewModel.clearLogs(for: def.id)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.ttTextSecondary)
                        }
                    }
                    .padding(TTSpacing.lg)

                    Divider().overlay(Color.ttBorder.opacity(0.3))

                    logPane(lines: rt.logLines)
                }
            } else {
                EmptyStateView(
                    icon: "server.rack",
                    title: "Select a Server",
                    subtitle: "Pick a saved server to start, stop, restart, and tail logs."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ttBackground)
    }

    private func logPane(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Logs")
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextSecondary)
                .padding(.horizontal, TTSpacing.lg)
                .padding(.top, TTSpacing.inputPaddingH)
                .padding(.bottom, TTSpacing.xs)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                        if lines.isEmpty {
                            Text("No log output yet.")
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(TTSpacing.md)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(TTFont.codeSmall)
                                    .foregroundColor(.ttTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                    }
                    .padding(.horizontal, TTSpacing.md)
                    .padding(.bottom, TTSpacing.md)
                }
                .background(Color.ttSurface.opacity(0.35))
                .onChange(of: lines.count) { _, count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared chrome

    private func metaGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: TTSpacing.md),
                GridItem(.flexible(), spacing: TTSpacing.md)
            ],
            alignment: .leading,
            spacing: TTSpacing.inputPaddingH
        ) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                    Text(item.0)
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextSecondary)
                    Text(item.1)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextPrimary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
    }

    private func classColor(_ c: ProcessClass) -> Color {
        switch c {
        case .user: return .ttSuccess
        case .system: return .ttWarning
        case .docker: return .ttPrimary
        case .ttbdebug: return .ttPrimary
        case .unknown: return .ttTextMuted
        }
    }

    private func classKind(_ c: ProcessClass) -> TTBannerKind {
        switch c {
        case .user: return .success
        case .system: return .warning
        case .docker, .ttbdebug: return .info
        case .unknown: return .info
        }
    }

    private func stateColor(_ s: ServerRuntimeState) -> Color {
        switch s {
        case .running: return .ttSuccess
        case .starting, .stopping, .conflict: return .ttWarning
        case .failed: return .ttError
        case .stopped, .unknown: return .ttTextMuted
        }
    }

    private func stateKind(_ s: ServerRuntimeState) -> TTBannerKind {
        switch s {
        case .running: return .success
        case .starting, .stopping, .conflict: return .warning
        case .failed: return .error
        case .stopped, .unknown: return .info
        }
    }
}

// MARK: - Editor sheet

struct LocalhostServerEditorSheet: View {
    @State private var draft: LocalServerDefinition
    let onSave: (LocalServerDefinition) -> Void
    let onCancel: () -> Void

    @State private var portText: String = ""
    @State private var envText: String = ""

    init(
        draft: LocalServerDefinition,
        onSave: @escaping (LocalServerDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
        _portText = State(initialValue: draft.preferredPort.map(String.init) ?? "")
        _envText = State(initialValue: draft.env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(draft.name.isEmpty && draft.launchCommand.isEmpty ? "Add Server" : "Edit Server")
                    .font(TTFont.heading2)
                    .foregroundColor(.ttTextPrimary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.ttSecondary)
                Button("Save") { commit() }
                    .buttonStyle(.ttPrimary)
                    .disabled(!canSave)
            }
            .padding(TTSpacing.lg)

            Divider().overlay(Color.ttBorder.opacity(0.3))

            Form {
                TextField("Name", text: $draft.name)
                HStack {
                    TextField("Working directory", text: $draft.workingDirectory)
                    Button("Browse…") { pickDirectory() }
                }
                TextField("Launch command", text: $draft.launchCommand)
                    .help("Example: npm run dev  or  python3 -m http.server 8765")
                TextField("Preferred port", text: $portText)
                TextField("Open URL on demand", text: Binding(
                    get: { draft.openURLOnStart ?? "" },
                    set: { draft.openURLOnStart = $0.isEmpty ? nil : $0 }
                ))
                Toggle("Use login shell (zsh -lc)", isOn: $draft.useLoginShell)
                VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                    Text("Environment (KEY=value per line)")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttTextPrimary)
                    TextEditor(text: $envText)
                        .font(TTFont.codeSmall)
                        .frame(minHeight: 80)
                }
            }
            .padding(TTSpacing.lg)
            .frame(minWidth: 520, minHeight: 420)
        }
        .background(Color.ttBackground)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: draft.workingDirectory)
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            draft.workingDirectory = url.path
        }
    }

    private func commit() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.launchCommand = draft.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.workingDirectory = draft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let portTrim = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.preferredPort = portTrim.isEmpty ? nil : Int(portTrim)
        draft.env = parseEnv(envText)
        draft.updatedAt = Date()
        onSave(draft)
    }

    private func parseEnv(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, !raw.hasPrefix("#") else { continue }
            guard let eq = raw.firstIndex(of: "=") else { continue }
            let key = String(raw[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: eq)...])
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}

// MARK: - Conflict sheet

struct LocalhostConflictSheet: View {
    let conflict: PortConflictInfo
    let onFreeSoft: () -> Void
    let onFreeForce: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TTSpacing.lg) {
            Text("Port Conflict")
                .font(TTFont.heading2)
                .foregroundColor(.ttTextPrimary)

            Text("Port \(conflict.port) is already in use by \(conflict.occupant.processName) (PID \(conflict.occupant.pid)).")
                .font(TTFont.bodyMedium)
                .foregroundColor(.ttTextSecondary)

            Text("Class: \(conflict.occupant.classification.displayName) · \(conflict.occupant.addressPortLabel)")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)

            if conflict.occupant.classification == .system || conflict.occupant.classification == .ttbdebug {
                TTBanner(
                    kind: .warning,
                    message: "This occupant is protected or system-owned. Free the port manually or choose a different preferred port."
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.ttSecondary)
                Button("Soft-stop & Start", action: onFreeSoft)
                    .buttonStyle(.ttSecondary)
                    .disabled(!LocalhostProcessClassifier.canSoftStop(conflict.occupant.classification))
                Button("Force free & Start…", action: onFreeForce)
                    .buttonStyle(.ttPrimary)
                    .disabled(!LocalhostProcessClassifier.canForceKill(conflict.occupant.classification))
                    .help("Requires confirmation before SIGKILL")
            }
        }
        .padding(TTSpacing.xxl)
        .frame(minWidth: 440)
        .background(Color.ttBackground)
    }
}
