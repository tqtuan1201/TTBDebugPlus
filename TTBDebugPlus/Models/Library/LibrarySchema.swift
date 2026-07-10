//
//  LibrarySchema.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Versioned SwiftData schema, migration plan, and ModelContainer factory
//  for the JSON Template Library. Isolated from the app's file-based storage.
//

import Foundation
import SwiftData

// MARK: - Versioned Schema (V1)

/// First schema version of the Template Library.
/// Future schema changes add a new `VersionedSchema` + a migration stage in
/// `LibraryMigrationPlan` — existing user data migrates automatically.
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [TemplateProject.self, JSONTemplate.self, TemplateVersion.self, TemplateTag.self]
    }
}

// MARK: - Migration Plan

/// Declares the ordered list of schema versions and the stages between them.
/// V1 is the baseline; add lightweight/custom stages here as the schema evolves.
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []  // No migrations yet — V1 is the initial release.
    }
}

// MARK: - Container Factory

enum LibraryContainer {
    /// The active schema (always the latest version).
    static let activeSchema = Schema(LibrarySchemaV1.models)

    /// Build the production container backed by an on-disk SQLite store in
    /// Application Support. Falls back to an in-memory store if the on-disk
    /// store cannot be opened, so the app never crashes on launch.
    static func make() -> ModelContainer {
        let storeURL = storeURL()
        let config = ModelConfiguration(
            "TemplateLibrary",
            schema: activeSchema,
            url: storeURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(
                for: activeSchema,
                migrationPlan: LibraryMigrationPlan.self,
                configurations: config
            )
        } catch {
            #if DEBUG
            print("[LibraryContainer] ⚠️ On-disk store failed (\(error)). Falling back to in-memory.")
            #endif
            let memoryConfig = ModelConfiguration(
                "TemplateLibrary-Memory",
                schema: activeSchema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: activeSchema, configurations: memoryConfig)
            } catch {
                // Last resort: empty schema container so launch never hard-crashes App Store builds.
                preconditionFailure("Template Library store failed to initialize: \(error)")
            }
        }
    }

    /// An in-memory container for previews and tests.
    static func makeInMemory() -> ModelContainer {
        let config = ModelConfiguration(schema: activeSchema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: activeSchema, configurations: config)
        } catch {
            preconditionFailure("In-memory Template Library failed: \(error)")
        }
    }

    /// `…/Application Support/TTBDebugPlus/Library/TemplateLibrary.store`
    static func storeURL() -> URL {
        let fm = FileManager.default
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory)
            .appendingPathComponent("TTBDebugPlus/Library", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("TemplateLibrary.store")
    }
}
