//
//  TemplateProject.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  SwiftData model — a named container that groups JSON templates.
//

import Foundation
import SwiftData

// MARK: - Template Project

/// A project groups related JSON templates (e.g. one per app, API, or feature).
/// Deleting a project cascades to all of its templates (and their versions).
@Model
final class TemplateProject {
    /// Stable identity used for export/import correlation.
    @Attribute(.unique) var id: UUID

    var name: String
    var details: String
    /// Hex color token (e.g. "#3B82F6") used for the project accent.
    var colorHex: String
    /// SF Symbol name for the project glyph.
    var icon: String
    /// Manual ordering index for the sidebar.
    var sortIndex: Int
    var isArchived: Bool

    var createdAt: Date
    var updatedAt: Date

    /// Cascade: removing a project removes its templates.
    @Relationship(deleteRule: .cascade, inverse: \JSONTemplate.project)
    var templates: [JSONTemplate] = []

    init(
        id: UUID = UUID(),
        name: String,
        details: String = "",
        colorHex: String = "#3B82F6",
        icon: String = "folder.fill",
        sortIndex: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.colorHex = colorHex
        self.icon = icon
        self.sortIndex = sortIndex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TemplateProject {
    /// Non-archived templates count (computed lazily; avoid for large fetch lists).
    var templateCount: Int { templates.count }

    func touch() { updatedAt = Date() }
}
