//
//  LibraryStore.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Observable facade injected via `.environment`, mirroring the app's existing
//  manager pattern (ConnectionManager / SessionManager / StorageManager).
//  Owns the Library ModelContainer and exposes the main-context repository.
//

import Foundation
import SwiftData
import Observation

// MARK: - Library Storage Stats

struct LibraryStats {
    var projectCount: Int = 0
    var templateCount: Int = 0
    var versionCount: Int = 0
    var tagCount: Int = 0
    var favoriteCount: Int = 0
    var storeFileSize: Int64 = 0

    var formattedStoreSize: String {
        ByteCountFormatter.string(fromByteCount: storeFileSize, countStyle: .file)
    }
}

// MARK: - Library Store

@MainActor
@Observable
final class LibraryStore {
    let container: ModelContainer

    /// Last user-facing error (surfaced by the UI via alert).
    var lastError: String?

    /// Cached stats for the data-management screen.
    var stats = LibraryStats()

    /// Bumped whenever a mutation occurs so SwiftUI views relying on manual
    /// fetches (paginated lists) know to reload.
    private(set) var revision: Int = 0

    init(container: ModelContainer = LibraryContainer.make()) {
        self.container = container
    }

    /// Repository bound to the main context (UI thread).
    var repository: LibraryRepository {
        LibraryRepository(container.mainContext)
    }

    var backupService: LibraryBackupService {
        LibraryBackupService(container.mainContext)
    }

    /// Signal that data changed (call after any mutation).
    func didMutate() {
        revision &+= 1
    }

    /// Run a repository mutation, capturing thrown errors for the UI.
    @discardableResult
    func perform<T>(_ work: (LibraryRepository) throws -> T) -> T? {
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
        let projectCount = (try? ctx.fetchCount(FetchDescriptor<TemplateProject>())) ?? 0
        let templateCount = (try? ctx.fetchCount(FetchDescriptor<JSONTemplate>())) ?? 0
        let versionCount = (try? ctx.fetchCount(FetchDescriptor<TemplateVersion>())) ?? 0
        let tagCount = (try? ctx.fetchCount(FetchDescriptor<TemplateTag>())) ?? 0
        let favoriteCount = (try? ctx.fetchCount(
            FetchDescriptor<JSONTemplate>(predicate: #Predicate { $0.isFavorite }))) ?? 0

        var size: Int64 = 0
        let url = LibraryContainer.storeURL()
        for suffix in ["", "-wal", "-shm"] {
            let p = url.path + suffix
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let bytes = attrs[.size] as? Int64 {
                size += bytes
            }
        }

        stats = LibraryStats(
            projectCount: projectCount, templateCount: templateCount,
            versionCount: versionCount, tagCount: tagCount,
            favoriteCount: favoriteCount, storeFileSize: size
        )
    }

    // MARK: - Bulk Destructive Ops (data management)

    /// Delete every template/version but keep projects.
    func deleteAllTemplates() {
        let ctx = container.mainContext
        do {
            try ctx.delete(model: TemplateVersion.self)
            try ctx.delete(model: JSONTemplate.self)
            try ctx.save()
            didMutate()
            refreshStats()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Wipe the entire library (projects, templates, versions, tags).
    func deleteEverything() {
        let ctx = container.mainContext
        do {
            try ctx.delete(model: TemplateVersion.self)
            try ctx.delete(model: JSONTemplate.self)
            try ctx.delete(model: TemplateTag.self)
            try ctx.delete(model: TemplateProject.self)
            try ctx.save()
            didMutate()
            refreshStats()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
