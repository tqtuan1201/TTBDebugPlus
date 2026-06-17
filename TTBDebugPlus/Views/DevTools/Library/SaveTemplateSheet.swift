//
//  SaveTemplateSheet.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Global "Save as Template" sheet — presented from any JSON source via
//  AppState.pendingTemplateDraft. Lets the user name, file, tag, and save JSON.
//

import SwiftUI
import SwiftData

struct SaveTemplateSheet: View {
    let draft: TemplateDraft

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\TemplateProject.sortIndex), SortDescriptor(\TemplateProject.name)])
    private var projects: [TemplateProject]

    @State private var viewModel: SaveTemplateViewModel

    init(draft: TemplateDraft) {
        self.draft = draft
        _viewModel = State(initialValue: SaveTemplateViewModel(draft: draft))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.ttBorder.opacity(0.2))
            form
        }
        .frame(minWidth: 480, minHeight: 440)
        .background(Color.ttBackground)
        .onAppear(perform: ensureDefaultProjectSelection)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Save as Template")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                Text("\(viewModel.formattedSize) · \(viewModel.isJSONValid ? "Valid JSON" : "Not valid JSON")")
                    .font(TTFont.bodySmall)
                    .foregroundColor(viewModel.isJSONValid ? .ttTextTertiary : .ttWarning)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.ttGhost)
            Button("Save") { commit() }
                .buttonStyle(.ttPrimaryCompact)
                .disabled(!viewModel.canSave)
        }
        .padding(TTSpacing.lg)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.lg) {
                labeled("Name") {
                    TextField("Template name", text: $viewModel.name)
                        .textFieldStyle(.plain)
                        .font(TTFont.bodyLarge)
                        .foregroundColor(.ttTextPrimary)
                        .padding(TTSpacing.sm)
                        .background(fieldBackground)
                }

                labeled("Project") { projectPicker }

                labeled("Tags") {
                    TextField("Comma-separated, e.g. api, users, prod", text: $viewModel.tagsText)
                        .textFieldStyle(.plain)
                        .font(TTFont.bodyMedium)
                        .foregroundColor(.ttTextPrimary)
                        .padding(TTSpacing.sm)
                        .background(fieldBackground)
                }

                labeled("Notes") {
                    TextField("Optional notes", text: $viewModel.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(TTFont.bodyMedium)
                        .foregroundColor(.ttTextPrimary)
                        .lineLimit(2...5)
                        .padding(TTSpacing.sm)
                        .background(fieldBackground)
                }

                Toggle("Pretty-print before saving", isOn: $viewModel.prettyPrint)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextSecondary)
                    .disabled(!viewModel.isJSONValid)
            }
            .padding(TTSpacing.lg)
        }
    }

    private var projectPicker: some View {
        Menu {
            ForEach(projects) { project in
                Button(action: { viewModel.selectedProjectID = project.id }) {
                    Label(project.name, systemImage: viewModel.selectedProjectID == project.id ? "checkmark" : project.icon)
                }
            }
            Divider()
            Button("New Project…") { createInlineProject() }
        } label: {
            HStack {
                Image(systemName: selectedProject?.icon ?? "tray.full.fill")
                    .foregroundColor(Color(hex: selectedProject?.colorHex ?? "#64748B"))
                Text(selectedProject?.name ?? "Inbox (default)")
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

    private var selectedProject: TemplateProject? {
        projects.first { $0.id == viewModel.selectedProjectID }
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

    // MARK: - Actions

    private func ensureDefaultProjectSelection() {
        if viewModel.selectedProjectID == nil {
            viewModel.selectedProjectID = projects.first?.id
        }
    }

    private func createInlineProject() {
        if let project = store.perform({ try $0.createProject(name: "New Project") }) {
            viewModel.selectedProjectID = project.id
        }
    }

    private func commit() {
        guard viewModel.commit(repo: store.repository, projects: projects) != nil else {
            store.lastError = "Could not save template."
            return
        }
        store.didMutate()   // refresh any open library list/stats
        dismiss()
    }
}
