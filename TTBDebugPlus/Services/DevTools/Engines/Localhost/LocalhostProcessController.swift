//
//  LocalhostProcessController.swift
//  DebugKit
//
//  Soft/force process signals with protection policy.
//

import Darwin
import Foundation

enum LocalhostProcessControlError: LocalizedError, Equatable {
    case protectedProcess
    case systemProcessBlocked
    case invalidPID
    case signalFailed(errnoCode: Int32)

    var errorDescription: String? {
        switch self {
        case .protectedProcess:
            return "This process is protected (DebugKit debug bridge or the app itself)."
        case .systemProcessBlocked:
            return "System processes cannot be force-killed from DebugKit."
        case .invalidPID:
            return "Invalid process ID."
        case .signalFailed(let code):
            let message = String(cString: strerror(code))
            return "Signal failed (errno \(code)): \(message). Process may be protected by the system, or you lack permission. Copy a Terminal kill command from the detail panel if needed."
        }
    }
}

enum LocalhostProcessController {
    enum SignalKind {
        case soft  // SIGTERM
        case force // SIGKILL
    }

    static func send(
        _ kind: SignalKind,
        pid: Int32,
        classification: ProcessClass
    ) throws {
        guard pid > 0 else { throw LocalhostProcessControlError.invalidPID }

        switch classification {
        case .ttbdebug:
            throw LocalhostProcessControlError.protectedProcess
        case .system:
            if kind == .force {
                throw LocalhostProcessControlError.systemProcessBlocked
            }
            // Soft stop on system still blocked for safety.
            throw LocalhostProcessControlError.systemProcessBlocked
        case .user, .docker, .unknown:
            break
        }

        let signal: Int32 = (kind == .soft) ? SIGTERM : SIGKILL
        let result = kill(pid, signal)
        if result != 0 {
            let code = errno
            throw LocalhostProcessControlError.signalFailed(errnoCode: code)
        }
    }

    /// Best-effort terminate a Process we own (prefer process API, then signals).
    static func terminateOwned(_ process: Process, force: Bool) {
        guard process.isRunning else { return }
        if force {
            process.terminate() // SIGTERM via Foundation
            // Escalate after brief wait is caller's job; immediate SIGKILL:
            let pid = process.processIdentifier
            if pid > 0 {
                _ = kill(pid, SIGKILL)
            }
        } else {
            process.terminate()
        }
    }
}
