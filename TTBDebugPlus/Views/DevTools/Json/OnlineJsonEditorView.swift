//
//  OnlineJsonEditorView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-01.
//  WKWebView wrapper for the embedded online-json.com editor clone
//  Provides dual-panel JSON editing (Code + Tree) with live sync
//  Also provides OnlineJsonViewerView for read-only inline embedding
//

import SwiftUI
import WebKit

// MARK: - Online JSON Editor View (Full editor for DevTools)
struct OnlineJsonEditorView: View {
    @Bindable var viewModel: JSONEditorViewModel
    @State private var bridge = OnlineJsonEditorBridge()
    @State private var contentHash: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            OnlineJsonEditorRepresentable(bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .onAppear {
            setupBridge()
        }
        .onChange(of: viewModel.rawJSON) { _, newValue in
            let newHash = newValue.hashValue
            if newHash != contentHash {
                contentHash = newHash
                bridge.setContent(newValue)
            }
        }
    }
    
    private func setupBridge() {
        bridge.onContentChanged = { json in
            if json.hashValue != viewModel.rawJSON.hashValue {
                viewModel.rawJSON = json
            }
        }
        
        bridge.onReady = {
            if !viewModel.rawJSON.isEmpty {
                contentHash = viewModel.rawJSON.hashValue
                bridge.setContent(viewModel.rawJSON)
            }
        }
    }
}

// MARK: - Online JSON Viewer View (Read-Only, for Network/Console inline embedding)
/// Lightweight read-only JSON viewer using the OnlineJsonEditorBridge.
/// Replaces JSONWebViewComponent for inline display in detail panes.
struct OnlineJsonViewerView: View {
    let jsonString: String
    var showToolbar: Bool = true
    var initialMode: String = "tree" // "tree", "code", or "preview"
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
    
    // MARK: - Compact Toolbar (Read-Only)
    private var viewerToolbar: some View {
        HStack(spacing: 4) {
            // Mode picker (compact)
            HStack(spacing: 1) {
                viewerModeButton(mode: "code", icon: "chevron.left.forwardslash.chevron.right", label: "Code")
                viewerModeButton(mode: "tree", icon: "list.bullet.indent", label: "Tree")
                viewerModeButton(mode: "preview", icon: "eye", label: "Preview")
            }
            
            Divider().frame(height: 14)
            
            // Search toggle
            if isSearching {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(.ttTextTertiary)
                    
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextPrimary)
                        .frame(width: 120)
                        .onSubmit { bridge.search(searchText) }
                        .onChange(of: searchText) { _, newValue in
                            bridge.search(newValue)
                        }
                    
                    if bridge.searchMatchCount > 0 {
                        Text("\(bridge.searchMatchCount)")
                            .font(TTFont.badge)
                            .foregroundColor(.ttPrimary)
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
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
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
                .accessibilityLabel("Search JSON")
            }
            
            Spacer()
            
            // Tree controls (only in tree mode)
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
                .help("Collapse/Expand")
            }
            
            // Copy
            Button(action: copyContent) {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.ttIcon(TTIcon.sm))
                    if isCopied {
                        Text("Copied")
                            .font(TTFont.labelSmall)
                    }
                }
                .foregroundColor(isCopied ? .ttSuccess : .ttTextSecondary)
            }
            .buttonStyle(.ttGhost)
            .help("Copy All")
            .accessibilityLabel("Copy JSON")
            
            // Open in Editor
            if let onOpenInEditor = onOpenInEditor {
                Button(action: { onOpenInEditor(jsonString) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.ttIcon(TTIcon.sm))
                        Text("Editor")
                            .font(TTFont.labelSmall)
                    }
                    .foregroundColor(.ttPrimary)
                }
                .buttonStyle(.ttGhost)
                .help("Open in JSON Editor")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.sm))
                Text(label)
                    .font(TTFont.labelSmall)
            }
            .foregroundColor(displayMode == mode ? .white : .ttTextTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(displayMode == mode ? Color.ttPrimary.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Status Bar
    private var viewerStatusBar: some View {
        HStack(spacing: 12) {
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
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.ttSurface.opacity(0.5))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color.ttSurface.opacity(0.1))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1),
            alignment: .top
        )
    }
    
    // MARK: - Helpers
    private var formattedSize: String {
        let bytes = jsonString.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
    
    private func copyContent() {
        bridge.getContent { json in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
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
        
        // 1. Folder reference: WebEditor/dist/online-json-editor.html
        let subdirs = ["WebEditor/dist", "WebEditor"]
        for subdir in subdirs {
            if let htmlURL = Bundle.main.url(
                forResource: "online-json-editor",
                withExtension: "html",
                subdirectory: subdir
            ) {
                wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
                return
            }
        }
        
        // 2. Root level (flat bundle — XcodeGen default without folder reference)
        if let htmlURL = Bundle.main.url(forResource: "online-json-editor", withExtension: "html") {
            wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            return
        }
        
        // 3. Direct filesystem search
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
    
    // MARK: - Commands (Swift → JS)
    
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
    
    // MARK: - Helpers
    
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
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "jsonBridge")
        webView?.navigationDelegate = nil
        webView = nil
    }
}

// MARK: - WKScriptMessageHandler
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
            
        case "modeChanged":
            break
            
        case "pong":
            break
            
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate
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

// MARK: - Leak Avoider
private class OnlineJsonLeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - NSViewRepresentable
struct OnlineJsonEditorRepresentable: NSViewRepresentable {
    let bridge: OnlineJsonEditorBridge
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = bridge.createWebView()
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "jsonBridge")
    }
}
