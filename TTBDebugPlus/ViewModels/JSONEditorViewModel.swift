//
//  JSONEditorViewModel.swift
//  DebugKit
//
//  Created by TuanTruong on 2026-03-29.
//  Core state management for JSON Editor — validate, format, minify, undo/redo, auto-fix.
//  Upgraded 2026-07-10: JSONRepairEngine, friendly errors, Auto Format/Fix preview, UX status.
//

import SwiftUI

@Observable
class JSONEditorViewModel {
    private enum DefaultsKey {
        static let rawJSON = "devTools.jsonEditor.rawJSON"
        static let sourceLabel = "devTools.jsonEditor.sourceLabel"
        static let indentation = "jsonIndentation"
        static let autoFormatOnLoad = "devTools.jsonEditor.autoFormatOnLoad"
    }

    // MARK: - Editor State
    var rawJSON: String = "" {
        didSet {
            if rawJSON != oldValue {
                isDirty = true
                // Persist only reasonably sized payloads to avoid UserDefaults bloat
                if !suppressPersistence, rawJSON.utf8.count <= 512_000 {
                    UserDefaults.standard.set(rawJSON, forKey: DefaultsKey.rawJSON)
                }
                scheduleValidateAndStats()
            }
        }
    }

    var isValid: Bool = true
    var validationErrors: [JSONValidationError] = []
    var sourceLabel: String? = nil {
        didSet {
            if let sourceLabel {
                UserDefaults.standard.set(sourceLabel, forKey: DefaultsKey.sourceLabel)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.sourceLabel)
            }
        }
    }
    var fileErrorMessage: String? = nil

    /// Transient toast / status for success actions (copy, format, fix applied)
    var statusBanner: String? = nil
    var statusKind: StatusKind = .neutral

    enum StatusKind {
        case neutral, success, error, working
    }

    // MARK: - Search (synced with bridge when possible)
    var searchText: String = ""
    var searchMatchCount: Int = 0
    var currentMatchIndex: Int = 0
    var isSearchPresented: Bool = false

    // MARK: - Stats
    var characterCount: Int = 0
    var lineCount: Int = 0
    var nodeCount: Int = 0
    var isDirty: Bool = false
    var isProcessing: Bool = false

    // MARK: - Auto Fix Preview
    var pendingRepair: JSONRepairResult? = nil
    var showRepairPreview: Bool = false

    /// Auto pretty-print after successful load/paste when content is already valid.
    var autoFormatOnLoad: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.autoFormatOnLoad) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoFormatOnLoad) }
    }

    // MARK: - Undo/Redo
    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private let maxHistory = 50

    // MARK: - Debounce
    private var validateTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    /// Skip UserDefaults write storm when applying large repairs.
    private var suppressPersistence = false

    init() {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.rawJSON) ?? ""
        // Avoid loading huge stale blobs into memory unexpectedly
        if stored.utf8.count <= 2_000_000 {
            rawJSON = stored
        }
        sourceLabel = UserDefaults.standard.string(forKey: DefaultsKey.sourceLabel)
        validate()
        updateStats(immediate: true)
        isDirty = false
    }

    deinit {
        validateTask?.cancel()
        statsTask?.cancel()
        bannerTask?.cancel()
    }

    // MARK: - Indentation
    var indentation: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: DefaultsKey.indentation)
            return stored == 0 ? 2 : max(1, min(stored, 8))
        }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.indentation) }
    }

    var isEmpty: Bool {
        rawJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    func loadJSON(_ json: String, source: String? = nil, autoFormat: Bool? = nil) {
        pushUndo()
        applyContent(json)
        sourceLabel = source
        validate()
        let shouldFormat = autoFormat ?? autoFormatOnLoad
        if shouldFormat, isValid, !isEmpty {
            format(showStatus: false)
        }
        flashStatus("Loaded\(source.map { " from \($0)" } ?? "")", kind: .success)
    }

    func format(showStatus: Bool = true) {
        isProcessing = true
        defer { isProcessing = false }
        guard let str = JSONFormatter.prettyPrint(rawJSON, indentation: indentation) else {
            if showStatus { flashStatus("Format failed — fix errors first or use Auto Fix", kind: .error) }
            return
        }
        guard str != rawJSON else {
            if showStatus { flashStatus("Already formatted", kind: .neutral) }
            return
        }
        pushUndo()
        applyContent(str)
        if showStatus { flashStatus("Formatted", kind: .success) }
    }

    func minify(showStatus: Bool = true) {
        isProcessing = true
        defer { isProcessing = false }
        guard let str = JSONFormatter.minify(rawJSON) else {
            if showStatus { flashStatus("Minify failed — JSON is invalid", kind: .error) }
            return
        }
        pushUndo()
        applyContent(str)
        if showStatus { flashStatus("Minified", kind: .success) }
    }

    /// Repair + pretty print. Pass `source` from the live editor (WebView) to avoid stale rawJSON.
    func prepareAutoFormat(source: String? = nil) {
        isProcessing = true
        defer { isProcessing = false }

        let input = source ?? rawJSON
        // Keep VM in sync with what we are about to repair
        if let source, source != rawJSON {
            rawJSON = source
        }

        let result = JSONRepairEngine.autoFormat(input, indentation: indentation)
        presentRepairResult(result, emptySuccess: "Already valid & formatted")
    }

    /// Repair malformed JSON. Prefer calling with live editor text.
    func prepareAutoFix(source: String? = nil) {
        isProcessing = true
        defer { isProcessing = false }

        let input = source ?? rawJSON
        if let source, source != rawJSON {
            rawJSON = source
        }

        var result = JSONRepairEngine.repair(input)
        // Pretty only when fully valid — never pretty-print invalid output
        if result.isValidAfterRepair,
           let pretty = JSONFormatter.prettyPrint(result.repaired, indentation: indentation),
           pretty != result.repaired {
            var fixes = result.fixes
            fixes.append(JSONRepairFix(kind: .prettyPrint, description: "Applied pretty-print formatting"))
            result = JSONRepairResult(
                original: result.original,
                repaired: pretty,
                fixes: fixes,
                isValidAfterRepair: true,
                validationMessage: nil,
                failureReason: nil
            )
        }
        presentRepairResult(result, emptySuccess: "JSON is already valid")
    }

    private func presentRepairResult(_ result: JSONRepairResult, emptySuccess: String) {
        // Already good, nothing to do
        if !result.didChange {
            if result.isValidAfterRepair {
                flashStatus(emptySuccess, kind: .success)
            } else {
                flashStatus(
                    result.failureReason
                        ?? result.validationMessage
                        ?? "No automatic fixes available",
                    kind: .error
                )
            }
            return
        }

        // Changed but still invalid — do NOT open apply sheet; show clear failure
        if !result.isValidAfterRepair {
            flashStatus(
                result.failureReason
                    ?? result.validationMessage
                    ?? "Auto Fix could not produce valid JSON",
                kind: .error
            )
            // Still surface diagnostics in validation panel
            if let issue = JSONValidator.validate(result.repaired) {
                validationErrors = [
                    JSONValidationError(
                        line: issue.line,
                        column: issue.column,
                        message: issue.friendlyMessage,
                        severity: .error
                    )
                ]
                isValid = false
            }
            return
        }

        // Valid repair — preview before apply
        pendingRepair = result
        showRepairPreview = true
    }

    /// Apply only when repair produced **valid** JSON (no silent partial apply).
    @discardableResult
    func applyPendingRepair() -> Bool {
        guard let pending = pendingRepair else { return false }

        // Hard gate: re-validate before mutating editor
        guard pending.isValidAfterRepair,
              JSONValidator.isValid(pending.repaired) else {
            flashStatus(
                pending.failureReason
                    ?? "Refusing to apply — result is not valid JSON",
                kind: .error
            )
            showRepairPreview = false
            pendingRepair = nil
            return false
        }

        pushUndo()
        applyContent(pending.repaired)
        validate()
        showRepairPreview = false
        let fixCount = pending.fixes.count
        pendingRepair = nil

        if isValid {
            flashStatus(
                "Auto Fix applied (\(fixCount) fix\(fixCount == 1 ? "" : "es"))",
                kind: .success
            )
            return true
        } else {
            // Should not happen after gate — rollback via undo message
            flashStatus("Apply aborted — validation failed after write", kind: .error)
            return false
        }
    }

    func dismissRepairPreview() {
        showRepairPreview = false
        pendingRepair = nil
    }

    func validate() {
        validationErrors = []
        guard !isEmpty else {
            isValid = true
            return
        }

        if let issue = JSONValidator.validate(rawJSON) {
            isValid = false
            validationErrors = [
                JSONValidationError(
                    line: issue.line,
                    column: issue.column,
                    message: issue.friendlyMessage,
                    severity: .error
                )
            ]
        } else {
            isValid = true
        }
    }

    func clear() {
        guard !isEmpty else { return }
        pushUndo()
        applyContent("")
        sourceLabel = nil
        flashStatus("Cleared", kind: .neutral)
    }

    func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rawJSON, forType: .string)
        flashStatus("Copied to clipboard", kind: .success)
        #endif
    }

    func paste() {
        #if os(macOS)
        if let str = NSPasteboard.general.string(forType: .string) {
            pushUndo()
            applyContent(str)
            if autoFormatOnLoad, JSONValidator.isValid(str) {
                format(showStatus: false)
            }
            flashStatus("Pasted", kind: .success)
        }
        #endif
    }

    // MARK: - Undo/Redo

    func pushUndo() {
        undoStack.append(rawJSON)
        if undoStack.count > maxHistory {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(rawJSON)
        applyContent(prev)
        flashStatus("Undo", kind: .neutral)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(rawJSON)
        applyContent(next)
        flashStatus("Redo", kind: .neutral)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - File I/O

    func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.loadJSON(content, source: url.lastPathComponent)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.fileErrorMessage = "Could not open file: \(error.localizedDescription)"
                    }
                }
            }
        }
        #endif
    }

    func saveFile() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceLabel ?? "data.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try self.rawJSON.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.isDirty = false
                        self.sourceLabel = url.lastPathComponent
                        self.flashStatus("Saved \(url.lastPathComponent)", kind: .success)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.fileErrorMessage = "Could not save file: \(error.localizedDescription)"
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Sample Data

    func loadSample() {
        let sample = """
        {
          "name": "DebugKit",
          "version": "1.0.0",
          "description": "Professional iOS debugging companion for macOS",
          "features": [
            "Console Logs",
            "Network Inspector",
            "Device Management",
            "Performance Monitor",
            "JSON Editor"
          ],
          "config": {
            "theme": "dark",
            "indentation": 2,
            "maxLogEntries": 10000,
            "autoConnect": true
          },
          "devices": [
            {
              "id": "device-001",
              "name": "iPhone 15 Pro",
              "os": "iOS 18.0",
              "isConnected": true,
              "metrics": {
                "cpu": 23.5,
                "memory": 156.2,
                "battery": 87
              }
            }
          ],
          "stats": {
            "totalRequests": 1250,
            "avgResponseTime": 245.6,
            "errorRate": 0.02,
            "uptime": null
          }
        }
        """
        loadJSON(sample, source: "Sample Data")
    }

    // MARK: - Private Helpers

    private func applyContent(_ value: String) {
        suppressPersistence = value.utf8.count > 512_000
        rawJSON = value
        suppressPersistence = false
        if value.utf8.count > 512_000 {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.rawJSON)
        }
    }

    private func scheduleValidateAndStats() {
        validateDebounced()
        updateStats(immediate: false)
    }

    private func validateDebounced() {
        validateTask?.cancel()
        validateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            validate()
        }
    }

    private func updateStats(immediate: Bool) {
        characterCount = rawJSON.count
        lineCount = rawJSON.isEmpty ? 0 : rawJSON.components(separatedBy: "\n").count

        statsTask?.cancel()
        let delay: UInt64 = immediate ? 0 : 150_000_000
        statsTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            let input = rawJSON
            // Off-main for large graphs
            let count = await Task.detached(priority: .utility) {
                JSONFormatter.countNodes(input)
            }.value
            guard !Task.isCancelled else { return }
            nodeCount = count
        }
    }

    func flashStatus(_ message: String, kind: StatusKind) {
        statusBanner = message
        statusKind = kind
        bannerTask?.cancel()
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            if statusBanner == message {
                statusBanner = nil
                statusKind = .neutral
            }
        }
    }

    // MARK: - Formatted Size
    var formattedSize: String {
        let bytes = rawJSON.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
