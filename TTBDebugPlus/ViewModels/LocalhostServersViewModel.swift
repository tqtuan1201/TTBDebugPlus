//
//  LocalhostServersViewModel.swift
//  TTBDebugPlus
//
//  Orchestrates discovery, lifecycle, logs, and conflicts for Localhost Servers.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class LocalhostServersViewModel {
    enum Pane: String, CaseIterable, Identifiable {
        case livePorts = "Live Ports"
        case myServers = "My Servers"
        var id: String { rawValue }
    }

    // MARK: - Published state

    /// Default to Live Ports — primary JTBD is discover / free a busy port.
    var pane: Pane = .livePorts
    var endpoints: [ListeningEndpoint] = []
    var definitions: [LocalServerDefinition] = []
    var runtimes: [UUID: ManagedServerRuntime] = [:]

    /// Process handles kept out of Equatable UI state.
    @ObservationIgnored
    private var processes: [UUID: Process] = [:]

    var selectedEndpointID: String?
    var selectedDefinitionID: UUID?

    var lastScanAt: Date?
    var isScanning = false
    var scanError: String?
    /// True when discovery produced no endpoints (hard fail); false for soft sandbox warnings with partial data.
    var scanErrorIsHardFailure = false
    var actionError: String?
    /// Short-lived success / info feedback (copy, soft-stop sent).
    var statusMessage: String?

    /// Live Ports search (name, port, PID, address, class).
    var portSearchText: String = ""

    var pendingConflict: PortConflictInfo?
    var pendingForceKill: ForceKillRequest?
    var editorDraft: LocalServerDefinition?
    var isEditorPresented = false

    // MARK: - Protection inputs

    var protectedPorts: Set<Int> = []
    var protectedPIDs: Set<Int32> = [ProcessInfo.processInfo.processIdentifier]

    // MARK: - Private

    @ObservationIgnored
    private var pollTask: Task<Void, Never>?
    @ObservationIgnored
    private var statusClearTask: Task<Void, Never>?
    @ObservationIgnored
    private var isVisible = false

    private let pollIntervalNanos: UInt64 = 3_000_000_000

    // MARK: - Derived

    var selectedEndpoint: ListeningEndpoint? {
        guard let id = selectedEndpointID else { return nil }
        return endpoints.first { $0.id == id }
    }

    var selectedDefinition: LocalServerDefinition? {
        guard let id = selectedDefinitionID else { return nil }
        return definitions.first { $0.id == id }
    }

    var filteredEndpoints: [ListeningEndpoint] {
        let query = portSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return endpoints }
        return endpoints.filter { endpoint in
            endpoint.processName.localizedCaseInsensitiveContains(query)
                || "\(endpoint.port)".contains(query)
                || "\(endpoint.pid)".contains(query)
                || endpoint.address.localizedCaseInsensitiveContains(query)
                || endpoint.addresses.contains { $0.localizedCaseInsensitiveContains(query) }
                || endpoint.classification.displayName.localizedCaseInsensitiveContains(query)
                || endpoint.addressPortLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var livePortsCountLabel: String {
        let n = endpoints.count
        if portSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(n)"
        }
        return "\(filteredEndpoints.count)/\(n)"
    }

    var myServersCountLabel: String {
        "\(definitions.count)"
    }

    func runtime(for id: UUID) -> ManagedServerRuntime {
        if let existing = runtimes[id] { return existing }
        let created = ManagedServerRuntime(id: id, state: .stopped)
        runtimes[id] = created
        return created
    }

    private func updateRuntime(id: UUID, _ mutate: (inout ManagedServerRuntime) -> Void) {
        var rt = runtime(for: id)
        mutate(&rt)
        runtimes[id] = rt
    }

    // MARK: - Lifecycle

    func onAppear(protectedPorts: Set<Int>) {
        self.protectedPorts = protectedPorts
        protectedPIDs.insert(ProcessInfo.processInfo.processIdentifier)
        if definitions.isEmpty {
            definitions = LocalServerStore.load()
            for def in definitions {
                _ = runtime(for: def.id)
            }
        }
        isVisible = true
        Task { await refreshPorts() }
        startPolling()
    }

    func onDisappear() {
        isVisible = false
        stopPolling()
    }

    func updateProtectedPorts(_ ports: Set<Int>) {
        protectedPorts = ports
    }

    // MARK: - Scanning

    func refreshPorts() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let pids = protectedPIDs
        let ports = protectedPorts
        let result = await LocalhostPortScanner.scan(
            protectedPIDs: pids,
            protectedPorts: ports
        )
        endpoints = result.endpoints
        scanError = result.userFacingError
        scanErrorIsHardFailure = result.isHardFailure
        lastScanAt = Date()

        // Drop selection if gone
        if let id = selectedEndpointID, !endpoints.contains(where: { $0.id == id }) {
            selectedEndpointID = nil
        }

        // Correlate owned runtimes with listeners
        for def in definitions {
            let rt = runtime(for: def.id)
            if let preferred = def.preferredPort,
               let match = endpoints.first(where: { $0.port == preferred && (rt.pid == nil || $0.pid == rt.pid) }),
               rt.state == .starting || rt.state == .running {
                updateRuntime(id: def.id) { value in
                    value.state = .running
                    if value.pid == nil { value.pid = match.pid }
                }
            }
        }
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, self.isVisible, !Task.isCancelled else { continue }
                await self.refreshPorts()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Definitions CRUD

    func beginAddServer() {
        editorDraft = LocalServerDefinition.blank()
        isEditorPresented = true
    }

    func beginEditServer(_ def: LocalServerDefinition) {
        editorDraft = def
        isEditorPresented = true
    }

    func saveEditorDraft(_ draft: LocalServerDefinition) {
        var item = draft
        item.updatedAt = Date()
        if let idx = definitions.firstIndex(where: { $0.id == item.id }) {
            definitions[idx] = item
        } else {
            definitions.append(item)
            _ = runtime(for: item.id)
        }
        persist()
        selectedDefinitionID = item.id
        pane = .myServers
        isEditorPresented = false
        editorDraft = nil
    }

    func deleteServer(_ id: UUID) {
        if let rt = runtimes[id], rt.state == .running || rt.state == .starting {
            stopServer(id: id, force: true)
        }
        definitions.removeAll { $0.id == id }
        runtimes[id] = nil
        processes[id] = nil
        if selectedDefinitionID == id { selectedDefinitionID = nil }
        persist()
    }

    private func persist() {
        do {
            try LocalServerStore.save(definitions)
        } catch {
            actionError = "Failed to save servers: \(error.localizedDescription)"
        }
    }

    // MARK: - Server lifecycle

    func startServer(id: UUID, skipConflictCheck: Bool = false) {
        guard let def = definitions.first(where: { $0.id == id }) else { return }
        let rt = runtime(for: id)

        if rt.state == .running || rt.state == .starting {
            actionError = "Server is already running or starting."
            return
        }

        if !skipConflictCheck, let port = def.preferredPort,
           let occupant = LocalhostPortScanner.occupant(of: port, in: endpoints) {
            // Allow if occupant is our own managed pid
            if rt.pid == nil || occupant.pid != rt.pid {
                pendingConflict = PortConflictInfo(
                    port: port,
                    occupant: occupant,
                    definitionID: id
                )
                updateRuntime(id: id) { $0.state = .conflict }
                return
            }
        }

        updateRuntime(id: id) { value in
            value.state = .starting
            value.lastError = nil
            value.logLines = []
            value.startedAt = Date()
        }

        let defCopy = def
        do {
            let handle = try LocalhostServerLauncher.launch(
                definition: defCopy,
                onLog: { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(definitionID: id, line: line)
                    }
                },
                onTerminate: { [weak self] status in
                    Task { @MainActor in
                        self?.handleTermination(definitionID: id, status: status)
                    }
                }
            )
            processes[id] = handle.process
            updateRuntime(id: id) { value in
                value.pid = handle.pid
                value.state = .running
            }
            appendLog(definitionID: id, line: "[ttb] Started pid \(handle.pid)")
            Task { await refreshPorts() }
        } catch {
            updateRuntime(id: id) { value in
                value.state = .failed
                value.lastError = error.localizedDescription
            }
            appendLog(definitionID: id, line: "[ttb] Launch failed: \(error.localizedDescription)")
        }
    }

    func stopServer(id: UUID, force: Bool = false) {
        let rt = runtime(for: id)
        updateRuntime(id: id) { $0.state = .stopping }
        if let process = processes[id] {
            LocalhostProcessController.terminateOwned(process, force: force)
        } else if let pid = rt.pid {
            do {
                try LocalhostProcessController.send(
                    force ? .force : .soft,
                    pid: pid,
                    classification: .user
                )
            } catch {
                actionError = error.localizedDescription
            }
        }
        // Give process a moment; terminationHandler will finalize.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let process = processes[id], process.isRunning, !force {
                LocalhostProcessController.terminateOwned(process, force: true)
            }
            if runtime(for: id).state == .stopping {
                processes[id] = nil
                updateRuntime(id: id) { value in
                    value.state = .stopped
                    value.pid = nil
                }
            }
            await refreshPorts()
        }
    }

    func restartServer(id: UUID) {
        stopServer(id: id, force: false)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            startServer(id: id)
        }
    }

    private func appendLog(definitionID: UUID, line: String) {
        updateRuntime(id: definitionID) { rt in
            LocalhostServerLauncher.appendLogLine(line, to: &rt.logLines)
        }
    }

    private func handleTermination(definitionID: UUID, status: Int32) {
        appendLog(definitionID: definitionID, line: "[ttb] Process exited with status \(status)")
        processes[definitionID] = nil
        let previous = runtime(for: definitionID).state
        updateRuntime(id: definitionID) { rt in
            rt.pid = nil
            if status == 0 {
                rt.state = .stopped
            } else if previous != .stopping {
                rt.state = .failed
                rt.lastError = "Exit status \(status)"
            } else {
                rt.state = .stopped
            }
        }
    }

    // MARK: - External process actions

    func softStopEndpoint(_ endpoint: ListeningEndpoint) {
        do {
            try LocalhostProcessController.send(
                .soft,
                pid: endpoint.pid,
                classification: endpoint.classification
            )
            actionError = nil
            showStatus("Sent SIGTERM to \(endpoint.processName) (PID \(endpoint.pid))")
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshPorts()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func requestForceKill(_ endpoint: ListeningEndpoint, startDefinitionAfter: UUID? = nil) {
        guard LocalhostProcessClassifier.canForceKill(endpoint.classification) else {
            actionError = LocalhostProcessControlError.systemProcessBlocked.errorDescription
            return
        }
        pendingForceKill = ForceKillRequest(
            pid: endpoint.pid,
            port: endpoint.port,
            processName: endpoint.processName,
            classification: endpoint.classification,
            definitionIDToStartAfter: startDefinitionAfter
        )
    }

    func confirmForceKill() {
        guard let req = pendingForceKill else { return }
        do {
            try LocalhostProcessController.send(
                .force,
                pid: req.pid,
                classification: req.classification
            )
            actionError = nil
            showStatus("Sent SIGKILL to \(req.processName) (PID \(req.pid))")
        } catch {
            actionError = error.localizedDescription
            if let defID = req.definitionIDToStartAfter {
                updateRuntime(id: defID) { $0.state = .failed }
            }
            pendingForceKill = nil
            return
        }
        let resumeID = req.definitionIDToStartAfter
        pendingForceKill = nil
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await refreshPorts()
            if let resumeID {
                startServer(id: resumeID, skipConflictCheck: true)
            }
        }
    }

    func cancelForceKill() {
        if let defID = pendingForceKill?.definitionIDToStartAfter {
            updateRuntime(id: defID) { $0.state = .stopped }
        }
        pendingForceKill = nil
    }

    // MARK: - Conflict resolution

    func resolveConflictByKillingOccupant(soft: Bool) {
        guard let conflict = pendingConflict else { return }
        let endpoint = conflict.occupant
        let defID = conflict.definitionID
        pendingConflict = nil

        if soft {
            softStopEndpoint(endpoint)
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await refreshPorts()
                startServer(id: defID, skipConflictCheck: true)
            }
            return
        }

        // Force path always goes through confirmation alert (same as Live Ports).
        requestForceKill(endpoint, startDefinitionAfter: defID)
    }

    func cancelConflict() {
        if let id = pendingConflict?.definitionID {
            updateRuntime(id: id) { $0.state = .stopped }
        }
        pendingConflict = nil
    }

    // MARK: - Helpers

    func copyKillCommand(for endpoint: ListeningEndpoint) {
        let cmd = "kill -TERM \(endpoint.pid)  # port \(endpoint.port) \(endpoint.processName)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        showStatus("Kill command copied")
    }

    func openURLIfConfigured(for def: LocalServerDefinition) {
        let raw = def.openURLOnStart?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlString: String
        if raw.isEmpty, let port = def.preferredPort {
            urlString = "http://127.0.0.1:\(port)"
        } else {
            urlString = raw
        }
        guard let url = URL(string: urlString), !urlString.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    func openURL(for endpoint: ListeningEndpoint) {
        let host = endpoint.preferredOpenHost
        guard let url = URL(string: "http://\(host):\(endpoint.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearLogs(for id: UUID) {
        updateRuntime(id: id) { $0.logLines = [] }
    }

    func showStatus(_ message: String) {
        statusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.statusMessage == message {
                    self?.statusMessage = nil
                }
            }
        }
    }

    var lastScanLabel: String {
        guard let lastScanAt else { return "Never scanned" }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return "Scanned \(formatter.string(from: lastScanAt))"
    }
}
