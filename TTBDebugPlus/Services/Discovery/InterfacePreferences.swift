//
//  InterfacePreferences.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-09.
//  Persists per-interface enabled/disabled state to UserDefaults.
//

import Foundation

// MARK: - Interface Preferences

/// Stores which network interfaces the user has explicitly disabled.
/// Defaults: all interfaces enabled (empty disabled set).
final class InterfacePreferences {

    static let shared = InterfacePreferences()

    private let defaultsKey = "ttbdebug.disabledInterfaces"

    // MARK: - Private State

    private var disabledNames: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: defaultsKey)
        }
    }

    // MARK: - API

    /// Returns true if the interface with this name is enabled (default: true).
    func isEnabled(_ name: String) -> Bool {
        !disabledNames.contains(name)
    }

    /// Enable or disable a specific interface by name. Persisted immediately.
    func setEnabled(_ name: String, _ enabled: Bool) {
        var current = disabledNames
        if enabled {
            current.remove(name)
        } else {
            current.insert(name)
        }
        disabledNames = current
        print("[TTBDebug] Interface '\(name)' \(enabled ? "enabled" : "disabled")")
    }

    /// Returns all interface names the user has explicitly disabled.
    var allDisabled: Set<String> { disabledNames }

    private init() {}
}
