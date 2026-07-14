//
//  LocalServerStore.swift
//  TTBDebugPlus
//
//  Persists LocalServerDefinition list under Application Support.
//

import Foundation

enum LocalServerStore {
    private static let fileName = "servers.json"
    private static let folderName = "Localhost"

    static var storageDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("TTBDebugPlus", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var fileURL: URL {
        storageDirectory.appendingPathComponent(fileName)
    }

    static func load() -> [LocalServerDefinition] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LocalServerDefinition].self, from: data)) ?? []
    }

    static func save(_ definitions: [LocalServerDefinition]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(definitions)
        try data.write(to: fileURL, options: [.atomic])
    }
}
