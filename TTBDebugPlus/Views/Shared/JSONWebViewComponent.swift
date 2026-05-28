//
//  JSONWebViewComponent.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-31.
//  Reusable SwiftUI component wrapping WKWebView JSON editor
//  Replaces JSONViewer (read-only) and JSONEditorCodeView/JSONEditorTreeView (editable)
//

import SwiftUI
import WebKit

// MARK: - Display Mode
enum JSONDisplayMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case code = "Code"
    case tree = "Tree"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .tree: return "list.bullet.indent"
        case .preview: return "eye"
        }
    }
    
    /// Maps to JS bridge mode names
    var jsMode: String {
        switch self {
        case .code: return "code"
        case .tree: return "tree"
        case .preview: return "preview"
        }
    }
}

// MARK: - JSON WebView Component
struct JSONWebViewComponent: View {
    let jsonString: String
    var isEditable: Bool = true
    var showToolbar: Bool = true
    var initialMode: JSONDisplayMode = .tree
    var onContentChange: ((String) -> Void)? = nil
    var onOpenInEditor: ((String) -> Void)? = nil
    
    @State private var bridge = JSONWebViewBridge()
    @State private var displayMode: JSONDisplayMode = .tree
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var isCopied: Bool = false
    @State private var contentHash: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if showToolbar {
                toolbarView
            }
            
            JSONWebViewRepresentable(bridge: bridge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if showToolbar {
                statusBarView
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
    
    // MARK: - Toolbar
    private var toolbarView: some View {
        HStack(spacing: 4) {
            // Mode picker
            HStack(spacing: 1) {
                ForEach(JSONDisplayMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            displayMode = mode
                            bridge.setMode(mode.jsMode)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.ttIcon(TTIcon.sm))
                            Text(mode.rawValue)
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
            }
            
            Divider().frame(height: 14)
            
            // Search
            if isSearching {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(.ttTextTertiary)
                    
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextPrimary)
                        .frame(width: 180)
                        .focused($isSearchFocused)
                        .onSubmit {
                            bridge.search(searchText)
                        }
                        .onChange(of: searchText) { _, newValue in
                            bridge.search(newValue)
                        }
                    
                    Text(searchResultText)
                        .font(TTFont.badge)
                        .foregroundColor(searchText.isEmpty ? .ttTextMuted : (bridge.searchMatchCount > 0 ? .ttPrimary : .ttWarning))
                        .frame(minWidth: 34, alignment: .trailing)
                    
                    Button(action: {
                        isSearching = false
                        isSearchFocused = false
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
                Button(action: {
                    isSearching = true
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.ttIcon(TTIcon.sm))
                }
                .buttonStyle(.ttGhost)
                .help("Search (⌘F)")
                .accessibilityLabel("Search JSON")
            }
            
            Spacer()
            
            // Tree controls (only in tree mode)
            if displayMode == .tree {
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
            
            // Format/Minify
            if isEditable {
                Button(action: { bridge.format() }) {
                    Image(systemName: "text.alignleft")
                        .font(.ttIcon(TTIcon.sm))
                }
                .buttonStyle(.ttGhost)
                .help("Format (⌥⇧F)")
                .accessibilityLabel("Format JSON")
                
                Button(action: { bridge.minify() }) {
                    Image(systemName: "text.justify.leading")
                        .font(.ttIcon(TTIcon.sm))
                }
                .buttonStyle(.ttGhost)
                .help("Minify")
                .accessibilityLabel("Minify JSON")
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
            
            // Open in Editor (for read-only mode)
            if !isEditable, let onOpenInEditor = onOpenInEditor {
                Button(action: {
                    onOpenInEditor(jsonString)
                }) {
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
            
            // Validation indicator
            if !bridge.isValid {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ttIcon(TTIcon.sm))
                        .foregroundColor(.ttError)
                    Text("Invalid")
                        .font(TTFont.labelSmall)
                        .foregroundColor(.ttError)
                }
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
    
    // MARK: - Status Bar
    private var statusBarView: some View {
        HStack(spacing: 12) {
            // Size
            Text(formattedSize)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
            
            // Lines
            if bridge.lineCount > 0 {
                Text("\(bridge.lineCount) lines")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
            }
            
            Spacer()
            
            // Mode indicator
            Text(displayMode.rawValue)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextMuted)
            
            // Read-only badge
            if !isEditable {
                Text("Read-Only")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.ttSurface.opacity(0.5))
                    )
            }
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
    
    private var searchResultText: String {
        if searchText.isEmpty { return "Find" }
        return bridge.searchMatchCount > 0 ? "\(bridge.searchMatchCount)" : "0"
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
        bridge.onContentChanged = { json in
            onContentChange?(json)
        }
        
        bridge.onReady = {
            bridge.setEditable(isEditable)
            bridge.setMode(displayMode.jsMode)
            if !jsonString.isEmpty {
                contentHash = jsonString.hashValue
                bridge.setContent(jsonString)
            }
        }
    }
}

// MARK: - NSViewRepresentable for WKWebView
struct JSONWebViewRepresentable: NSViewRepresentable {
    let bridge: JSONWebViewBridge
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = bridge.createWebView()
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Updates are handled through the bridge, not through SwiftUI updates
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) {
        nsView.stopLoading()
        nsView.navigationDelegate = nil
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "jsonBridge")
    }
}
