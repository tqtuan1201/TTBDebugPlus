//
//  JSONWebViewBridge.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-31.
//  WKWebView ↔ Swift bidirectional bridge for JSON editor
//

import WebKit
import SwiftUI

/// Bidirectional bridge between Swift and the embedded JSON WebView editor.
/// Handles command queuing, base64 encoding for large payloads, and debounced callbacks.
@Observable
class JSONWebViewBridge: NSObject {
    // MARK: - Public State
    var isReady: Bool = false
    var isValid: Bool = true
    var validationError: String? = nil
    var searchMatchCount: Int = 0
    var contentSize: Int = 0
    var lineCount: Int = 0
    var charCount: Int = 0
    
    // MARK: - Callbacks
    var onContentChanged: ((String) -> Void)? = nil
    var onReady: (() -> Void)? = nil
    var onCopied: ((String) -> Void)? = nil
    
    // MARK: - Private
    private(set) var webView: WKWebView?
    private var pendingCommands: [() -> Void] = []
    private let base64Threshold = 100_000 // 100KB
    private var isUpdatingFromJS = false
    
    // MARK: - Setup
    
    func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(LeakAvoider(delegate: self), name: "jsonBridge")
        
        // Allow inline media
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground") // Transparent background
        self.webView = wv
        loadEditor()
        return wv
    }
    
    private func loadEditor() {
        guard let wv = webView else { return }
        
        // 1. Folder reference: WebEditor/dist/index.html
        let subdirs = ["WebEditor/dist", "WebEditor"]
        for bundle in editorResourceBundles {
            for subdir in subdirs {
                if let htmlURL = bundle.url(forResource: "index", withExtension: "html", subdirectory: subdir) {
                    wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
                    return
                }
            }
        }
        
        // 2. Root level (flat bundle — XcodeGen default without folder reference)
        for bundle in editorResourceBundles {
            if let htmlURL = bundle.url(forResource: "index", withExtension: "html") {
                wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
                return
            }
        }
        
        // 3. Direct filesystem search
        let bundlePath = Bundle.main.bundlePath
        let paths = [
            "Contents/Resources/WebEditor/dist/index.html",
            "Contents/Resources/WebEditor/index.html",
            "Contents/Resources/index.html",
        ]
        for p in paths {
            let fullPath = (bundlePath as NSString).appendingPathComponent(p)
            if FileManager.default.fileExists(atPath: fullPath) {
                let url = URL(fileURLWithPath: fullPath)
                wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                return
            }
        }
        print("[JSONWebViewBridge] ERROR: Could not find WebEditor HTML")
    }

    private var editorResourceBundles: [Bundle] {
        #if SWIFT_PACKAGE
        return [Bundle.module, Bundle.main]
        #else
        return [Bundle.main]
        #endif
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
        executeWhenReady {
            self.evaluateJS("window.TTBridge.format()")
        }
    }
    
    func minify() {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.minify()")
        }
    }
    
    func expandAll() {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.expandAll()")
        }
    }
    
    func collapseAll() {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.collapseAll()")
        }
    }
    
    func collapseLevel(_ level: Int) {
        executeWhenReady {
            self.evaluateJS("window.TTBridge.collapseLevel(\(level))")
        }
    }
    
    func getContent(completion: @escaping (String) -> Void) {
        executeWhenReady {
            self.webView?.evaluateJavaScript("window.TTBridge.getContent()") { result, error in
                if let json = result as? String {
                    completion(json)
                } else {
                    completion("")
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func executeWhenReady(_ block: @escaping () -> Void) {
        if isReady {
            block()
        } else {
            pendingCommands.append(block)
        }
    }
    
    private func evaluateJS(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[JSONWebViewBridge] JS Error: \(error.localizedDescription)")
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
    
    // MARK: - Cleanup
    
    func cleanup() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "jsonBridge")
        webView?.navigationDelegate = nil
        webView = nil
        isReady = false
        pendingCommands.removeAll()
        onContentChanged = nil
        onReady = nil
        onCopied = nil
    }

    deinit {
        // Ensure script handler is removed so WKWebView does not retain the bridge
        cleanup()
    }
}

// MARK: - WKScriptMessageHandler
extension JSONWebViewBridge: WKScriptMessageHandler {
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
            // Execute pending commands
            for cmd in pendingCommands {
                cmd()
            }
            pendingCommands.removeAll()
            
        case "contentChanged":
            isValid = data["valid"] as? Bool ?? true
            validationError = data["error"] as? String
            contentSize = data["size"] as? Int ?? 0
            lineCount = data["lines"] as? Int ?? 0
            charCount = data["chars"] as? Int ?? 0
            
            // Fetch content and notify
            isUpdatingFromJS = true
            getContent { [weak self] json in
                self?.onContentChanged?(json)
                self?.isUpdatingFromJS = false
            }
            
        case "contentLoaded":
            isValid = data["valid"] as? Bool ?? true
            contentSize = data["size"] as? Int ?? 0
            validationError = data["error"] as? String
            lineCount = data["lines"] as? Int ?? 0
            charCount = data["chars"] as? Int ?? 0
            
        case "searchResult":
            searchMatchCount = data["count"] as? Int ?? 0
            
        case "modeChanged":
            break
            
        case "copied":
            if let text = data["text"] as? String {
                onCopied?(text)
            }
            
        case "pong":
            break
            
        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate
extension JSONWebViewBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // WebView loaded — JS init will call notifySwift('ready')
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[JSONWebViewBridge] Navigation failed: \(error.localizedDescription)")
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Crash recovery — reload
        print("[JSONWebViewBridge] Web content process terminated — reloading")
        isReady = false
        loadEditor()
    }
}

// MARK: - Leak Avoider
/// Prevents retain cycle between WKUserContentController and Bridge
private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
