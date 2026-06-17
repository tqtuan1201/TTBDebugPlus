//
//  SaveTemplateViewModel.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Form state + validation for the "Save as Template" sheet.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class SaveTemplateViewModel {
    // MARK: - Form Fields
    var name: String = ""
    var notes: String = ""
    var tagsText: String = ""           // comma-separated free text
    var selectedProjectID: UUID?
    var prettyPrint: Bool = true

    // MARK: - Source
    private(set) var rawJSON: String
    let sourceLabel: String

    init(draft: TemplateDraft) {
        self.rawJSON = draft.json
        self.sourceLabel = draft.sourceLabel
        self.name = Self.suggestedName(from: draft.sourceLabel)
    }

    // MARK: - Validation

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasValidName: Bool { !trimmedName.isEmpty }
    var isJSONValid: Bool {
        guard let data = rawJSON.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }
    var canSave: Bool { hasValidName && !rawJSON.isEmpty }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(rawJSON.utf8.count), countStyle: .file)
    }

    var parsedTagNames: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Content to persist — optionally pretty-printed.
    func contentToSave() -> String {
        guard prettyPrint,
              let data = rawJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return rawJSON }
        return str
    }

    // MARK: - Commit

    /// Persist the template. Returns the created template, or nil on failure.
    @discardableResult
    func commit(repo: LibraryRepository, projects: [TemplateProject]) -> JSONTemplate? {
        guard canSave else { return nil }
        let project = projects.first { $0.id == selectedProjectID }
        return try? repo.createTemplate(
            name: trimmedName,
            content: contentToSave(),
            project: project,
            notes: notes,
            sourceLabel: sourceLabel,
            tagNames: parsedTagNames
        )
    }

    // MARK: - Helpers

    private static func suggestedName(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled Template" }
        return String(trimmed.prefix(80))
    }
}
