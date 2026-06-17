//
//  SavedToken.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  SwiftData model — a JWT the user saved or auto-recorded into history.
//  Only the token string + metadata are persisted; signing secrets and private
//  keys are NEVER stored.
//

import Foundation
import SwiftData

@Model
final class SavedToken {
    @Attribute(.unique) var id: UUID

    /// User-facing name. Defaults to a derived label (issuer/subject) when saved from history.
    var name: String
    var notes: String

    /// The compact JWT string. Stored externally to keep the row light.
    @Attribute(.externalStorage) var token: String

    /// Declared algorithm (e.g. "HS256"), denormalized for list display/filtering.
    var algorithm: String

    /// Where this token came from, e.g. "Decoded", "Network — GET /me", "Generated".
    var sourceLabel: String

    /// Expiration captured at save time (from `exp`), for quick "expired" badges.
    var expiresAt: Date?

    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Date

    var createdAt: Date
    var updatedAt: Date

    /// Lowercased denormalized search index (name + notes + source + algorithm + subject/issuer).
    var searchText: String

    init(
        id: UUID = UUID(),
        name: String,
        token: String,
        algorithm: String = "",
        notes: String = "",
        sourceLabel: String = "",
        expiresAt: Date? = nil,
        isFavorite: Bool = false,
        useCount: Int = 0,
        lastUsedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        searchableExtra: String = ""
    ) {
        self.id = id
        self.name = name
        self.token = token
        self.algorithm = algorithm
        self.notes = notes
        self.sourceLabel = sourceLabel
        self.expiresAt = expiresAt
        self.isFavorite = isFavorite
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.searchText = ""
        refreshSearchText(extra: searchableExtra)
    }
}

extension SavedToken {
    /// Recompute the denormalized search index. `extra` carries claim hints
    /// (issuer/subject) that aren't stored as their own columns.
    func refreshSearchText(extra: String = "") {
        searchText = [name, notes, sourceLabel, algorithm, extra]
            .joined(separator: " ")
            .lowercased()
    }

    func touch() {
        updatedAt = Date()
        refreshSearchText()
    }

    func recordUse() {
        useCount += 1
        lastUsedAt = Date()
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}
