//
//  JSONTemplate.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  SwiftData model — a saved, named JSON payload inside a project.
//

import Foundation
import SwiftData

// MARK: - JSON Template

/// A reusable JSON payload saved by the user from any JSON they viewed.
///
/// Scale note (macOS 14): the `#Index` macro requires macOS 15, so for fast
/// search over 10k+ rows we maintain a denormalized lowercased `searchText`
/// field and query it with `#Predicate.contains`, combined with paginated
/// `FetchDescriptor` (fetchLimit/fetchOffset). See `LibraryRepository`.
@Model
final class JSONTemplate {
    @Attribute(.unique) var id: UUID

    var name: String
    var notes: String

    /// The raw JSON content. Stored as text to preserve formatting exactly.
    @Attribute(.externalStorage) var content: String

    /// Byte size of `content` (UTF-8), denormalized for cheap list display/sorting.
    var byteSize: Int

    /// Human-readable origin label, e.g. "Response — GET /users".
    var sourceLabel: String

    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Date

    var createdAt: Date
    var updatedAt: Date

    /// Lowercased, denormalized search index (name + notes + source + tag names).
    /// Maintained via `refreshSearchText()` on every mutation.
    var searchText: String

    /// Owning project (inverse of `TemplateProject.templates`).
    var project: TemplateProject?

    /// Cascade: removing a template removes its version history.
    @Relationship(deleteRule: .cascade, inverse: \TemplateVersion.template)
    var versions: [TemplateVersion] = []

    /// Many-to-many tags for filtering.
    @Relationship(inverse: \TemplateTag.templates)
    var tags: [TemplateTag] = []

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        notes: String = "",
        sourceLabel: String = "",
        isFavorite: Bool = false,
        useCount: Int = 0,
        lastUsedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        project: TemplateProject? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.notes = notes
        self.byteSize = content.utf8.count
        self.sourceLabel = sourceLabel
        self.isFavorite = isFavorite
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
        self.searchText = ""
        refreshSearchText()
    }
}

extension JSONTemplate {
    /// Recompute denormalized fields. Call after any content/metadata/tag change.
    func refreshSearchText() {
        byteSize = content.utf8.count
        let tagNames = tags.map(\.name).joined(separator: " ")
        searchText = [name, notes, sourceLabel, tagNames]
            .joined(separator: " ")
            .lowercased()
    }

    func touch() {
        updatedAt = Date()
        refreshSearchText()
    }

    /// Record that this template was opened/used (drives the Recent section).
    func recordUse() {
        useCount += 1
        lastUsedAt = Date()
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }
}
