//
//  TemplateLibraryView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Root of the JSON Template Library — a three-pane master/detail browser
//  (scopes/projects · template list · detail) hosted inside Dev Tools.
//

import SwiftUI
import SwiftData

struct TemplateLibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppState.self) private var appState

    @Query(sort: [SortDescriptor(\TemplateProject.sortIndex), SortDescriptor(\TemplateProject.name)])
    private var projects: [TemplateProject]
    @Query(sort: [SortDescriptor(\TemplateTag.name)])
    private var tags: [TemplateTag]

    @State private var viewModel = TemplateLibraryViewModel()
    @State private var showDataManagement = false
    @State private var showNewProject = false
    @State private var projectToEdit: TemplateProject?
    @State private var projectToDelete: TemplateProject?

    var body: some View {
        VStack(spacing: 0) {
            libraryToolbar

            HSplitView {
                LibrarySidebar(
                    projects: projects,
                    scope: viewModelScopeBinding,
                    onNewProject: { showNewProject = true },
                    onEditProject: { projectToEdit = $0 },
                    onDeleteProject: { projectToDelete = $0 }
                )
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

                TemplateListView(viewModel: viewModel, tags: tags)
                    .frame(minWidth: 280, idealWidth: 360)

                TemplateDetailView(
                    template: viewModel.selectedTemplate,
                    projects: projects
                )
                .frame(minWidth: 360)
            }
        }
        .background(Color.ttBackground)
        .onAppear {
            viewModel.reload(repo: store.repository)
            store.refreshStats()
        }
        .onChange(of: store.revision) { _, _ in
            viewModel.reload(repo: store.repository)
        }
        .sheet(isPresented: $showDataManagement) {
            LibraryDataManagementView()
                .frame(minWidth: 640, minHeight: 520)
        }
        .sheet(isPresented: $showNewProject) {
            ProjectEditorSheet(project: nil)
                .frame(minWidth: 460, minHeight: 360)
        }
        .sheet(item: $projectToEdit) { project in
            ProjectEditorSheet(project: project)
                .frame(minWidth: 460, minHeight: 360)
        }
        .confirmationDialog(
            "Delete project?",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: projectToDelete
        ) { project in
            Button("Delete Project & \(project.templates.count) Template(s)", role: .destructive) {
                deleteProject(project)
            }
            Button("Cancel", role: .cancel) { projectToDelete = nil }
        } message: { project in
            Text("“\(project.name)” and all of its templates and version history will be permanently deleted. This cannot be undone.")
        }
        .alert("Library Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: - Toolbar

    private var libraryToolbar: some View {
        HStack(spacing: TTSpacing.sm) {
            HStack(spacing: TTSpacing.xs) {
                Image(systemName: AppIcon.templateLibrary)
                    .font(.ttIcon(TTIcon.lg))
                    .foregroundColor(.ttPrimary)
                Text("Template Library")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
            }

            Spacer()

            Text("\(store.stats.templateCount) templates · \(projects.count) projects")
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)

            Button(action: { showNewProject = true }) {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.ttSecondaryCompact)
            .help("Create a new project")

            Button(action: { showDataManagement = true }) {
                Image(systemName: AppIcon.storage)
                    .font(.ttIcon(TTIcon.lg))
            }
            .buttonStyle(.ttGhost)
            .help("Manage library data — backup, restore, import/export")
        }
        .padding(.horizontal, TTSpacing.lg)
        .padding(.vertical, TTSpacing.sm)
        .background(Color.ttSurface.opacity(0.2))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Bindings / Actions

    private var viewModelScopeBinding: Binding<LibraryScope> {
        Binding(
            get: { viewModel.scope },
            set: { newValue in
                viewModel.scope = newValue
                viewModel.reload(repo: store.repository)
            }
        )
    }

    private func deleteProject(_ project: TemplateProject) {
        store.perform { try $0.deleteProject(project) }
        if case .project(let id) = viewModel.scope, id == project.id {
            viewModel.scope = .all
        }
        viewModel.reload(repo: store.repository)
    }
}
