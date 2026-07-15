//
//  TemplateVersionHistoryView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Version history sheet — browse snapshots, preview, and restore.
//

import SwiftUI

struct TemplateVersionHistoryView: View {
    let template: JSONTemplate

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVersionID: UUID?

    private var versions: [TemplateVersion] {
        template.versions.sorted { $0.versionNumber > $1.versionNumber }
    }

    private var selectedVersion: TemplateVersion? {
        versions.first { $0.id == selectedVersionID } ?? versions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.ttBorder.opacity(0.2))
            HSplitView {
                versionList.frame(minWidth: 200, idealWidth: 220)
                preview.frame(minWidth: 320)
            }
        }
        .background(Color.ttBackground)
        .onAppear { selectedVersionID = versions.first?.id }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                Text("Version History")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                Text("\(versions.count) version\(versions.count == 1 ? "" : "s") · \(template.name)")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.ttSecondaryCompact)
        }
        .padding(TTSpacing.lg)
    }

    private var versionList: some View {
        ScrollView {
            LazyVStack(spacing: TTSpacing.xxs) {
                ForEach(versions) { version in
                    versionRow(version)
                }
            }
            .padding(TTSpacing.sm)
        }
        .background(Color.ttSurface.opacity(0.12))
    }

    private func versionRow(_ version: TemplateVersion) -> some View {
        let isCurrent = version.content == template.content
        let isSelected = selectedVersion?.id == version.id
        return Button(action: { selectedVersionID = version.id }) {
            VStack(alignment: .leading, spacing: TTSpacing.inlineGapSmall) {
                HStack(spacing: TTSpacing.xs) {
                    Text("v\(version.versionNumber)")
                        .font(TTFont.labelLarge)
                        .foregroundColor(.ttTextPrimary)
                    if isCurrent {
                        Text("CURRENT")
                            .font(TTFont.badge)
                            .foregroundColor(.ttSuccess)
                            .padding(.horizontal, TTSpacing.tight).padding(.vertical, TTSpacing.hairline)
                            .background(Capsule().fill(Color.ttSuccess.opacity(0.15)))
                    }
                    Spacer()
                }
                if !version.note.isEmpty {
                    Text(version.note)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextSecondary)
                        .lineLimit(1)
                }
                Text("\(TTDateFormatter.dateTime.string(from: version.createdAt)) · \(version.formattedSize)")
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextTertiary)
            }
            .padding(.horizontal, TTSpacing.sm)
            .padding(.vertical, TTSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.sm)
                    .fill(isSelected ? Color.ttPrimary.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Restore This Version") { restore(version) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let version = selectedVersion {
            VStack(spacing: 0) {
                HStack {
                    Text("v\(version.versionNumber) preview")
                        .font(TTFont.labelMedium)
                        .foregroundColor(.ttTextSecondary)
                    Spacer()
                    if version.content != template.content {
                        Button(action: { restore(version) }) {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.ttOutlined)
                    }
                }
                .padding(TTSpacing.sm)

                OnlineJsonViewerView(jsonString: version.content, showToolbar: true,
                                     initialMode: "code", showPreviewMode: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Color.ttBackground
        }
    }

    private func restore(_ version: TemplateVersion) {
        store.perform { try $0.restoreVersion(version) }
        dismiss()
    }
}
