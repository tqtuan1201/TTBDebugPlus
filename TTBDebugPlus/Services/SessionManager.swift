//
//  SessionManager.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Manages debug session persistence, export/import
//  Hardened 2026-07-10: auto-bind to connection lifecycle, log caps, StorageManager path.
//

import Foundation

// MARK: - Debug Session Model
struct DebugSession: Codable, Identifiable {
    let id: String
    let deviceName: String
    let appName: String
    let startTime: Date
    var endTime: Date?
    var consoleLogs: [ConsoleLogPayload]
    var apiLogs: [APILogPayload]
    var performanceSnapshots: [PerformanceMetricsPayload]
    
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        let mins = Int(duration / 60)
        let secs = Int(duration.truncatingRemainder(dividingBy: 60))
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }
    
    var formattedDate: String {
        TTDateFormatter.dateTime.string(from: startTime)
    }
    
    var totalLogCount: Int {
        consoleLogs.count + apiLogs.count
    }
    
    init(deviceName: String, appName: String) {
        self.id = UUID().uuidString
        self.deviceName = deviceName
        self.appName = appName
        self.startTime = Date()
        self.consoleLogs = []
        self.apiLogs = []
        self.performanceSnapshots = []
    }
}

// MARK: - Session Manager
@Observable
final class SessionManager {
    
    var recentSessions: [DebugSession] = []
    var currentSession: DebugSession?
    
    private let maxRecentSessions = 20
    private let maxConsoleLogs = 8_000
    private let maxAPILogs = 4_000
    private let maxPerformanceSnapshots = 120
    private let fileManager = FileManager.default
    /// Tracks primary device for the open session (reconnect keeps same session).
    private var primaryDeviceId: String?
    
    /// Align with StorageManager: Application Support/TTBDebugPlus/Sessions
    private var sessionsDirectory: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            let fallback = fileManager.temporaryDirectory.appendingPathComponent("TTBDebugPlus/Sessions", isDirectory: true)
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
        let dir = appSupport.appendingPathComponent("TTBDebugPlus/Sessions", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    init() {
        loadRecentSessions()
        migrateLegacySessionsIfNeeded()
    }
    
    // MARK: - Session Lifecycle
    
    func startSession(deviceName: String, appName: String) {
        // Auto-save previous session
        if let current = currentSession {
            saveSession(current)
        }
        currentSession = DebugSession(deviceName: deviceName, appName: appName)
        primaryDeviceId = nil
    }

    /// Called when a device completes handshake. Reconnect / multi-device keeps the open session.
    func noteDeviceConnected(deviceId: String, deviceName: String, appName: String) {
        if currentSession == nil {
            startSession(deviceName: deviceName, appName: appName)
            primaryDeviceId = deviceId
            return
        }
        // Existing session: bind primary if unset; otherwise keep accumulating (reconnect / multi-device)
        if primaryDeviceId == nil {
            primaryDeviceId = deviceId
        }
    }
    
    func endSession() {
        guard var session = currentSession else { return }
        session.endTime = Date()
        saveSession(session)
        currentSession = nil
        primaryDeviceId = nil
    }
    
    // MARK: - Add Data (capped)
    
    func addConsoleLog(_ log: ConsoleLogPayload) {
        guard currentSession != nil else { return }
        currentSession?.consoleLogs.append(log)
        if let count = currentSession?.consoleLogs.count, count > maxConsoleLogs {
            currentSession?.consoleLogs.removeFirst(count - maxConsoleLogs)
        }
    }
    
    func addAPILog(_ log: APILogPayload) {
        guard currentSession != nil else { return }
        currentSession?.apiLogs.append(log)
        if let count = currentSession?.apiLogs.count, count > maxAPILogs {
            currentSession?.apiLogs.removeFirst(count - maxAPILogs)
        }
    }
    
    func addPerformanceSnapshot(_ snapshot: PerformanceMetricsPayload) {
        guard currentSession != nil else { return }
        currentSession?.performanceSnapshots.append(snapshot)
        if let count = currentSession?.performanceSnapshots.count, count > maxPerformanceSnapshots {
            currentSession?.performanceSnapshots.removeFirst(count - maxPerformanceSnapshots)
        }
    }

    /// Move files from legacy lowercase `sessions` folder if present.
    private func migrateLegacySessionsIfNeeded() {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacy = appSupport.appendingPathComponent("TTBDebugPlus/sessions", isDirectory: true)
        let modern = sessionsDirectory
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        guard let files = try? fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttbdebug" {
            let dest = modern.appendingPathComponent(file.lastPathComponent)
            if !fileManager.fileExists(atPath: dest.path) {
                try? fileManager.moveItem(at: file, to: dest)
            }
        }
    }
    
    // MARK: - Persistence
    
    func saveSession(_ session: DebugSession) {
        var sessionToSave = session
        if sessionToSave.endTime == nil {
            sessionToSave.endTime = Date()
        }
        
        let fileName = "\(session.id).ttbdebug"
        let fileURL = sessionsDirectory.appendingPathComponent(fileName)
        
        if let data = try? JSONEncoder().encode(sessionToSave) {
            try? data.write(to: fileURL)
            loadRecentSessions()
        }
    }
    
    func loadRecentSessions() {
        guard let files = try? fileManager.contentsOfDirectory(at: sessionsDirectory,
                                                                includingPropertiesForKeys: [.creationDateKey],
                                                                options: .skipsHiddenFiles) else { return }
        
        let sessions = files
            .filter { $0.pathExtension == "ttbdebug" }
            .compactMap { url -> DebugSession? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(DebugSession.self, from: data)
            }
            .sorted { $0.startTime > $1.startTime }
        
        recentSessions = Array(sessions.prefix(maxRecentSessions))
    }
    
    func loadSession(id: String) -> DebugSession? {
        let fileURL = sessionsDirectory.appendingPathComponent("\(id).ttbdebug")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DebugSession.self, from: data)
    }
    
    func deleteSession(id: String) {
        let fileURL = sessionsDirectory.appendingPathComponent("\(id).ttbdebug")
        try? fileManager.removeItem(at: fileURL)
        recentSessions.removeAll { $0.id == id }
    }
    
    // MARK: - Export/Import
    
    func exportSession(_ session: DebugSession, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url)
    }
    
    func importSession(from url: URL) throws -> DebugSession {
        let data = try Data(contentsOf: url)
        let session = try JSONDecoder().decode(DebugSession.self, from: data)
        saveSession(session)
        return session
    }
}
