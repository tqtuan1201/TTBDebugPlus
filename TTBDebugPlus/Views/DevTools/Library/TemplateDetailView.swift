//
//  TemplateDetailView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Right pane: full template detail — metadata, actions, and a read-only JSON
//  preview that reuses the existing OnlineJsonViewerView component.
//

import SwiftUI
import UniformTypeIdentifiers

struct TemplateDetailView: View {
    let template: JSONTemplate?
    let projects: [TemplateProject]

    @Environment(LibraryStore.self) private var store
    @Environment(AppState.self) private var appState

    @State private var showVersions = false
    @State private var showEditMetadata = false
    @State private var showDeleteConfirm = false

    var body: some View {
        if let template {
            detail(for: template)
                .id(template.id)  // reset child state when selection changes
        } else {
            placeholder
        }
    }

    // MARK: - Detail

    private func detail(for template: JSONTemplate) -> some View {
        VStack(spacing: 0) {
            header(template)
            metadataStrip(template)
            Divider().overlay(Color.ttBorder.opacity(0.2))
            OnlineJsonViewerView(
                jsonString: template.content,
                showToolbar: true,
                initialMode: "code",
                showPreviewMode: false,
                onOpenInEditor: { json in
                    store.repository.recordUse(template)
                    appState.openInJSONEditor(json: json, source: "Template — \(template.name)")
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
        .sheet(isPresented: $showVersions) {
            TemplateVersionHistoryView(template: template)
                .frame(minWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showEditMetadata) {
            EditTemplateMetadataSheet(template: template, projects: projects)
                .frame(minWidth: 460, minHeight: 420)
        }
        .confirmationDialog("Delete this template?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Template", role: .destructive) {
                store.perform { try $0.deleteTemplate(template) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(template.name)” and its \(template.versions.count) version(s) will be permanently removed.")
        }
    }

    private func header(_ template: JSONTemplate) -> some View {
        HStack(alignment: .top, spacing: TTSpacing.sm) {
            VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                Text(template.name)
                    .font(TTFont.heading2)
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(2)
                if !template.sourceLabel.isEmpty {
                    Text(template.sourceLabel)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            actionButtons(template)
        }
        .padding(.horizontal, TTSpacing.lg)
        .padding(.vertical, TTSpacing.md)
    }

    private func actionButtons(_ template: JSONTemplate) -> some View {
        HStack(spacing: TTSpacing.xxs) {
            Button(action: { store.perform { try $0.toggleFavorite(template) } }) {
                Image(systemName: template.isFavorite ? "star.fill" : "star")
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(template.isFavorite ? .ttWarning : .ttTextSecondary)
            }
            .buttonStyle(.ttGhost)
            .help(template.isFavorite ? "Remove from favorites" : "Add to favorites")

            Button(action: { showVersions = true }) {
                Image(systemName: "clock.arrow.circlepath").font(.ttIcon(TTIcon.xl))
            }
            .buttonStyle(.ttGhost)
            .help("Version history (\(template.versions.count))")

            Button(action: { showEditMetadata = true }) {
                Image(systemName: "pencil").font(.ttIcon(TTIcon.xl))
            }
            .buttonStyle(.ttGhost)
            .help("Edit name, project, tags, notes")

            Button(action: { exportTemplate(template) }) {
                Image(systemName: "square.and.arrow.up").font(.ttIcon(TTIcon.xl))
            }
            .buttonStyle(.ttGhost)
            .help("Export template…")

            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash").font(.ttIcon(TTIcon.xl))
                    .foregroundColor(.ttError)
            }
            .buttonStyle(.ttGhost)
            .help("Delete template")
        }
    }

    private func metadataStrip(_ template: JSONTemplate) -> some View {
        HStack(spacing: TTSpacing.md) {
            metaPill(icon: "folder", text: template.project?.name ?? "—")
            metaPill(icon: "arrow.down.circle", text: template.formattedSize)
            metaPill(icon: "eye", text: "\(template.useCount) uses")
            metaPill(icon: "clock", text: TTDateFormatter.relative(template.updatedAt))
            if !template.tags.isEmpty {
                ForEach(template.tags) { tag in
                    Text(tag.name)
                        .font(TTFont.badge)
                        .foregroundColor(Color(hex: tag.colorHex))
                        .padding(.horizontal, TTSpacing.xs)
                        .padding(.vertical, TTSpacing.xxxs)
                        .background(Capsule().fill(Color(hex: tag.colorHex).opacity(0.15)))
                }
            }
            Spacer()
        }
        .padding(.horizontal, TTSpacing.lg)
        .padding(.bottom, TTSpacing.sm)
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: TTSpacing.xxs) {
            Image(systemName: icon).font(.ttIcon(TTIcon.xs))
            Text(text)
        }
        .font(TTFont.labelSmall)
        .foregroundColor(.ttTextTertiary)
    }

    private var placeholder: some View {
        VStack(spacing: TTSpacing.md) {
            Spacer()
            Image(systemName: AppIcon.templateLibrary)
                .font(TTFont.lightDisplay(base: 40))
                .foregroundColor(.ttTextMuted)
            Text("Select a template")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextSecondary)
            Text("Choose a template from the list to preview and manage it.")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ttBackground)
    }

    // MARK: - Export

    private func exportTemplate(_ template: JSONTemplate) {
        guard let data = try? store.backupService.exportTemplate(template) else {
            store.lastError = "Could not encode template for export."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(template.name).\(LibraryBackupService.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: LibraryBackupService.fileExtension) ?? .json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do { try data.write(to: url) }
                catch { store.lastError = error.localizedDescription }
            }
        }
    }
}
