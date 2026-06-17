//
//  TemplateTag.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  SwiftData model — a user-defined label for filtering templates.
//

import Foundation
import SwiftData

// MARK: - Template Tag

/// A reusable label applied to templates for filtering (many-to-many).
@Model
final class TemplateTag {
    @Attribute(.unique) var id: UUID

    /// Lowercased, trimmed canonical name — kept unique to avoid duplicates.
    @Attribute(.unique) var name: String

    /// Hex color token for the tag chip.
    var colorHex: String

    var createdAt: Date

    /// Templates carrying this tag (inverse declared on `JSONTemplate.tags`).
    var templates: [JSONTemplate] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#64748B",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

extension TemplateTag {
    /// Normalize a free-text tag entry into a canonical name.
    static func canonicalName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
