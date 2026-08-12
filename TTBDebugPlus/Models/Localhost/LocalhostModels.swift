//
//  LocalhostModels.swift
//  DebugKit
//
//  Data models for Localhost Server Manager (Dev Tools).
//

import Foundation

// MARK: - Process classification

enum ProcessClass: String, Codable, CaseIterable, Identifiable {
    case user
    case system
    case docker
    case ttbdebug
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .user: return "User"
        case .system: return "System"
        case .docker: return "Docker"
        case .ttbdebug: return "DebugKit"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Server runtime state

enum ServerRuntimeState: String, Codable, CaseIterable {
    case unknown
    case stopped
    case starting
    case running
    case stopping
    case failed
    case conflict

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .failed: return "Failed"
        case .conflict: return "Conflict"
        }
    }
}

// MARK: - Server definition (persisted)

struct LocalServerDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var workingDirectory: String
    var launchCommand: String
    var preferredPort: Int?
    var openURLOnStart: String?
    var env: [String: String]
    /// When true, launch via `/bin/zsh -lc` so nvm/fnm PATH is available.
    var useLoginShell: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        workingDirectory: String,
        launchCommand: String,
        preferredPort: Int? = nil,
        openURLOnStart: String? = nil,
        env: [String: String] = [:],
        useLoginShell: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.launchCommand = launchCommand
        self.preferredPort = preferredPort
        self.openURLOnStart = openURLOnStart
        self.env = env
        self.useLoginShell = useLoginShell
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func blank() -> LocalServerDefinition {
        LocalServerDefinition(
            name: "",
            workingDirectory: NSHomeDirectory(),
            launchCommand: ""
        )
    }
}

// MARK: - Listening endpoint (discovered)

struct ListeningEndpoint: Identifiable, Hashable {
    /// Stable id: "pid:port" after dedupe (or "pid:port:address" pre-dedupe).
    var id: String
    /// Primary address for display / open-URL heuristics.
    var address: String
    /// All bound addresses for this pid+port (IPv4/IPv6/etc.).
    var addresses: [String]
    var port: Int
    var pid: Int32
    var processName: String
    var classification: ProcessClass

    init(
        id: String,
        address: String,
        addresses: [String]? = nil,
        port: Int,
        pid: Int32,
        processName: String,
        classification: ProcessClass
    ) {
        self.id = id
        self.address = address
        self.addresses = addresses ?? [address]
        self.port = port
        self.pid = pid
        self.processName = processName
        self.classification = classification
    }

    var displayTitle: String {
        "\(processName) :\(port)"
    }

    var addressPortLabel: String {
        if addresses.count <= 1 {
            return "\(address):\(port)"
        }
        return addresses.map { "\($0):\(port)" }.joined(separator: " · ")
    }

    var addressesLabel: String {
        addresses.joined(separator: ", ")
    }

    /// Prefer loopback IPv4 when opening a browser.
    var preferredOpenHost: String {
        if addresses.contains("127.0.0.1") { return "127.0.0.1" }
        if addresses.contains("::1") || addresses.contains("[::1]") { return "127.0.0.1" }
        if address == "*" || address == "0.0.0.0" || address == "::" { return "127.0.0.1" }
        if address.hasPrefix("[") {
            return "127.0.0.1"
        }
        return address.isEmpty ? "127.0.0.1" : address
    }
}

// MARK: - Managed runtime (in-memory UI state)

struct ManagedServerRuntime: Identifiable, Equatable {
    let id: UUID
    var state: ServerRuntimeState
    var pid: Int32?
    var logLines: [String]
    var lastError: String?
    var startedAt: Date?

    init(
        id: UUID,
        state: ServerRuntimeState = .stopped,
        pid: Int32? = nil,
        logLines: [String] = [],
        lastError: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.state = state
        self.pid = pid
        self.logLines = logLines
        self.lastError = lastError
        self.startedAt = startedAt
    }
}

// MARK: - Conflict payload

struct PortConflictInfo: Identifiable, Equatable {
    var id: String { "\(port)-\(occupant.pid)" }
    var port: Int
    var occupant: ListeningEndpoint
    var definitionID: UUID
}

// MARK: - Force kill confirmation payload

struct ForceKillRequest: Identifiable, Equatable {
    var id: String { "\(pid)-\(port)-\(definitionIDToStartAfter?.uuidString ?? "none")" }
    var pid: Int32
    var port: Int
    var processName: String
    var classification: ProcessClass
    /// When set, start this managed server after a successful force kill (conflict resolve).
    var definitionIDToStartAfter: UUID? = nil
}
