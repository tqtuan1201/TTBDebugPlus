//
//  LaunchAtLoginService.swift
//  DebugKit
//
//  Thin wrapper around SMAppService.mainApp for Open at Login.
//  Keeps registration logic out of views; surfaces actionable status/errors.
//

import AppKit
import Foundation
import ServiceManagement

/// Registers / unregisters the main app as a macOS Login Item (macOS 13+).
@Observable
@MainActor
final class LaunchAtLoginService {

    static let shared = LaunchAtLoginService()

    private(set) var status: SMAppService.Status
    private(set) var lastErrorMessage: String?

    private init() {
        status = SMAppService.mainApp.status
    }

    // MARK: - Derived state

    /// UI switch “on” for enabled or pending user approval.
    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    /// Always allow the toggle — even `.notFound` should attempt `register()` so the user
    /// gets a real error instead of a permanently dead control.
    var isToggleAvailable: Bool { true }

    /// Short secondary line under the toggle (menu bar / settings caption).
    var detailMessage: String? {
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return lastErrorMessage
        }
        switch status {
        case .enabled:
            return "DebugKit will start when you log in to macOS."
        case .requiresApproval:
            return "Allow DebugKit in System Settings → Login Items."
        case .notFound:
            return installHint ?? "Could not register this app as a login item. Install to /Applications and try again."
        case .notRegistered:
            return "Start DebugKit automatically at login."
        @unknown default:
            return nil
        }
    }

    /// Whether to offer a deep-link into System Settings → Login Items.
    var shouldOfferSystemSettingsLink: Bool {
        switch status {
        case .requiresApproval, .notFound:
            return true
        case .enabled, .notRegistered:
            return lastErrorMessage != nil
        @unknown default:
            return lastErrorMessage != nil
        }
    }

    /// Bundle path for diagnostics (tests / debug logs).
    var bundlePath: String {
        Bundle.main.bundlePath
    }

    /// Hint when the running copy is unlikely to work as a Login Item.
    var installHint: String? {
        let path = bundlePath
        let inApplications = path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
        if !inApplications {
            return "Move DebugKit to /Applications (do not run from a DMG or external volume), then try again."
        }
        // Renamed side-by-side copies often confuse Launch Services / BTM for the same bundle ID.
        let name = (path as NSString).lastPathComponent
        if name.localizedCaseInsensitiveContains(".dev") || name.contains("(") {
            return "Use the standard app name in /Applications (DebugKit.app), not a renamed copy."
        }
        return "If registration fails, remove other copies of this app, reinstall from the DMG into /Applications, then try again."
    }

    // MARK: - Actions

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
