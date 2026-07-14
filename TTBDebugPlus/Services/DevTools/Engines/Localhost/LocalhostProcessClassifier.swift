//
//  LocalhostProcessClassifier.swift
//  TTBDebugPlus
//
//  Pure classification of listening processes for safety policy.
//

import Foundation

enum LocalhostProcessClassifier {
    /// Known system / OS helpers that should not be force-killed by default.
    private static let systemProcessNames: Set<String> = [
        "ControlCenter",
        "rapportd",
        "sharingd",
        "AirPlayXPCHelper",
        "coreaudiod",
        "mDNSResponder",
        "launchd",
        "kernel_task",
        "WindowServer",
        "loginwindow",
        "SystemUIServer",
        "configd",
        "syslogd",
        "bluetoothd",
        "identityservicesd",
        "UserEventAgent",
        "cfprefsd"
    ]

    /// Minimum length before truncated-name prefix matching is allowed.
    /// Prevents short collisions (e.g. "User" matching something unintended).
    private static let truncationMatchMinLength = 6

    static func classify(
        processName: String,
        pid: Int32,
        port: Int,
        protectedPIDs: Set<Int32>,
        protectedPorts: Set<Int>
    ) -> ProcessClass {
        if protectedPIDs.contains(pid) || protectedPorts.contains(port) {
            return .ttbdebug
        }

        let lower = processName.lowercased()
        if lower.contains("docker") || lower == "com.docker.backend" || lower.contains("vpnkit") {
            return .docker
        }

        if isSystemProcessName(processName) || lower.hasPrefix("com.apple.") {
            return .system
        }

        // Low ports often owned by system services when process name is empty/unknown.
        if processName.isEmpty && port < 1024 {
            return .system
        }

        if processName.isEmpty {
            return .unknown
        }

        return .user
    }

    /// Exact match, or truncation-safe match for lsof COMMAND column without `+c 0`
    /// (e.g. "ControlCe" → ControlCenter).
    static func isSystemProcessName(_ processName: String) -> Bool {
        if processName.isEmpty { return false }
        if systemProcessNames.contains(processName) { return true }

        for sys in systemProcessNames {
            if processName == sys { return true }
            // Truncated lsof name is a prefix of the full system name.
            if processName.count >= truncationMatchMinLength
                && sys.hasPrefix(processName) {
                return true
            }
            // Full name (or longer) starts with known system name.
            if processName.hasPrefix(sys) { return true }
        }
        return false
    }

    /// Whether soft-stop is allowed.
    static func canSoftStop(_ classification: ProcessClass) -> Bool {
        switch classification {
        case .user, .docker, .unknown:
            return true
        case .system, .ttbdebug:
            return false
        }
    }

    /// Whether force-kill is allowed (system blocked; ttbdebug blocked).
    static func canForceKill(_ classification: ProcessClass) -> Bool {
        switch classification {
        case .user, .docker, .unknown:
            return true
        case .system, .ttbdebug:
            return false
        }
    }
}
