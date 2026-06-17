//
//  TemplateLibraryViewModel.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Drives the Template Library browser: scope, search, filtering, sorting, and
//  paginated lazy loading so 10k+ templates never load all at once.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class TemplateLibraryViewModel {
    // MARK: - Query State
    var scope: LibraryScope = .all { didSet { if scope != oldValue { needsReload = true } } }
    var searchText: String = ""
    var selectedTagID: UUID? { didSet { if selectedTagID != oldValue { needsReload = true } } }
    var sortOrder: TemplateSortOrder = .recentlyUpdated {
        didSet { if sortOrder != oldValue { needsReload = true } }
    }

    /// Currently selected template (drives the detail pane).
    var selectedTemplateID: UUID?

    // MARK: - Pagination
    private(set) var templates: [JSONTemplate] = []
    private(set) var totalCount: Int = 0
    private(set) var isLoading: Bool = false
    let pageSize: Int = 50

    private var needsReload = false
    private var searchTask: Task<Void, Never>?

    var canLoadMore: Bool { templates.count < totalCount }

    // MARK: - Search (debounced)

    /// Call from `.onChange(of: searchText)`. Debounces then reloads.
    func searchChanged(repo: LibraryRepository) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            reload(repo: repo)
        }
    }

    // MARK: - Loading

    /// Reload the first page from scratch (after any filter/scope/sort change).
    func reload(repo: LibraryRepository) {
        isLoading = true
        let effectiveSort = scope == .recent ? TemplateSortOrder.recentlyUsed : sortOrder
        totalCount = repo.templateCount(scope: scope, search: searchText, tagID: selectedTagID)
        templates = repo.fetchTemplates(
            scope: scope, search: searchText, tagID: selectedTagID,
            sort: effectiveSort, limit: pageSize, offset: 0
        )
        needsReload = false
        isLoading = false

        // Keep a valid selection.
        if let id = selectedTemplateID, !templates.contains(where: { $0.id == id }) {
            selectedTemplateID = templates.first?.id
        } else if selectedTemplateID == nil {
            selectedTemplateID = templates.first?.id
        }
    }

    /// Append the next page when the user scrolls near the end.
    func loadNextPage(repo: LibraryRepository) {
        guard !isLoading, canLoadMore else { return }
        isLoading = true
        let effectiveSort = scope == .recent ? TemplateSortOrder.recentlyUsed : sortOrder
        let next = repo.fetchTemplates(
            scope: scope, search: searchText, tagID: selectedTagID,
            sort: effectiveSort, limit: pageSize, offset: templates.count
        )
        // De-dupe defensively against concurrent mutations.
        let knownIDs = Set(templates.map(\.id))
        templates.append(contentsOf: next.filter { !knownIDs.contains($0.id) })
        isLoading = false
    }

    /// Reload if a filter changed since the last load (cheap no-op otherwise).
    func reloadIfNeeded(repo: LibraryRepository) {
        if needsReload { reload(repo: repo) }
    }

    var selectedTemplate: JSONTemplate? {
        guard let id = selectedTemplateID else { return nil }
        return templates.first { $0.id == id }
    }
}
