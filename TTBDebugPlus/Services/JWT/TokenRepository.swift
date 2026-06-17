//
//  TokenRepository.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Data-access layer over the token vault ModelContext: CRUD plus paginated,
//  indexed search and favorites — mirroring LibraryRepository.
//

import Foundation
import SwiftData

// MARK: - Scope & Sort

enum TokenScope: Equatable {
    case all
    case favorites
    case recent
}

enum TokenSortOrder: String, CaseIterable, Identifiable {
    case recentlyUsed = "Recently Used"
    case recentlyAdded = "Recently Added"
    case name = "Name"
    case expiry = "Expiry"

    var id: String { rawValue }
}

// MARK: - Repository

@MainActor
struct TokenRepository {
    let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    // MARK: - Queries

    func count(scope: TokenScope, search: String) -> Int {
        let descriptor = FetchDescriptor<SavedToken>(predicate: predicate(scope: scope, search: search))
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func fetch(scope: TokenScope, search: String, sort: TokenSortOrder,
               limit: Int, offset: Int) -> [SavedToken] {
        var descriptor = FetchDescriptor<SavedToken>(
            predicate: predicate(scope: scope, search: search),
            sortBy: sortDescriptors(for: sort)
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return (try? context.fetch(descriptor)) ?? []
    }

    func token(with id: UUID) -> SavedToken? {
        let descriptor = FetchDescriptor<SavedToken>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// Whether a token string already exists (used to de-dupe history auto-saves).
    func existing(tokenString: String) -> SavedToken? {
        let descriptor = FetchDescriptor<SavedToken>(predicate: #Predicate { $0.token == tokenString })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Mutations

    @discardableResult
    func create(name: String, token: String, algorithm: String = "",
                notes: String = "", sourceLabel: String = "",
                expiresAt: Date? = nil, searchableExtra: String = "") throws -> SavedToken {
        let model = SavedToken(
            name: name, token: token, algorithm: algorithm, notes: notes,
            sourceLabel: sourceLabel, expiresAt: expiresAt, searchableExtra: searchableExtra
        )
        context.insert(model)
        try save()
        return model
    }

    /// Insert a token into history, or bump the existing identical one. Returns the row.
    @discardableResult
    func upsertHistory(name: String, token: String, algorithm: String,
                       sourceLabel: String, expiresAt: Date?, searchableExtra: String) throws -> SavedToken {
        if let existing = existing(tokenString: token) {
            existing.recordUse()
            existing.touch()
            try save()
            return existing
        }
        return try create(name: name, token: token, algorithm: algorithm,
                          sourceLabel: sourceLabel, expiresAt: expiresAt,
                          searchableExtra: searchableExtra)
    }

    func updateMetadata(_ token: SavedToken, name: String, notes: String) throws {
        token.name = name
        token.notes = notes
        token.touch()
        try save()
    }

    func toggleFavorite(_ token: SavedToken) throws {
        token.isFavorite.toggle()
        token.touch()
        try save()
    }

    func recordUse(_ token: SavedToken) {
        token.recordUse()
        try? save()
    }

    func delete(_ token: SavedToken) throws {
        context.delete(token)
        try save()
    }

    // MARK: - Predicate / Sort

    private func predicate(scope: TokenScope, search: String) -> Predicate<SavedToken> {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasQuery = !q.isEmpty

        switch scope {
        case .favorites:
            return #Predicate { t in t.isFavorite && (!hasQuery || t.searchText.contains(q)) }
        case .all, .recent:
            return #Predicate { t in !hasQuery || t.searchText.contains(q) }
        }
    }

    private func sortDescriptors(for sort: TokenSortOrder) -> [SortDescriptor<SavedToken>] {
        switch sort {
        case .recentlyUsed:  return [SortDescriptor(\.lastUsedAt, order: .reverse)]
        case .recentlyAdded: return [SortDescriptor(\.createdAt, order: .reverse)]
        case .name:          return [SortDescriptor(\.name, comparator: .localizedStandard)]
        case .expiry:        return [SortDescriptor(\.expiresAt, order: .forward)]
        }
    }
}
