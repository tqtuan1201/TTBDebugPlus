//
//  LibraryDataManagementView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Dedicated data-management screen for the Template Library:
//  stats, backup/restore, import/export, and destructive cleanup.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryDataManagementView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var importStrategy: ImportStrategy = .skipDuplicates
    @State private var statusMessage: String?
    @State private var showDeleteTemplatesConfirm = false
    @State private var showDeleteEverythingConfirm = false
    @State private var showRestoreConfirm = false
    @State private var pendingRestoreData: Data?

    private var libraryUTType: UTType {
        UTType(filenameExtension: LibraryBackupService.fileExtension) ?? .json
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.ttBorder.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.lg) {
                    if let statusMessage {
                        statusBanner(statusMessage)
                    }
                    statsCard
                    backupCard
                    importExportCard
                    dangerCard
                }
                .padding(TTSpacing.lg)
            }
        }
        .background(Color.ttBackground)
        .onAppear { store.refreshStats() }
        .confirmationDialog("Delete all templates?", isPresented: $showDeleteTemplatesConfirm, titleVisibility: .visible) {
            Button("Delete All Templates", role: .destructive) {
                store.deleteAllTemplates()
                statusMessage = "All templates deleted. Projects kept."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every template and its version history will be removed. Projects remain.")
        }
        .confirmationDialog("Erase the entire library?", isPresented: $showDeleteEverythingConfirm, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) {
                store.deleteEverything()
                statusMessage = "Library erased."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All projects, templates, versions, and tags will be permanently deleted. Export a backup first if unsure.")
        }
        .confirmationDialog("Restore from backup?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Replace Current Library", role: .destructive) { performRestore() }
            Button("Cancel", role: .cancel) { pendingRestoreData = nil }
        } message: {
            Text("Restoring replaces your current library with the backup's contents.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library Data Management")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                Text("Backup, restore, import/export, and cleanup")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.ttSecondaryCompact)
        }
        .padding(TTSpacing.lg)
    }

    // MARK: - Cards

    private var statsCard: some View {
        CardView(title: "OVERVIEW") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: TTSpacing.md) {
                statTile("Projects", "\(store.stats.projectCount)", "folder.fill")
                statTile("Templates", "\(store.stats.templateCount)", AppIcon.json)
                statTile("Favorites", "\(store.stats.favoriteCount)", "star.fill")
                statTile("Versions", "\(store.stats.versionCount)", "clock.arrow.circlepath")
                statTile("Tags", "\(store.stats.tagCount)", "tag.fill")
                statTile("Store Size", store.stats.formattedStoreSize, "externaldrive.fill")
            }
        }
    }

    private var backupCard: some View {
        CardView(title: "BACKUP & RESTORE") {
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                Text("Save or restore your whole library (projects, templates, versions, tags) as a single \(LibraryBackupService.fileExtension) file.")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                HStack(spacing: TTSpacing.sm) {
                    Button(action: exportFullBackup) {
                        Label("Export Backup…", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.ttSecondaryCompact)

                    Button(action: chooseRestoreFile) {
                        Label("Restore Backup…", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(.ttSecondaryCompact)
                }
            }
        }
    }

    private var importExportCard: some View {
        CardView(title: "IMPORT") {
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                Text("Merge templates from an exported file into your current library.")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)

                Picker("On conflict", selection: $importStrategy) {
                    ForEach(ImportStrategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                Text(importStrategy.detail)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextMuted)

                Button(action: chooseImportFile) {
                    Label("Import File…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.ttSecondaryCompact)
            }
        }
    }

    private var dangerCard: some View {
        CardView(title: "DANGER ZONE") {
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete all templates")
                            .font(TTFont.labelLarge).foregroundColor(.ttTextPrimary)
                        Text("Keep projects, remove every template + version.")
                            .font(TTFont.bodySmall).foregroundColor(.ttTextTertiary)
                    }
                    Spacer()
                    Button("Delete Templates", role: .destructive) { showDeleteTemplatesConfirm = true }
                        .buttonStyle(.ttOutlined)
                }
                SectionDivider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erase entire library")
                            .font(TTFont.labelLarge).foregroundColor(.ttError)
                        Text("Permanently remove everything.")
                            .font(TTFont.bodySmall).foregroundColor(.ttTextTertiary)
                    }
                    Spacer()
                    Button("Erase Everything", role: .destructive) { showDeleteEverythingConfirm = true }
                        .buttonStyle(TTOutlinedButtonStyle(color: .ttError))
                }
            }
        }
    }

    private func statTile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: TTSpacing.xxs) {
            Image(systemName: icon)
                .font(.ttIcon(TTIcon.xl))
                .foregroundColor(.ttPrimary)
            Text(value)
                .font(TTFont.heading3)
                .foregroundColor(.ttTextPrimary)
            Text(label)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TTSpacing.sm)
        .background(RoundedRectangle(cornerRadius: TTRadius.sm).fill(Color.ttSurface.opacity(0.4)))
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: TTSpacing.xs) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.ttSuccess)
            Text(message).font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
            Spacer()
            Button(action: { statusMessage = nil }) {
                Image(systemName: "xmark").font(.ttIcon(TTIcon.xs))
            }
            .buttonStyle(.ttGhost)
        }
        .padding(TTSpacing.sm)
        .background(RoundedRectangle(cornerRadius: TTRadius.sm).fill(Color.ttSuccess.opacity(0.12)))
    }

    // MARK: - File Actions

    private func exportFullBackup() {
        guard let data = try? store.backupService.exportFullLibrary() else {
            store.lastError = "Could not create backup."
            return
        }
        let panel = NSSavePanel()
        let stamp = TTDateFormatter.iso8601.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "TTBDebugPlus-Library-\(stamp).\(LibraryBackupService.fileExtension)"
        panel.allowedContentTypes = [libraryUTType]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                    statusMessage = "Backup exported."
                } catch { store.lastError = error.localizedDescription }
            }
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [libraryUTType, .json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let summary = try store.backupService.importData(data, strategy: importStrategy)
                store.didMutate()
                store.refreshStats()
                statusMessage = "Imported \(summary.templatesAdded) template(s), \(summary.projectsAdded) project(s). Skipped \(summary.skipped), replaced \(summary.replaced)."
            } catch {
                store.lastError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func chooseRestoreFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [libraryUTType, .json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                pendingRestoreData = try Data(contentsOf: url)
                showRestoreConfirm = true
            } catch {
                store.lastError = "Could not read backup: \(error.localizedDescription)"
            }
        }
    }

    private func performRestore() {
        guard let data = pendingRestoreData else { return }
        do {
            let summary = try store.backupService.restoreReplacingAll(data)
            store.didMutate()
            store.refreshStats()
            statusMessage = "Restored \(summary.templatesAdded) template(s) across \(summary.projectsAdded) project(s)."
        } catch {
            store.lastError = "Restore failed: \(error.localizedDescription)"
        }
        pendingRestoreData = nil
    }
}
