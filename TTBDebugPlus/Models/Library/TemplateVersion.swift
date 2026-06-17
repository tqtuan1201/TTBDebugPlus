//
//  TemplateVersion.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  SwiftData model — an immutable snapshot of a template's content.
//

import Foundation
import SwiftData

// MARK: - Template Version

/// A point-in-time snapshot of a `JSONTemplate`'s content, captured whenever
/// the user saves a meaningful edit. Enables version history + restore.
@Model
final class TemplateVersion {
    @Attribute(.unique) var id: UUID

    /// Monotonic version number within the owning template (1-based).
    var versionNumber: Int

    @Attribute(.externalStorage) var content: String
    var sizeBytes: Int

    /// Optional user note describing the change.
    var note: String

    var createdAt: Date

    /// Owning template (inverse of `JSONTemplate.versions`).
    var template: JSONTemplate?

    init(
        id: UUID = UUID(),
        versionNumber: Int,
        content: String,
        note: String = "",
        createdAt: Date = Date(),
        template: JSONTemplate? = nil
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.content = content
        self.sizeBytes = content.utf8.count
        self.note = note
        self.createdAt = createdAt
        self.template = template
    }
}

extension TemplateVersion {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}
