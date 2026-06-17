//
//  EditTemplateMetadataSheet.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Edit an existing template's name, project, tags, and notes.
//

import SwiftUI

struct EditTemplateMetadataSheet: View {
    let template: JSONTemplate
    let projects: [TemplateProject]

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var tagsText: String = ""
    @State private var selectedProjectID: UUID?

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var selectedProject: TemplateProject? { projects.first { $0.id == selectedProjectID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.ttBorder.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.lg) {
                    labeled("Name") {
                        TextField("Template name", text: $name)
                            .textFieldStyle(.plain)
                            .font(TTFont.bodyLarge)
                            .foregroundColor(.ttTextPrimary)
                            .padding(TTSpacing.sm)
                            .background(fieldBackground)
                    }
                    labeled("Project") { projectPicker }
                    labeled("Tags") {
                        TextField("Comma-separated tags", text: $tagsText)
                            .textFieldStyle(.plain)
                            .font(TTFont.bodyMedium)
                            .foregroundColor(.ttTextPrimary)
                            .padding(TTSpacing.sm)
                            .background(fieldBackground)
                    }
                    labeled("Notes") {
                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(TTFont.bodyMedium)
                            .foregroundColor(.ttTextPrimary)
                            .lineLimit(2...5)
                            .padding(TTSpacing.sm)
                            .background(fieldBackground)
                    }
                }
                .padding(TTSpacing.lg)
            }
        }
        .background(Color.ttBackground)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            Text("Edit Template")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextPrimary)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.ttGhost)
            Button("Save") { commit() }
                .buttonStyle(.ttPrimaryCompact)
                .disabled(!canSave)
        }
        .padding(TTSpacing.lg)
    }

    private var projectPicker: some View {
        Menu {
            ForEach(projects) { project in
                Button(action: { selectedProjectID = project.id }) {
                    Label(project.name, systemImage: selectedProjectID == project.id ? "checkmark" : project.icon)
                }
            }
        } label: {
            HStack {
                Image(systemName: selectedProject?.icon ?? "tray.full.fill")
                    .foregroundColor(Color(hex: selectedProject?.colorHex ?? "#64748B"))
                Text(selectedProject?.name ?? "—")
                    .foregroundColor(.ttTextPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.ttIcon(TTIcon.sm))
                    .foregroundColor(.ttTextTertiary)
            }
            .font(TTFont.bodyMedium)
            .padding(TTSpacing.sm)
            .background(fieldBackground)
        }
        .menuStyle(.borderlessButton)
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            Text(label.uppercased())
                .font(TTFont.sidebarHeader)
                .foregroundColor(.ttTextTertiary)
                .tracking(1.0)
            content()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: TTRadius.sm)
            .fill(Color.ttSurface.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.sm).stroke(Color.ttBorder.opacity(0.3)))
    }

    private func load() {
        name = template.name
        notes = template.notes
        tagsText = template.tags.map(\.name).joined(separator: ", ")
        selectedProjectID = template.project?.id
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagNames = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        store.perform {
            try $0.updateMetadata(template, name: trimmed, notes: notes,
                                  project: selectedProject, tagNames: tagNames)
        }
        dismiss()
    }
}
