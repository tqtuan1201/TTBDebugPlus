//
//  InterfacePreferences.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-09.
//  Persists per-interface enabled/disabled state to UserDefaults.
//  Hardened 2026-07-10: in-memory cache + write-through.
//

import Foundation

// MARK: - Interface Preferences

/// Stores which network interfaces the user has explicitly disabled.
/// Defaults: all interfaces enabled (empty disabled set).
final class InterfacePreferences {

    static let shared = InterfacePreferences()

    private let defaultsKey = "ttbdebug.disabledInterfaces"
    private let lock = NSLock()
    private var cachedDisabled: Set<String>

    private init() {
        let arr = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        cachedDisabled = Set(arr)
    }

    // MARK: - API

    /// Returns true if the interface with this name is enabled (default: true).
    func isEnabled(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cachedDisabled.contains(name)
    }

    /// Enable or disable a specific interface by name. Persisted immediately.
    func setEnabled(_ name: String, _ enabled: Bool) {
        lock.lock()
        if enabled {
            cachedDisabled.remove(name)
        } else {
            cachedDisabled.insert(name)
        }
        let snapshot = Array(cachedDisabled)
        lock.unlock()

        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
        print("[TTBDebug] Interface '\(name)' \(enabled ? "enabled" : "disabled")")
    }

    /// Returns all interface names the user has explicitly disabled.
    var allDisabled: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return cachedDisabled
    }
}
