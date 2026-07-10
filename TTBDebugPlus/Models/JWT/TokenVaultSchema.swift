//
//  TokenVaultSchema.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Versioned SwiftData schema, migration plan, and ModelContainer factory for
//  the JWT token vault. Isolated from the Template Library store and from the
//  app's file-based storage so the two never collide.
//

import Foundation
import SwiftData

// MARK: - Versioned Schema (V1)

enum TokenVaultSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SavedToken.self]
    }
}

// MARK: - Migration Plan

enum TokenVaultMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TokenVaultSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []  // V1 is the initial release.
    }
}

// MARK: - Container Factory

enum TokenVaultContainer {
    static let activeSchema = Schema(TokenVaultSchemaV1.models)

    /// Production container backed by an on-disk SQLite store. Falls back to an
    /// in-memory store so the app never crashes on launch if the file is locked.
    static func make() -> ModelContainer {
        let config = ModelConfiguration(
            "TokenVault",
            schema: activeSchema,
            url: storeURL(),
            allowsSave: true
        )
        do {
            return try ModelContainer(
                for: activeSchema,
                migrationPlan: TokenVaultMigrationPlan.self,
                configurations: config
            )
        } catch {
            #if DEBUG
            print("[TokenVaultContainer] ⚠️ On-disk store failed (\(error)). Falling back to in-memory.")
            #endif
            let memoryConfig = ModelConfiguration(
                "TokenVault-Memory",
                schema: activeSchema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: activeSchema, configurations: memoryConfig)
            } catch {
                preconditionFailure("Token Vault store failed to initialize: \(error)")
            }
        }
    }

    static func makeInMemory() -> ModelContainer {
        let config = ModelConfiguration(schema: activeSchema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: activeSchema, configurations: config)
        } catch {
            preconditionFailure("In-memory Token Vault failed: \(error)")
        }
    }

    /// `…/Application Support/TTBDebugPlus/JWT/TokenVault.store`
    static func storeURL() -> URL {
        let fm = FileManager.default
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory)
            .appendingPathComponent("TTBDebugPlus/JWT", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("TokenVault.store")
    }
}
