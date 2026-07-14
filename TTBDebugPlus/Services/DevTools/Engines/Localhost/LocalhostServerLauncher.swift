//
//  LocalhostServerLauncher.swift
//  TTBDebugPlus
//
//  Launches project servers as child processes and streams logs.
//

import Foundation

enum LocalhostServerLauncherError: LocalizedError {
    case emptyCommand
    case invalidDirectory(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Launch command is empty."
        case .invalidDirectory(let path):
            return "Working directory does not exist: \(path)"
        case .launchFailed(let message):
            return message
        }
    }
}

enum LocalhostServerLauncher {
    static let maxLogLines = 8_000

    struct LaunchHandle {
        let process: Process
        let pid: Int32
    }

    /// Launch a definition. Call `onLog` from arbitrary queues — hop to MainActor in ViewModel.
    static func launch(
        definition: LocalServerDefinition,
        onLog: @escaping @Sendable (String) -> Void,
        onTerminate: @escaping @Sendable (Int32) -> Void
    ) throws -> LaunchHandle {
        let command = definition.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw LocalhostServerLauncherError.emptyCommand }

        let dir = definition.workingDirectory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            throw LocalhostServerLauncherError.invalidDirectory(dir)
        }

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: dir, isDirectory: true)

        if definition.useLoginShell {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
        } else {
            // Split simple command; advanced users should prefer login shell.
            let components = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let exe = components.first else {
                throw LocalhostServerLauncherError.emptyCommand
            }
            process.executableURL = URL(fileURLWithPath: exe.hasPrefix("/") ? exe : "/usr/bin/env")
            if exe.hasPrefix("/") {
                process.arguments = Array(components.dropFirst())
            } else {
                process.arguments = components
            }
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in definition.env {
            environment[key] = value
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let outHandle = stdout.fileHandleForReading
        let errHandle = stderr.fileHandleForReading

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            emitLines(text, onLog: onLog)
        }
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            emitLines(text, onLog: onLog)
        }

        process.terminationHandler = { proc in
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            onTerminate(proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            throw LocalhostServerLauncherError.launchFailed(error.localizedDescription)
        }

        return LaunchHandle(process: process, pid: process.processIdentifier)
    }

    static func appendLogLine(_ line: String, to lines: inout [String], max: Int = maxLogLines) {
        lines.append(line)
        if lines.count > max {
            lines.removeFirst(lines.count - max)
        }
    }

    private static func emitLines(_ text: String, onLog: @escaping @Sendable (String) -> Void) {
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            if isLast && part.isEmpty { continue }
            let line = isLast && !text.hasSuffix("\n") ? String(part) : String(part)
            if !line.isEmpty || text.hasSuffix("\n") {
                onLog(line)
            }
        }
    }
}
