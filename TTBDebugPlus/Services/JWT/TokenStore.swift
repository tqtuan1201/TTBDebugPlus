//
//  TokenStore.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Observable facade over the JWT token vault, injected via `.environment` —
//  mirrors LibraryStore. Owns the ModelContainer and exposes a main-context
//  repository. Views use manual paginated fetches (no @Query).
//

import Foundation
import SwiftData
import Observation

// MARK: - Stats

struct TokenVaultStats {
    var tokenCount: Int = 0
    var favoriteCount: Int = 0
    var storeFileSize: Int64 = 0

    var formattedStoreSize: String {
        ByteCountFormatter.string(fromByteCount: storeFileSize, countStyle: .file)
    }
}

// MARK: - Store

@MainActor
@Observable
final class TokenStore {
    let container: ModelContainer

    /// Last user-facing error (surfaced by the UI via alert).
    var lastError: String?

    /// Cached stats for the history/data-management UI.
    var stats = TokenVaultStats()

    /// Bumped on every mutation so views relying on manual fetches reload.
    private(set) var revision: Int = 0

    init(container: ModelContainer = TokenVaultContainer.make()) {
        self.container = container
    }

    var repository: TokenRepository {
        TokenRepository(container.mainContext)
    }

    func didMutate() {
        revision &+= 1
    }

    /// Run a repository mutation, capturing thrown errors for the UI.
    @discardableResult
    func perform<T>(_ work: (TokenRepository) throws -> T) -> T? {
        do {
            let result = try work(repository)
            didMutate()
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Stats

    func refreshStats() {
        let ctx = container.mainContext
        let tokenCount = (try? ctx.fetchCount(FetchDescriptor<SavedToken>())) ?? 0
        let favoriteCount = (try? ctx.fetchCount(
            FetchDescriptor<SavedToken>(predicate: #Predicate { $0.isFavorite }))) ?? 0

        var size: Int64 = 0
        let url = TokenVaultContainer.storeURL()
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let bytes = attrs[.size] as? Int64 {
                size += bytes
            }
        }
        stats = TokenVaultStats(tokenCount: tokenCount, favoriteCount: favoriteCount, storeFileSize: size)
    }

    /// Wipe the entire vault (used by data-management / clear history).
    func deleteEverything() {
        let ctx = container.mainContext
        do {
            try ctx.delete(model: SavedToken.self)
            try ctx.save()
            didMutate()
            refreshStats()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
