//
//  OnlineJsonEditorView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-01.
//  WKWebView wrapper for the embedded online-json.com editor clone
//  Provides dual-panel JSON editing (Code + Tree) with live sync
//  Upgraded 2026-07-10: full toolbar, Auto Fix preview, keyboard shortcuts, UX states.
//

import SwiftUI
import WebKit
import AppKit

// MARK: - Online JSON Editor View (Full editor for DevTools)
struct OnlineJsonEditorView: View {
    @Bindable var viewModel: JSONEditorViewModel
    @State private var bridge = OnlineJsonEditorBridge()
    @State private var contentHash: Int = 0
    @State private var displayMode: String = "code"
    @State private var isSearching = false
    @State private var localSearch = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar

            // Status / error banner
            if let banner = viewModel.statusBanner {
                statusBannerView(banner)
            } else if !viewModel.isValid, let err = viewModel.validationErrors.first {
                errorBannerView(err)
            } else if viewModel.isEmpty {
                emptyHintBar
            }

            ZStack {
                OnlineJsonEditorRepresentable(bridge: bridge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.9)
                        .padding(TTSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.ttSurface.opacity(0.92))
                        )
                }
            }

            editorStatusBar
        }
        .background(Color.clear)
        .onAppear { setupBridge() }
        .onChange(of: viewModel.rawJSON) { _, newValue in
            let newHash = newValue.hashValue
            if newHash != contentHash {
                contentHash = newHash
                // Large payloads: set via base64 path inside bridge
                bridge.setContent(newValue)
            }
        }
        .sheet(isPresented: $viewModel.showRepairPreview) {
            if let pending = viewModel.pendingRepair {
                JSONAutoFixPreviewSheet(
                    result: pending,
                    onApply: {
                        let ok = viewModel.applyPendingRepair()
                        if ok {
                            contentHash = viewModel.rawJSON.hashValue
                            bridge.setContent(viewModel.rawJSON)
                        }
                    },
                    onCancel: { viewModel.dismissRepairPreview() }
                )
            }
        }
        .focusable()
        // Keyboard shortcuts (macOS)
        .background(shortcutButtons)
    }

    // Hidden buttons that host keyboard shortcuts
    private var shortcutButtons: some View {
        Group {
            Button("") { syncEditorThen { viewModel.format() } }
                .keyboardShortcut("b", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            Button("") { syncEditorThen { viewModel.minify() } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)
            Button("") { viewModel.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
            Button("") { viewModel.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)
            Button("") {
                isSearching = true
                DispatchQueue.main.async { searchFocused = true }
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0).frame(width: 0, height: 0)
            Button("") { viewModel.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)
            Button("") {
                syncEditorThen { live in viewModel.prepareAutoFix(source: live) }
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .opacity(0).frame(width: 0, height: 0)
            Button("") {
                syncEditorThen { live in viewModel.prepareAutoFormat(source: live) }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .opacity(0).frame(width: 0, height: 0)
        }
    }

    /// Pull latest text from WKWebView before any repair/format action.
    private func syncEditorThen(_ action: @escaping (String) -> Void) {
        bridge.getContent { live in
            DispatchQueue.main.async {
                let text = live.isEmpty ? viewModel.rawJSON : live
                if text != viewModel.rawJSON {
                    viewModel.rawJSON = text
                    contentHash = text.hashValue
                }
                action(text)
            }
        }
    }

    private func syncEditorThen(_ action: @escaping () -> Void) {
        syncEditorThen { _ in action() }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: TTSpacing.xs) {
            // Mode
            HStack(spacing: TTSpacing.hairline) {
                modeButton("code", icon: "chevron.left.forwardslash.chevron.right", label: "Code")
                modeButton("tree", icon: "list.bullet.indent", label: "Tree")
                modeButton("preview", icon: "eye", label: "Preview")
            }

            Divider().frame(height: 16)

            // Search
            if isSearching {
                HStack(spacing: TTSpacing.xxs) {
                    Image(systemName: "magnifyingglass")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(.ttTextTertiary)
                    TextField("Search…", text: $localSearch)
                        .textFieldStyle(.plain)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextPrimary)
                        .frame(width: 140)
                        .focused($searchFocused)
                        .onSubmit { bridge.searchNext() }
                        .onChange(of: localSearch) { _, v in
                            bridge.search(v)
                            viewModel.searchText = v
                        }
                    if bridge.searchMatchCount > 0 {
                        Text("\(bridge.searchMatchCount)")
                            .font(TTFont.badge)
                            .foregroundColor(.ttPrimary)
                        Button(action: { bridge.searchPrevious() }) {
                            Image(systemName: "chevron.up").font(.ttIcon(TTIcon.xs))
                        }
                        .buttonStyle(.plain)
                        Button(action: { bridge.searchNext() }) {
                            Image(systemName: "chevron.down").font(.ttIcon(TTIcon.xs))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: {
                        isSearching = false
                        localSearch = ""
                        bridge.search("")
                    }) {
                        Image(systemName: "xmark").font(.ttIcon(TTIcon.xs))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, TTSpacing.xs)
                .padding(.vertical, TTSpacing.inlineGapSmall)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.ttSurface)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.ttBorder.opacity(0.3)))
                )
            } else {
                toolIcon("magnifyingglass", help: "Search (⌘F)") {
                    isSearching = true
                    DispatchQueue.main.async { searchFocused = true }
                }
            }

            Divider().frame(height: 16)

            // Tree fold
            if displayMode == "tree" {
                Menu {
                    Button("Expand All") { bridge.expandAll() }
                    Button("Collapse All") { bridge.collapseAll() }
                    Divider()
                    Button("Collapse Level 1") { bridge.collapseLevel(1) }
                    Button("Collapse Level 2") { bridge.collapseLevel(2) }
                    Button("Collapse Level 3") { bridge.collapseLevel(3) }
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.ttIcon(TTIcon.sm))
                        .foregroundColor(.ttTextSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
                .help("Expand / Collapse")
            }

            // Core edit actions
            toolIcon("text.alignleft", help: "Format (⌘B)") {
                syncEditorThen { viewModel.format() }
            }
            toolIcon("arrow.left.and.line.vertical.and.arrow.right", help: "Minify (⌘⇧M)") {
                syncEditorThen { viewModel.minify() }
            }

            Button(action: {
                // CRITICAL: pull live WebView text before repair (rawJSON can be stale when invalid)
                syncEditorThen { live in
                    viewModel.prepareAutoFormat(source: live)
                }
            }) {
                Label("Auto Format", systemImage: "wand.and.stars")
                    .font(TTFont.labelSmall)
            }
            .buttonStyle(.ttSecondary)
            .help("Repair common issues + pretty print (⌘⇧F)")

            Button(action: {
                syncEditorThen { live in
                    viewModel.prepareAutoFix(source: live)
                }
            }) {
                Label("Auto Fix", systemImage: "wrench.and.screwdriver")
                    .font(TTFont.labelSmall)
            }
            .buttonStyle(.ttGhost)
            .help("Preview automatic repairs (⌘⇧.)")
            .disabled(viewModel.isEmpty)

            Divider().frame(height: 16)

            toolIcon("arrow.uturn.backward", help: "Undo (⌘Z)", disabled: !viewModel.canUndo) { viewModel.undo() }
            toolIcon("arrow.uturn.forward", help: "Redo (⌘⇧Z)", disabled: !viewModel.canRedo) { viewModel.redo() }

            Spacer(minLength: 8)

            toolIcon("doc.on.clipboard", help: "Paste") { viewModel.paste() }
            toolIcon("doc.on.doc", help: "Copy (⌘⇧C)") { viewModel.copy() }
            toolIcon("trash", help: "Clear", disabled: viewModel.isEmpty) { viewModel.clear() }

            Divider().frame(height: 16)

            toolIcon("folder", help: "Open file…") { viewModel.openFile() }
            toolIcon("square.and.arrow.down", help: "Save…") { viewModel.saveFile() }

            Menu {
                Button("Load Sample JSON") { viewModel.loadSample() }
                Toggle("Auto Format on Load", isOn: Binding(
                    get: { viewModel.autoFormatOnLoad },
                    set: { viewModel.autoFormatOnLoad = $0 }
                ))
                Divider()
                Picker("Indent", selection: Binding(
                    get: { viewModel.indentation },
                    set: { viewModel.indentation = $0 }
                )) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.ttIcon(TTIcon.sm))
                    .foregroundColor(.ttTextSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("More")
        }
        .padding(.horizontal, TTSpacing.inputPaddingH)
        .padding(.vertical, TTSpacing.xs)
        .background(Color.ttSurface.opacity(0.2))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }

    private func modeButton(_ mode: String, icon: String, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                displayMode = mode
                bridge.setMode(mode)
            }
        }) {
            HStack(spacing: TTSpacing.inlineGapSmall) {
                Image(systemName: icon).font(.ttIcon(TTIcon.sm))
                Text(label).font(TTFont.labelSmall)
            }
            .foregroundColor(displayMode == mode ? .white : .ttTextTertiary)
            .padding(.horizontal, TTSpacing.sm)
            .padding(.vertical, TTSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(displayMode == mode ? Color.ttPrimary.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func toolIcon(_ system: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.ttIcon(TTIcon.sm))
                .foregroundColor(disabled ? .ttTextMuted : .ttTextSecondary)
        }
        .buttonStyle(.ttGhost)
        .disabled(disabled)
        .help(help)
    }

    // MARK: - Banners

    private func statusBannerView(_ text: String) -> some View {
        TTBanner(kind: statusBannerKind, message: text)
            .padding(.horizontal, TTSpacing.sm)
            .padding(.vertical, TTSpacing.xxs)
    }

    private var statusBannerKind: TTBannerKind {
        switch viewModel.statusKind {
        case .success: return .success
        case .error: return .error
        case .working: return .warning
        case .neutral: return .info
        }
    }

    private func errorBannerView(_ err: JSONValidationError) -> some View {
        TTBanner(
            kind: errorBannerKind(err),
            message: "Line \(err.line), col \(err.column) — \(err.message)",
            trailing: AnyView(
                Button("Auto Fix") {
                    syncEditorThen { live in viewModel.prepareAutoFix(source: live) }
                }
                .buttonStyle(.ttSecondary)
                .controlSize(.small)
            )
        )
        .padding(.horizontal, TTSpacing.sm)
        .padding(.vertical, TTSpacing.xxs)
    }

    private func errorBannerKind(_ err: JSONValidationError) -> TTBannerKind {
        switch err.severity {
        case .error: return .error
        case .warning: return .warning
        }
    }

    private var emptyHintBar: some View {
        HStack(spacing: TTSpacing.sm) {
            Image(systemName: "curlybraces")
                .foregroundColor(.ttTextSecondary)
            Text("Paste JSON, open a file, or load sample data to get started.")
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextSecondary)
            Spacer()
            Button("Sample") { viewModel.loadSample() }
                .buttonStyle(.ttGhost)
            Button("Paste") { viewModel.paste() }
                .buttonStyle(.ttSecondary)
        }
        .padding(.horizontal, TTSpacing.md)
        .padding(.vertical, TTSpacing.xs)
        .background(Color.ttSurface.opacity(0.35))
    }

    // MARK: - Status Bar

    private var editorStatusBar: some View {
        HStack(spacing: TTSpacing.md) {
            HStack(spacing: TTSpacing.tight) {
                Circle()
                    .fill(viewModel.isEmpty ? Color.ttTextMuted : (viewModel.isValid ? Color.ttSuccess : Color.ttError))
                    .frame(width: 6, height: 6)
                Text(viewModel.isEmpty ? "Empty" : (viewModel.isValid ? "Valid" : "Invalid"))
                    .font(TTFont.codeSmall)
                    .foregroundColor(viewModel.isEmpty ? .ttTextMuted : (viewModel.isValid ? .ttSuccess : .ttError))
            }

            Text(viewModel.formattedSize)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)

            if viewModel.lineCount > 0 {
                Text("\(viewModel.lineCount) lines")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
            }

            if viewModel.nodeCount > 0 {
                Text("\(viewModel.nodeCount) nodes")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
            }

            if viewModel.isDirty {
                Text("Modified")
                    .font(TTFont.badge)
                    .foregroundColor(.ttWarning)
            }

            Spacer()

            if let source = viewModel.sourceLabel {
                Text(source)
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextMuted)
                    .lineLimit(1)
            }

            Text(displayMode.capitalized)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextMuted)

            Text("indent \(viewModel.indentation)")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextMuted)
        }
        .padding(.horizontal, TTSpacing.md)
        .padding(.vertical, TTSpacing.xxs)
        .background(Color.ttSurface.opacity(0.12))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Bridge

    private func setupBridge() {
        bridge.onContentChanged = { json in
            if json.hashValue != viewModel.rawJSON.hashValue {
                // Bridge edits: push undo only on first change of a burst via VM path
                // Avoid undo spam — treat webview edits as direct assignment with single undo push
                if viewModel.rawJSON != json {
                    viewModel.pushUndo()
                    viewModel.rawJSON = json
                    contentHash = json.hashValue
                }
            }
        }

        bridge.onReady = {
            bridge.setEditable(true)
            bridge.setMode(displayMode)
            if !viewModel.rawJSON.isEmpty {
                contentHash = viewModel.rawJSON.hashValue
                bridge.setContent(viewModel.rawJSON)
            }
        }
    }
}

// MARK: - Online JSON Viewer View (Read-Only, for Network/Console inline embedding)
/// Lightweight read-only JSON viewer using the OnlineJsonEditorBridge.
struct OnlineJsonViewerView: View {
    let jsonString: String
    var showToolbar: Bool = true
    var initialMode: String = "tree"
    var showPreviewMode: Bool = true
    var onOpenInEditor: ((String) -> Void)? = nil

    @State private var bridge = OnlineJsonEditorBridge()
    @State private var displayMode: String = "tree"
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @State private var isCopied: Bool = false
    @State private var contentHash: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if showToolbar {
                viewerToolbar
            }

            OnlineJsonEditorRepresentable(bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showToolbar {
                viewerStatusBar
            }
        }
        .onAppear {
            displayMode = initialMode
            setupBridge()
        }
        .onChange(of: jsonString) { _, newValue in
            let newHash = newValue.hashValue
            if newHash != contentHash {
                contentHash = newHash
                bridge.setContent(newValue)
            }
        }
    }

    private var viewerToolbar: some View {
        HStack(spacing: TTSpacing.xxs) {
            HStack(spacing: TTSpacing.hairline) {
                viewerModeButton(mode: "code", icon: "chevron.left.forwardslash.chevron.right", label: "Code")
                viewerModeButton(mode: "tree", icon: "list.bullet.indent", label: "Tree")
                if showPreviewMode {
                    viewerModeButton(mode: "preview", icon: "eye", label: "Preview")
                }
            }

            Divider().frame(height: 14)

            if isSearching {
                HStack(spacing: TTSpacing.xxs) {
                    Image(systemName: "magnifyingglass")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(.ttTextTertiary)

                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextPrimary)
                        .frame(width: 120)
                        .onSubmit { bridge.searchNext() }
                        .onChange(of: searchText) { _, newValue in
                            bridge.search(newValue)
                        }

                    if bridge.searchMatchCount > 0 {
                        Text("\(bridge.searchMatchCount)")
                            .font(TTFont.badge)
                            .foregroundColor(.ttPrimary)

                        Button(action: { bridge.searchPrevious() }) {
                            Image(systemName: "chevron.up")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextSecondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: { bridge.searchNext() }) {
                            Image(systemName: "chevron.down")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        isSearching = false
                        searchText = ""
                        bridge.search("")
                    }) {
                        Image(systemName: "xmark")
                            .font(.ttIcon(TTIcon.xs))
                            .foregroundColor(.ttTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, TTSpacing.xs)
                .padding(.vertical, TTSpacing.inlineGapSmall)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.ttSurface)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.ttBorder.opacity(0.3)))
                )
            } else {
                Button(action: { isSearching = true }) {
                    Image(systemName: "magnifyingglass")
                        .font(.ttIcon(TTIcon.sm))
                }
                .buttonStyle(.ttGhost)
                .help("Search (⌘F)")
            }

            Spacer()

            if displayMode == "tree" {
                Menu {
                    Button("Expand All") { bridge.expandAll() }
                    Button("Collapse All") { bridge.collapseAll() }
                    Divider()
                    Button("Collapse Level 1") { bridge.collapseLevel(1) }
                    Button("Collapse Level 2") { bridge.collapseLevel(2) }
                    Button("Collapse Level 3") { bridge.collapseLevel(3) }
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.ttIcon(TTIcon.sm))
                        .foregroundColor(.ttTextSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }

            Button(action: copyContent) {
                HStack(spacing: TTSpacing.inlineGapSmall) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.ttIcon(TTIcon.sm))
                    if isCopied {
                        Text("Copied").font(TTFont.labelSmall)
                    }
                }
                .foregroundColor(isCopied ? .ttSuccess : .ttTextSecondary)
            }
            .buttonStyle(.ttGhost)

            if let onOpenInEditor {
                Button(action: { onOpenInEditor(jsonString) }) {
                    HStack(spacing: TTSpacing.inlineGapSmall) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.ttIcon(TTIcon.sm))
                        Text("Editor")
                            .font(TTFont.labelSmall)
                    }
                    .foregroundColor(.ttPrimary)
                }
                .buttonStyle(.ttGhost)
            }
        }
        .padding(.horizontal, TTSpacing.sm)
        .padding(.vertical, TTSpacing.xxs)
        .background(Color.ttSurface.opacity(0.15))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }

    private func viewerModeButton(mode: String, icon: String, label: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                displayMode = mode
                bridge.setMode(mode)
            }
        }) {
            HStack(spacing: TTSpacing.inlineGapSmall) {
                Image(systemName: icon).font(.ttIcon(TTIcon.sm))
                Text(label).font(TTFont.labelSmall)
            }
            .foregroundColor(displayMode == mode ? .white : .ttTextTertiary)
            .padding(.horizontal, TTSpacing.sm)
            .padding(.vertical, TTSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(displayMode == mode ? Color.ttPrimary.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var viewerStatusBar: some View {
        HStack(spacing: TTSpacing.md) {
            HStack(spacing: TTSpacing.xxs) {
                Circle()
                    .fill(bridge.isValid ? Color.ttSuccess : Color.ttError)
                    .frame(width: 6, height: 6)
                Text(bridge.isValid ? "Valid" : "Invalid")
                    .font(TTFont.codeSmall)
                    .foregroundColor(bridge.isValid ? .ttSuccess : .ttError)
            }

            Text(formattedSize)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)

            if bridge.lineCount > 0 {
                Text("\(bridge.lineCount) lines")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
            }

            Spacer()

            Text(displayMode.capitalized)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextMuted)

            Text("Read-Only")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextMuted)
                .padding(.horizontal, TTSpacing.xs)
                .padding(.vertical, TTSpacing.hairline)
                .background(Capsule().fill(Color.ttSurface.opacity(0.5)))
        }
        .padding(.horizontal, TTSpacing.inputPaddingH)
        .padding(.vertical, TTSpacing.inlineGapSmall)
        .background(Color.ttSurface.opacity(0.1))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1),
            alignment: .top
        )
    }

    private var formattedSize: String {
        let bytes = jsonString.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func copyContent() {
        bridge.getContent { json in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json.isEmpty ? jsonString : json, forType: .string)
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isCopied = false
            }
        }
    }

    private func setupBridge() {
        bridge.onReady = {
            bridge.setEditable(false)
            bridge.setMode(displayMode)
            if !jsonString.isEmpty {
                contentHash = jsonString.hashValue
                bridge.setContent(jsonString)
            }
        }
    }
}

// MARK: - Bridge (Swift ↔ JS)
@Observable
class OnlineJsonEditorBridge: NSObject {
    var isReady: Bool = false
    var isValid: Bool = true
    var searchMatchCount: Int = 0
    var lineCount: Int = 0
    var onContentChanged: ((String) -> Void)? = nil
    var onReady: (() -> Void)? = nil

    private(set) var webView: WKWebView?
    private var pendingCommands: [() -> Void] = []
    private let base64Threshold = 100_000

    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            OnlineJsonLeakAvoider(delegate: self), name: "jsonBridge"
        )
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
        self.webView = wv
        loadEditor()
        return wv
    }

    private func loadEditor() {
        guard let wv = webView else { return }

        let subdirs = ["WebEditor/dist", "WebEditor"]
        for bundle in editorResourceBundles {
            for subdir in subdirs {
                if let htmlURL = bundle.url(
                    forResource: "online-json-editor",
                    withExtension: "html",
                    subdirectory: subdir
                ) {
                    wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
                    return
                }
            }
        }

        for bundle in editorResourceBundles {
            if let htmlURL = bundle.url(forResource: "online-json-editor", withExtension: "html") {
                wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
                return
            }
        }

        let bundlePath = Bundle.main.bundlePath
        let paths = [
            "Contents/Resources/WebEditor/dist/online-json-editor.html",
            "Contents/Resources/WebEditor/online-json-editor.html",
            "Contents/Resources/online-json-editor.html",
        ]
        for p in paths {
            let fullPath = (bundlePath as NSString).appendingPathComponent(p)
            if FileManager.default.fileExists(atPath: fullPath) {
                let url = URL(fileURLWithPath: fullPath)
                wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                return
            }
        }
        print("[OnlineJsonEditorBridge] ERROR: Could not find online-json-editor.html")
    }

    private var editorResourceBundles: [Bundle] {
        #if SWIFT_PACKAGE
        return [Bundle.module, Bundle.main]
        #else
        return [Bundle.main]
        #endif
    }

    func setContent(_ json: String) {
        executeWhenReady {
            if json.count > self.base64Threshold {
                let b64 = Data(json.utf8).base64EncodedString()
                self.evaluateJS("window.TTBridge.setContent('\(self.escapeJS(b64))', 'base64')")
            } else {
                self.evaluateJS("window.TTBridge.setContent(\(self.jsonStringLiteral(json)))")
            }
        }
    }

    func setMode(_ mode: String) {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.setMode('\(mode)')")
        }
    }

    func setEditable(_ editable: Bool) {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.setEditable(\(editable))")
        }
    }

    func search(_ term: String) {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.search(\(self.jsonStringLiteral(term)))")
        }
    }

    func searchNext() {
        executeWhenReady { self.evaluateJS("window.TTBridge.searchNext()") }
    }

    func searchPrevious() {
        executeWhenReady { self.evaluateJS("window.TTBridge.searchPrevious()") }
    }

    func format() {
        executeWhenReady { self.evaluateJS("window.TTBridge.format()") }
    }

    func minify() {
        executeWhenReady { self.evaluateJS("window.TTBridge.minify()") }
    }

    func expandAll() {
        executeWhenReady { self.evaluateJS("window.TTBridge.expandAll()") }
    }

    func collapseAll() {
        executeWhenReady { self.evaluateJS("window.TTBridge.collapseAll()") }
    }

    func collapseLevel(_ level: Int) {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.collapseLevel(\(level))")
        }
    }

    func getContent(completion: @escaping (String) -> Void) {
        executeWhenReady {
            self.webView?.evaluateJavaScript("window.TTBridge.getContent()") { result, _ in
                completion(result as? String ?? "")
            }
        }
    }

    private func executeWhenReady(_ block: @escaping () -> Void) {
        if isReady { block() }
        else { pendingCommands.append(block) }
    }

    private func evaluateJS(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[OnlineJsonEditorBridge] JS Error: \(error.localizedDescription)")
            }
        }
    }

    private func escapeJS(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "'", with: "\\'")
           .replacingOccurrences(of: "\n", with: "\\n")
           .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func jsonStringLiteral(_ str: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: str, options: .fragmentsAllowed),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(escapeJS(str))\""
    }

    func cleanup() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "jsonBridge")
        webView?.navigationDelegate = nil
        webView = nil
        isReady = false
        pendingCommands.removeAll()
        onContentChanged = nil
        onReady = nil
    }

    deinit { cleanup() }
}

extension OnlineJsonEditorBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "jsonBridge",
              let bodyStr = message.body as? String,
              let data = bodyStr.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = msg["event"] as? String else { return }

        let eventData = msg["data"] as? [String: Any] ?? [:]

        DispatchQueue.main.async { [weak self] in
            self?.handleEvent(event, data: eventData)
        }
    }

    private func handleEvent(_ event: String, data: [String: Any]) {
        switch event {
        case "ready":
            isReady = true
            onReady?()
            for cmd in pendingCommands { cmd() }
            pendingCommands.removeAll()

        case "contentChanged":
            isValid = data["valid"] as? Bool ?? true
            lineCount = data["lines"] as? Int ?? lineCount
            getContent { [weak self] json in
                self?.onContentChanged?(json)
            }

        case "contentLoaded":
            isValid = data["valid"] as? Bool ?? true
            lineCount = data["lines"] as? Int ?? lineCount

        case "searchResult":
            searchMatchCount = data["count"] as? Int ?? 0

        case "modeChanged", "pong":
            break

        default:
            break
        }
    }
}

extension OnlineJsonEditorBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[OnlineJsonEditorBridge] Navigation failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        loadEditor()
    }
}

private class OnlineJsonLeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct OnlineJsonEditorRepresentable: NSViewRepresentable {
    let bridge: OnlineJsonEditorBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.createWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "jsonBridge")
    }
}
