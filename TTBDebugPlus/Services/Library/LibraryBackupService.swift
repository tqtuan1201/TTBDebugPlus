//
//  LibraryBackupService.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Import / export / backup / restore for the Template Library.
//  Uses the Codable DTOs in LibraryDTO.swift and a versioned envelope.
//

import Foundation
import SwiftData

struct LibraryImportSummary {
    var projectsAdded = 0
    var templatesAdded = 0
    var skipped = 0
    var replaced = 0
}

@MainActor
struct LibraryBackupService {
    let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// File extension used for library bundles.
    static let fileExtension = "ttlibrary"

    // MARK: - Export

    /// Full-library backup (all projects + templates + versions + tags).
    func exportFullLibrary() throws -> Data {
        let projects = (try? context.fetch(
            FetchDescriptor<TemplateProject>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let envelope = LibraryExportEnvelope(
            exportedAt: Date(),
            projects: projects.map(ProjectDTO.init),
            looseTemplates: []
        )
        return try Self.encoder.encode(envelope)
    }

    /// Export a single project and its templates.
    func exportProject(_ project: TemplateProject) throws -> Data {
        let envelope = LibraryExportEnvelope(
            exportedAt: Date(),
            projects: [ProjectDTO(project)],
            looseTemplates: []
        )
        return try Self.encoder.encode(envelope)
    }

    /// Export a single template (carried in `looseTemplates`).
    func exportTemplate(_ template: JSONTemplate) throws -> Data {
        let envelope = LibraryExportEnvelope(
            exportedAt: Date(),
            projects: [],
            looseTemplates: [TemplateDTO(template)]
        )
        return try Self.encoder.encode(envelope)
    }

    // MARK: - Import / Restore

    /// Import an envelope using the given conflict strategy.
    @discardableResult
    func importData(_ data: Data, strategy: ImportStrategy) throws -> LibraryImportSummary {
        let envelope = try Self.decoder.decode(LibraryExportEnvelope.self, from: data)
        var summary = LibraryImportSummary()

        let repo = LibraryRepository(context)

        for projectDTO in envelope.projects {
            let project = try resolveProject(projectDTO, strategy: strategy, summary: &summary)
            guard let project else { continue }
            for templateDTO in projectDTO.templates {
                try importTemplate(templateDTO, into: project, strategy: strategy,
                                   repo: repo, summary: &summary)
            }
        }

        // Loose templates land in the default project.
        if !envelope.looseTemplates.isEmpty {
            let inbox = try repo.defaultProject()
            for templateDTO in envelope.looseTemplates {
                try importTemplate(templateDTO, into: inbox, strategy: strategy,
                                   repo: repo, summary: &summary)
            }
        }

        try context.save()
        return summary
    }

    /// Restore from a backup: wipe everything, then import. Destructive.
    @discardableResult
    func restoreReplacingAll(_ data: Data) throws -> LibraryImportSummary {
        // Validate before destroying existing data.
        let envelope = try Self.decoder.decode(LibraryExportEnvelope.self, from: data)
        try context.delete(model: TemplateVersion.self)
        try context.delete(model: JSONTemplate.self)
        try context.delete(model: TemplateTag.self)
        try context.delete(model: TemplateProject.self)
        try context.save()

        let payload = try Self.encoder.encode(envelope)
        return try importData(payload, strategy: .duplicate)
    }

    // MARK: - Helpers

    private func resolveProject(_ dto: ProjectDTO, strategy: ImportStrategy,
                               summary: inout LibraryImportSummary) throws -> TemplateProject? {
        let id = dto.id
        let existing = try context.fetch(
            FetchDescriptor<TemplateProject>(predicate: #Predicate { $0.id == id })).first

        switch strategy {
        case .skipDuplicates:
            if let existing { return existing }  // reuse, add only new templates
            return makeProject(dto, newID: false, summary: &summary)
        case .replace:
            if let existing {
                existing.name = dto.name
                existing.details = dto.details
                existing.colorHex = dto.colorHex
                existing.icon = dto.icon
                existing.isArchived = dto.isArchived
                existing.touch()
                summary.replaced += 1
                return existing
            }
            return makeProject(dto, newID: false, summary: &summary)
        case .duplicate:
            return makeProject(dto, newID: existing != nil, summary: &summary)
        }
    }

    private func makeProject(_ dto: ProjectDTO, newID: Bool,
                            summary: inout LibraryImportSummary) -> TemplateProject {
        let project = TemplateProject(
            id: newID ? UUID() : dto.id, name: dto.name, details: dto.details,
            colorHex: dto.colorHex, icon: dto.icon, sortIndex: dto.sortIndex,
            isArchived: dto.isArchived, createdAt: dto.createdAt, updatedAt: dto.updatedAt
        )
        context.insert(project)
        summary.projectsAdded += 1
        return project
    }

    private func importTemplate(_ dto: TemplateDTO, into project: TemplateProject,
                               strategy: ImportStrategy, repo: LibraryRepository,
                               summary: inout LibraryImportSummary) throws {
        let id = dto.id
        let existing = try context.fetch(
            FetchDescriptor<JSONTemplate>(predicate: #Predicate { $0.id == id })).first

        if let existing {
            switch strategy {
            case .skipDuplicates:
                summary.skipped += 1
                return
            case .replace:
                existing.name = dto.name
                existing.notes = dto.notes
                existing.content = dto.content
                existing.sourceLabel = dto.sourceLabel
                existing.isFavorite = dto.isFavorite
                existing.project = project
                existing.tags = try repo.resolveTags(dto.tags.map(\.name))
                existing.touch()
                summary.replaced += 1
                return
            case .duplicate:
                break  // fall through to create a copy with a new id
            }
        }

        let useNewID = existing != nil  // only true under .duplicate here
        let template = JSONTemplate(
            id: useNewID ? UUID() : dto.id, name: dto.name, content: dto.content,
            notes: dto.notes, sourceLabel: dto.sourceLabel, isFavorite: dto.isFavorite,
            useCount: dto.useCount, lastUsedAt: dto.lastUsedAt,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, project: project
        )
        template.tags = try repo.resolveTags(dto.tags.map(\.name))
        template.refreshSearchText()
        context.insert(template)

        for v in dto.versions.sorted(by: { $0.versionNumber < $1.versionNumber }) {
            let version = TemplateVersion(
                id: useNewID ? UUID() : v.id, versionNumber: v.versionNumber,
                content: v.content, note: v.note, createdAt: v.createdAt, template: template
            )
            context.insert(version)
        }
        summary.templatesAdded += 1
    }
}
