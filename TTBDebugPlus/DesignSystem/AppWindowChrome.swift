//
//  AppWindowChrome.swift
//  TTBDebugPlus
//
//  Forces NSWindow titlebar / chrome to match the app canvas so macOS
//  never shows a light system strip above the dark UI.
//  Title text: system title is hidden (adaptive black-on-dark bug with
//  transparent titlebars); SwiftUI navigationTitle renders light text instead.
//

import SwiftUI
import AppKit

// MARK: - Window chrome configurator

/// Invisible view that configures its host `NSWindow` for unified dark (or light) chrome.
struct AppWindowChrome: NSViewRepresentable {
    var prefersDark: Bool = true
    var title: String = AppBrand.name
    var subtitle: String = AppBrand.tagline

    func makeNSView(context: Context) -> NSView {
        let view = ChromeHostView()
        view.prefersDark = prefersDark
        view.title = title
        view.subtitle = subtitle
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? ChromeHostView else { return }
        host.prefersDark = prefersDark
        host.title = title
        host.subtitle = subtitle
        host.applyChrome()
    }
}

// MARK: - Host view

private final class ChromeHostView: NSView {
    var prefersDark: Bool = true
    var title: String = AppBrand.name
    var subtitle: String = AppBrand.tagline

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in
            self?.applyChrome()
        }
    }

    func applyChrome() {
        guard let window else { return }

        window.appearance = NSAppearance(named: prefersDark ? .darkAqua : .aqua)

        let insertedFullSize = !window.styleMask.contains(.fullSizeContentView)
        if insertedFullSize {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = true

        // Hide native title + subtitle labels entirely. SwiftUI paints them black
        // on transparent dark titlebars (adaptive contrast bug). We draw a custom
        // white toolbar label in ContentView instead.
        window.titleVisibility = .hidden
        window.title = title // still set for Mission Control / accessibility
        if #available(macOS 11.0, *) {
            window.subtitle = "" // prevent dual black subtitle under custom label
            window.titlebarSeparatorStyle = .none
        }

        window.backgroundColor = prefersDark
            ? NSColor(srgbRed: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 1)
            : NSColor(srgbRed: 241 / 255, green: 245 / 255, blue: 249 / 255, alpha: 1)
        window.isOpaque = true
        window.isMovableByWindowBackground = false

        // fullSizeContentView changes safe-area / column metrics. Without a follow-up
        // layout pass, the sidebar can keep a cold-start measurement (server-stopped
        // chrome missing until Start→Stop). Invalidate AppKit + notify SwiftUI.
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .ttbWindowChromeDidApply, object: window)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted after `AppWindowChrome` applies `fullSizeContentView` / titlebar settings.
    static let ttbWindowChromeDidApply = Notification.Name("ttbWindowChromeDidApply")
}

// MARK: - View modifier

extension View {
    /// Unifies macOS window titlebar with the app design-system canvas.
    func appWindowChrome(
        prefersDark: Bool = true,
        title: String = AppBrand.name,
        subtitle: String = AppBrand.tagline
    ) -> some View {
        background(
            AppWindowChrome(prefersDark: prefersDark, title: title, subtitle: subtitle)
                .frame(width: 0, height: 0)
        )
    }
}
