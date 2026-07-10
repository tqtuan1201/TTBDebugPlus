//
//  BugReport.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-28.
//  Bug report model with Markdown export — persisted as JSON in app support dir
//

import Foundation
import AppKit

// MARK: - Bug Report Model
struct BugReport: Identifiable, Codable {
    let id: UUID
    var title: String
    var severity: Severity
    var tags: Set<ReportTag>
    var reproSteps: [String]
    var expectedResult: String
    var actualResult: String
    var notes: String
    var screenshotFileNames: [String] // Filenames in app support dir
    var deviceInfo: DeviceInfoSnapshot
    var createdAt: Date
    var updatedAt: Date
    
    init(
        title: String = "",
        severity: Severity = .medium,
        tags: Set<ReportTag> = [],
        reproSteps: [String] = [""],
        expectedResult: String = "",
        actualResult: String = "",
        notes: String = "",
        screenshotFileNames: [String] = [],
        deviceInfo: DeviceInfoSnapshot = .empty
    ) {
        self.id = UUID()
        self.title = title
        self.severity = severity
        self.tags = tags
        self.reproSteps = reproSteps
        self.expectedResult = expectedResult
        self.actualResult = actualResult
        self.notes = notes
        self.screenshotFileNames = screenshotFileNames
        self.deviceInfo = deviceInfo
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Markdown Export
    func toMarkdown() -> String {
        var md = "## \(severity.emoji) \(title)\n\n"
        md += "**Severity:** \(severity.rawValue)"
        if !tags.isEmpty {
            md += " | **Tags:** \(tags.map(\.label).joined(separator: ", "))"
        }
        md += "\n"
        md += "**Device:** \(deviceInfo.deviceName) | **OS:** \(deviceInfo.osVersion)\n"
        md += "**App:** \(deviceInfo.appName) v\(deviceInfo.appVersion) | **SDK:** \(deviceInfo.sdkVersion)\n"
        md += "**Screen:** \(deviceInfo.screenResolution) | **Date:** \(formattedDate)\n\n"
        
        if reproSteps.contains(where: { !$0.isEmpty }) {
            md += "### Reproduction Steps\n"
            for (i, step) in reproSteps.enumerated() where !step.isEmpty {
                md += "\(i + 1). \(step)\n"
            }
            md += "\n"
        }
        
        if !expectedResult.isEmpty {
            md += "### Expected Result\n\(expectedResult)\n\n"
        }
        
        if !actualResult.isEmpty {
            md += "### Actual Result\n\(actualResult)\n\n"
        }
        
        if !notes.isEmpty {
            md += "### Notes\n\(notes)\n\n"
        }
        
        if !screenshotFileNames.isEmpty {
            md += "### Screenshots\n"
            md += "_\(screenshotFileNames.count) screenshot(s) attached_\n"
        }
        
        return md
    }
    
    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: createdAt)
    }

    // MARK: - Slack Export (mrkdwn)
    func toSlack() -> String {
        var s = "*\(severity.emoji) \(title.isEmpty ? "Untitled issue" : title)*\n"
        s += "Severity: \(severity.rawValue)"
        if !tags.isEmpty { s += "  |  Tags: \(tags.map(\.label).joined(separator: ", "))" }
        s += "\n"
        s += "Device: \(deviceInfo.deviceName)  |  OS: \(deviceInfo.osVersion)\n"
        s += "App: \(deviceInfo.appName) v\(deviceInfo.appVersion)  |  Screen: \(deviceInfo.screenResolution)\n"
        if reproSteps.contains(where: { !$0.isEmpty }) {
            s += "\n*Steps to reproduce:*\n"
            var n = 0
            for step in reproSteps where !step.isEmpty { n += 1; s += "\(n). \(step)\n" }
        }
        if !expectedResult.isEmpty { s += "\n*Expected:* \(expectedResult)\n" }
        if !actualResult.isEmpty { s += "*Actual:* \(actualResult)\n" }
        if !notes.isEmpty { s += "\n*Notes:* \(notes)\n" }
        if !screenshotFileNames.isEmpty { s += "\n_\(screenshotFileNames.count) screenshot(s) attached_\n" }
        return s
    }

    // MARK: - Jira Export (wiki markup)
    func toJira() -> String {
        var s = "h2. \(severity.emoji) \(title.isEmpty ? "Untitled issue" : title)\n"
        s += "*Severity:* \(severity.rawValue)"
        if !tags.isEmpty { s += " | *Tags:* \(tags.map(\.label).joined(separator: ", "))" }
        s += "\n"
        s += "*Device:* \(deviceInfo.deviceName) | *OS:* \(deviceInfo.osVersion)\n"
        s += "*App:* \(deviceInfo.appName) v\(deviceInfo.appVersion) | *SDK:* \(deviceInfo.sdkVersion)\n"
        s += "*Screen:* \(deviceInfo.screenResolution) | *Date:* \(formattedDate)\n"
        if reproSteps.contains(where: { !$0.isEmpty }) {
            s += "\nh3. Reproduction Steps\n"
            for step in reproSteps where !step.isEmpty { s += "# \(step)\n" }
        }
        if !expectedResult.isEmpty { s += "\nh3. Expected Result\n\(expectedResult)\n" }
        if !actualResult.isEmpty { s += "\nh3. Actual Result\n\(actualResult)\n" }
        if !notes.isEmpty { s += "\nh3. Notes\n\(notes)\n" }
        if !screenshotFileNames.isEmpty { s += "\n_\(screenshotFileNames.count) screenshot(s) attached_\n" }
        return s
    }
}

// MARK: - Metadata Text Format
enum MetadataFormat: String, CaseIterable {
    case plain = "Plain Text"
    case markdown = "Markdown"
    case slack = "Slack"
    case jira = "Jira"
}

// MARK: - Severity
enum Severity: String, Codable, CaseIterable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    
    var emoji: String {
        switch self {
        case .critical: return "🔴"
        case .high: return "🟠"
        case .medium: return "🟡"
        case .low: return "🟢"
        }
    }
    
    var color: String {
        switch self {
        case .critical: return "ttError"
        case .high: return "ttWarning"
        case .medium: return "ttPrimary"
        case .low: return "ttSuccess"
        }
    }
}

// MARK: - Report Tag
enum ReportTag: String, Codable, CaseIterable, Hashable {
    case bug = "Bug"
    case ui = "UI"
    case performance = "Performance"
    case crash = "Crash"
    case ux = "UX"
    case network = "Network"
    case data = "Data"
    
    var label: String { rawValue }
    
    var icon: String {
        switch self {
        case .bug: return "🐛"
        case .ui: return "📱"
        case .performance: return "⚡"
        case .crash: return "💥"
        case .ux: return "🎨"
        case .network: return "🌐"
        case .data: return "💾"
        }
    }
}

// MARK: - Device Info Snapshot
struct DeviceInfoSnapshot: Codable {
    var deviceName: String
    var osVersion: String
    var appName: String
    var appVersion: String
    var sdkVersion: String
    var screenResolution: String
    var isSimulator: Bool
    
    static let empty = DeviceInfoSnapshot(
        deviceName: "—", osVersion: "—", appName: "—",
        appVersion: "—", sdkVersion: "—", screenResolution: "—", isSimulator: false
    )

    /// Returns true when a field carries a real value (filters placeholders / blanks).
    private func isReal(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces)
        return !v.isEmpty && v != "—"
    }

    /// App label such as "MyApp v1.0.5" (omits version when unknown).
    var appLabel: String {
        guard isReal(appName) else { return isReal(appVersion) ? "v\(appVersion)" : "—" }
        return isReal(appVersion) ? "\(appName) v\(appVersion)" : appName
    }

    /// Label/value pairs for the footer banner & metadata export — only real values.
    var displayPairs: [(label: String, value: String)] {
        var pairs: [(String, String)] = []
        if isReal(deviceName)       { pairs.append(("Device", deviceName)) }
        if isReal(osVersion)        { pairs.append(("OS", osVersion)) }
        if appLabel != "—"          { pairs.append(("App", appLabel)) }
        if isReal(screenResolution) { pairs.append(("Screen", screenResolution)) }
        if isReal(sdkVersion)       { pairs.append(("SDK", sdkVersion)) }
        return pairs
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func formattedStamp(_ date: Date) -> String { Self.stampFormatter.string(from: date) }

    /// One-line / multi-line metadata text for "copy image + info" in the chosen format.
    func metadataText(format: MetadataFormat, timestamp: Date, appTitle: String = "TTBDebugPlus") -> String {
        let stamp = formattedStamp(timestamp)
        let typeBadge = isSimulator ? "Simulator" : "Real Device"
        var fields = displayPairs
        fields.append(("Type", typeBadge))
        fields.append(("Captured", stamp))

        switch format {
        case .plain:
            let body = fields.map { "\($0.label): \($0.value)" }.joined(separator: "  •  ")
            return "[\(appTitle)] \(body)"
        case .markdown:
            let body = fields.map { "**\($0.label):** \($0.value)" }.joined(separator: " | ")
            return "_Captured with \(appTitle)_\n\(body)"
        case .slack:
            let body = fields.map { "*\($0.label):* \($0.value)" }.joined(separator: "  |  ")
            return "_\(appTitle)_\n\(body)"
        case .jira:
            let body = fields.map { "*\($0.label):* \($0.value)" }.joined(separator: " | ")
            return "_\(appTitle)_\n\(body)"
        }
    }
}

// MARK: - Recording Session
struct RecordingSession {
    var frames: [RecordingFrame] = []
    var startTime: Date = Date()
    var interval: TimeInterval = 0.5
    var isActive: Bool = false
    
    var duration: TimeInterval {
        guard isActive || !frames.isEmpty else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    var frameCount: Int { frames.count }
    
    mutating func reset() {
        frames.removeAll()
        startTime = Date()
        isActive = false
    }
}

struct RecordingFrame: Identifiable {
    let id = UUID()
    let image: NSImage
    let timestamp: Date
    let index: Int
}

// MARK: - Bug Report Storage
final class BugReportStorage {
    static let shared = BugReportStorage()
    
    private let fileManager = FileManager.default
    
    var storageDirectory: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("TTBDebugPlus/BugReports")
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
        let dir = appSupport.appendingPathComponent("TTBDebugPlus/BugReports")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    var screenshotsDirectory: URL {
        let dir = storageDirectory.appendingPathComponent("screenshots")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func saveReport(_ report: BugReport) {
        let url = storageDirectory.appendingPathComponent("\(report.id.uuidString).json")
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: url)
        }
    }
    
    func loadReports() -> [BugReport] {
        guard let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(BugReport.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    func deleteReport(_ id: UUID) {
        let url = storageDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }
    
    func saveScreenshot(_ image: NSImage, fileName: String) -> String? {
        let nsImage = image
        let url = screenshotsDirectory.appendingPathComponent(fileName)
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        try? pngData.write(to: url)
        return fileName
    }
}
