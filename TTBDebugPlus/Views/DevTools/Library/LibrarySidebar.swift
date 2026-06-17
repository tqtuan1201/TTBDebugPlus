//
//  LibrarySidebar.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Left pane of the library: smart scopes (All / Favorites / Recent) + projects.
//

import SwiftUI

struct LibrarySidebar: View {
    let projects: [TemplateProject]
    @Binding var scope: LibraryScope
    var onNewProject: () -> Void
    var onEditProject: (TemplateProject) -> Void
    var onDeleteProject: (TemplateProject) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.lg) {
                smartScopesSection
                projectsSection
            }
            .padding(.vertical, TTSpacing.md)
        }
        .background(Color.ttSurface.opacity(0.12))
    }

    // MARK: - Smart Scopes

    private var smartScopesSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xxs) {
            sectionHeader("LIBRARY")
            scopeRow(.all, label: "All Templates", icon: "tray.full")
            scopeRow(.favorites, label: "Favorites", icon: "star.fill")
            scopeRow(.recent, label: "Recent", icon: "clock.arrow.circlepath")
        }
        .padding(.horizontal, TTSpacing.sm)
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xxs) {
            HStack {
                sectionHeader("PROJECTS")
                Spacer()
                Button(action: onNewProject) {
                    Image(systemName: "plus")
                        .font(.ttIcon(TTIcon.sm))
                }
                .buttonStyle(.ttGhost)
                .help("New project")
            }

            if projects.isEmpty {
                Text("No projects yet")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .padding(.horizontal, TTSpacing.md)
                    .padding(.vertical, TTSpacing.sm)
            } else {
                ForEach(projects) { project in
                    projectRow(project)
                }
            }
        }
        .padding(.horizontal, TTSpacing.sm)
    }

    // MARK: - Rows

    private func scopeRow(_ target: LibraryScope, label: String, icon: String) -> some View {
        Button(action: { scope = target }) {
            HStack(spacing: TTSpacing.sm) {
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.lg))
                    .frame(width: 18)
                Text(label)
                Spacer()
            }
        }
        .buttonStyle(TTSidebarItemStyle(isSelected: scope == target))
    }

    private func projectRow(_ project: TemplateProject) -> some View {
        Button(action: { scope = .project(project.id) }) {
            HStack(spacing: TTSpacing.sm) {
                Image(systemName: project.icon)
                    .font(.ttIcon(TTIcon.lg))
                    .foregroundColor(Color(hex: project.colorHex))
                    .frame(width: 18)
                Text(project.name)
                    .lineLimit(1)
                Spacer()
                if project.isArchived {
                    Image(systemName: "archivebox")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(.ttTextMuted)
                }
            }
        }
        .buttonStyle(TTSidebarItemStyle(isSelected: scope == .project(project.id)))
        .contextMenu {
            Button("Edit…") { onEditProject(project) }
            Divider()
            Button("Delete Project", role: .destructive) { onDeleteProject(project) }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(TTFont.sidebarHeader)
            .foregroundColor(.ttTextTertiary)
            .tracking(1.2)
            .padding(.horizontal, TTSpacing.md)
            .padding(.top, TTSpacing.xs)
    }
}
