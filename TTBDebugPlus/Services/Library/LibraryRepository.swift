//
//  LibraryRepository.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Data-access layer over the Template Library ModelContext. All persistence
//  logic (CRUD, paginated search, versioning, tags) lives here so views and
//  view models never touch SwiftData fetch internals directly.
//

import Foundation
import SwiftData

@MainActor
struct LibraryRepository {
    let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    // MARK: - Save

    /// Persist pending changes, surfacing failures to the caller.
    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    // MARK: - Projects

    func fetchProjects(includeArchived: Bool = true) -> [TemplateProject] {
        var descriptor = FetchDescriptor<TemplateProject>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]
        )
        if !includeArchived {
            descriptor.predicate = #Predicate { !$0.isArchived }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func project(with id: UUID) -> TemplateProject? {
        let descriptor = FetchDescriptor<TemplateProject>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func createProject(name: String, details: String = "", colorHex: String = "#3B82F6",
                       icon: String = "folder.fill") throws -> TemplateProject {
        let nextIndex = (fetchProjects().map(\.sortIndex).max() ?? -1) + 1
        let project = TemplateProject(name: name, details: details, colorHex: colorHex,
                                      icon: icon, sortIndex: nextIndex)
        context.insert(project)
        try save()
        return project
    }

    func updateProject(_ project: TemplateProject) throws {
        project.touch()
        try save()
    }

    func deleteProject(_ project: TemplateProject) throws {
        context.delete(project)  // cascades to templates + versions
        try save()
    }

    /// Default project used when the user saves a template without choosing one.
    @discardableResult
    func defaultProject() throws -> TemplateProject {
        if let existing = fetchProjects().first(where: { $0.name == "Inbox" }) {
            return existing
        }
        return try createProject(name: "Inbox", details: "Templates saved without a project",
                                 colorHex: "#64748B", icon: "tray.full.fill")
    }

    // MARK: - Templates (paginated, indexed search)

    /// The total number of templates matching a scope/search (for pagination UI).
    func templateCount(scope: LibraryScope, search: String, tagID: UUID? = nil) -> Int {
        if let tagID {
            return templatesForTag(tagID, scope: scope, search: search).count
        }
        let descriptor = FetchDescriptor<JSONTemplate>(predicate: predicate(scope: scope, search: search))
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Fetch one page of templates. Uses `fetchLimit`/`fetchOffset` for lazy
    /// loading so 10k+ rows never load at once.
    func fetchTemplates(scope: LibraryScope, search: String, tagID: UUID? = nil,
                        sort: TemplateSortOrder, limit: Int, offset: Int) -> [JSONTemplate] {
        // Tag filter path: bounded set, filtered + sorted + paginated in memory.
        if let tagID {
            let all = templatesForTag(tagID, scope: scope, search: search)
            let sorted = applySort(all, sort: sort)
            return Array(sorted.dropFirst(offset).prefix(limit))
        }

        var descriptor = FetchDescriptor<JSONTemplate>(
            predicate: predicate(scope: scope, search: search),
            sortBy: sortDescriptors(for: sort)
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Create / Update Templates

    @discardableResult
    func createTemplate(name: String, content: String, project: TemplateProject?,
                        notes: String = "", sourceLabel: String = "",
                        tagNames: [String] = []) throws -> JSONTemplate {
        let target = try project ?? defaultProject()
        let template = JSONTemplate(name: name, content: content, notes: notes,
                                    sourceLabel: sourceLabel, project: target)
        template.tags = try resolveTags(tagNames)
        template.refreshSearchText()
        context.insert(template)
        // Seed version 1 with the initial content.
        let v1 = TemplateVersion(versionNumber: 1, content: content, note: "Initial", template: template)
        context.insert(v1)
        target.touch()
        try save()
        return template
    }

    /// Update a template's content. If content changed, snapshot a new version.
    func updateContent(_ template: JSONTemplate, newContent: String, note: String = "") throws {
        guard newContent != template.content else { return }
        let nextVersion = (template.versions.map(\.versionNumber).max() ?? 0) + 1
        let snapshot = TemplateVersion(versionNumber: nextVersion, content: newContent,
                                       note: note, template: template)
        context.insert(snapshot)
        template.content = newContent
        template.touch()
        try save()
    }

    func updateMetadata(_ template: JSONTemplate, name: String, notes: String,
                       project: TemplateProject?, tagNames: [String]) throws {
        template.name = name
        template.notes = notes
        template.project = project
        template.tags = try resolveTags(tagNames)
        template.touch()
        try save()
    }

    func toggleFavorite(_ template: JSONTemplate) throws {
        template.isFavorite.toggle()
        template.touch()
        try save()
    }

    /// Record that the user opened the template (drives the Recent scope).
    func recordUse(_ template: JSONTemplate) {
        template.recordUse()
        try? save()
    }

    func deleteTemplate(_ template: JSONTemplate) throws {
        context.delete(template)  // cascades to versions
        try save()
    }

    func moveTemplate(_ template: JSONTemplate, to project: TemplateProject) throws {
        template.project = project
        template.touch()
        try save()
    }

    // MARK: - Versions

    func restoreVersion(_ version: TemplateVersion) throws {
        guard let template = version.template else { return }
        // Restoring is itself a content change → snapshots a new version.
        try updateContent(template, newContent: version.content,
                          note: "Restored v\(version.versionNumber)")
    }

    func deleteVersion(_ version: TemplateVersion) throws {
        context.delete(version)
        try save()
    }

    // MARK: - Tags

    func fetchTags() -> [TemplateTag] {
        let descriptor = FetchDescriptor<TemplateTag>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Resolve free-text names to existing/new tags (deduped by canonical name).
    func resolveTags(_ names: [String]) throws -> [TemplateTag] {
        var result: [TemplateTag] = []
        let existing = fetchTags()
        for raw in names {
            let canonical = TemplateTag.canonicalName(raw)
            guard !canonical.isEmpty else { continue }
            if let match = existing.first(where: { $0.name == canonical }) ?? result.first(where: { $0.name == canonical }) {
                result.append(match)
            } else {
                let tag = TemplateTag(name: canonical)
                context.insert(tag)
                result.append(tag)
            }
        }
        return result
    }

    // MARK: - Predicate / Sort Builders

    private func predicate(scope: LibraryScope, search: String) -> Predicate<JSONTemplate> {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasQuery = !q.isEmpty

        switch scope {
        case .favorites:
            return #Predicate { t in
                t.isFavorite && (!hasQuery || t.searchText.contains(q))
            }
        case .project(let pid):
            return #Predicate { t in
                (t.project?.id == pid) && (!hasQuery || t.searchText.contains(q))
            }
        case .all, .recent:
            return #Predicate { t in
                !hasQuery || t.searchText.contains(q)
            }
        }
    }

    private func sortDescriptors(for sort: TemplateSortOrder) -> [SortDescriptor<JSONTemplate>] {
        switch sort {
        case .recentlyUpdated: return [SortDescriptor(\.updatedAt, order: .reverse)]
        case .recentlyUsed:    return [SortDescriptor(\.lastUsedAt, order: .reverse)]
        case .name:            return [SortDescriptor(\.name, comparator: .localizedStandard)]
        case .sizeDescending:  return [SortDescriptor(\.byteSize, order: .reverse)]
        case .createdNewest:   return [SortDescriptor(\.createdAt, order: .reverse)]
        }
    }

    private func applySort(_ items: [JSONTemplate], sort: TemplateSortOrder) -> [JSONTemplate] {
        switch sort {
        case .recentlyUpdated: return items.sorted { $0.updatedAt > $1.updatedAt }
        case .recentlyUsed:    return items.sorted { $0.lastUsedAt > $1.lastUsedAt }
        case .name:            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .sizeDescending:  return items.sorted { $0.byteSize > $1.byteSize }
        case .createdNewest:   return items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Tag-filtered helpers (relationship-based, in memory)

    private func templatesForTag(_ tagID: UUID, scope: LibraryScope, search: String) -> [JSONTemplate] {
        let descriptor = FetchDescriptor<TemplateTag>(predicate: #Predicate { $0.id == tagID })
        guard let tag = try? context.fetch(descriptor).first else { return [] }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return tag.templates.filter { t in
            let scopeOK: Bool
            switch scope {
            case .all, .recent:      scopeOK = true
            case .favorites:         scopeOK = t.isFavorite
            case .project(let pid):  scopeOK = t.project?.id == pid
            }
            let searchOK = q.isEmpty || t.searchText.contains(q)
            return scopeOK && searchOK
        }
    }
}
