//
//  LibraryDTO.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Codable transfer objects for import/export/backup, plus query value types.
//

import Foundation

// MARK: - Save Draft

/// A pending request to save some JSON as a template. Set on `AppState` by any
/// JSON source (editor, network detail), consumed by the global save sheet.
struct TemplateDraft: Identifiable, Equatable {
    let id = UUID()
    var json: String
    var sourceLabel: String
}

// MARK: - Sorting & Filtering

enum TemplateSortOrder: String, CaseIterable, Identifiable {
    case recentlyUpdated = "Recently Updated"
    case recentlyUsed    = "Recently Used"
    case name            = "Name"
    case sizeDescending  = "Largest"
    case createdNewest   = "Newest"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .recentlyUpdated: return "clock.arrow.circlepath"
        case .recentlyUsed:    return "eye"
        case .name:            return "textformat"
        case .sizeDescending:  return "arrow.down.doc"
        case .createdNewest:   return "sparkles"
        }
    }
}

/// A "smart" scope in the library sidebar (independent of a specific project).
enum LibraryScope: Hashable {
    case all
    case favorites
    case recent
    case project(UUID)
}

// MARK: - Export / Backup DTOs

/// Versioned envelope so importers can detect format changes.
struct LibraryExportEnvelope: Codable {
    var format: String = "ttbdebug.library"
    var schemaVersion: Int = 1
    var exportedAt: Date
    var projects: [ProjectDTO]
    /// Templates whose project is not part of this export (e.g. single-template export).
    var looseTemplates: [TemplateDTO]
}

struct ProjectDTO: Codable {
    var id: UUID
    var name: String
    var details: String
    var colorHex: String
    var icon: String
    var sortIndex: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var templates: [TemplateDTO]
}

struct TemplateDTO: Codable {
    var id: UUID
    var name: String
    var notes: String
    var content: String
    var sourceLabel: String
    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var tags: [TagDTO]
    var versions: [VersionDTO]
}

struct TagDTO: Codable {
    var id: UUID
    var name: String
    var colorHex: String
}

struct VersionDTO: Codable {
    var id: UUID
    var versionNumber: Int
    var content: String
    var note: String
    var createdAt: Date
}

// MARK: - Import Strategy

enum ImportStrategy: String, CaseIterable, Identifiable {
    /// Skip any project/template whose id already exists.
    case skipDuplicates = "Skip Duplicates"
    /// Import everything with fresh ids (never overwrites).
    case duplicate = "Import as Copies"
    /// Replace existing records that share an id.
    case replace = "Replace Existing"

    var id: String { rawValue }
    var detail: String {
        switch self {
        case .skipDuplicates: return "Keep existing items; only add new ones."
        case .duplicate:      return "Add all items with new identifiers."
        case .replace:        return "Overwrite existing items that share an ID."
        }
    }
}

// MARK: - DTO Mapping (SwiftData ➜ DTO)

extension TagDTO {
    init(_ tag: TemplateTag) {
        self.init(id: tag.id, name: tag.name, colorHex: tag.colorHex)
    }
}

extension VersionDTO {
    init(_ v: TemplateVersion) {
        self.init(id: v.id, versionNumber: v.versionNumber, content: v.content,
                  note: v.note, createdAt: v.createdAt)
    }
}

extension TemplateDTO {
    init(_ t: JSONTemplate) {
        self.init(
            id: t.id, name: t.name, notes: t.notes, content: t.content,
            sourceLabel: t.sourceLabel, isFavorite: t.isFavorite, useCount: t.useCount,
            lastUsedAt: t.lastUsedAt, createdAt: t.createdAt, updatedAt: t.updatedAt,
            tags: t.tags.map(TagDTO.init),
            versions: t.versions
                .sorted { $0.versionNumber < $1.versionNumber }
                .map(VersionDTO.init)
        )
    }
}

extension ProjectDTO {
    init(_ p: TemplateProject) {
        self.init(
            id: p.id, name: p.name, details: p.details, colorHex: p.colorHex,
            icon: p.icon, sortIndex: p.sortIndex, isArchived: p.isArchived,
            createdAt: p.createdAt, updatedAt: p.updatedAt,
            templates: p.templates.map(TemplateDTO.init)
        )
    }
}
