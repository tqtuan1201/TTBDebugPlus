//
//  ProjectEditorSheet.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Create or edit a project (name, description, color, icon, archived).
//

import SwiftUI

struct ProjectEditorSheet: View {
    /// nil → create mode; non-nil → edit mode.
    let project: TemplateProject?

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var details: String = ""
    @State private var colorHex: String = "#3B82F6"
    @State private var icon: String = "folder.fill"
    @State private var isArchived: Bool = false

    private let palette = ["#3B82F6", "#22C55E", "#F59E0B", "#EF4444", "#A855F7",
                           "#EC4899", "#14B8A6", "#06B6D4", "#84CC16", "#64748B"]
    private let icons = ["folder.fill", "tray.full.fill", "shippingbox.fill", "cube.fill",
                         "server.rack", "globe", "ladybug.fill", "star.fill", "bolt.fill", "doc.text.fill"]

    private var isEditing: Bool { project != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.ttBorder.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.lg) {
                    field("Name") {
                        TextField("Project name", text: $name)
                            .textFieldStyle(.plain)
                            .font(TTFont.bodyLarge)
                            .foregroundColor(.ttTextPrimary)
                            .padding(TTSpacing.sm)
                            .background(fieldBackground)
                    }
                    field("Description") {
                        TextField("Optional description", text: $details, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(TTFont.bodyMedium)
                            .foregroundColor(.ttTextPrimary)
                            .lineLimit(2...4)
                            .padding(TTSpacing.sm)
                            .background(fieldBackground)
                    }
                    field("Color") { colorPicker }
                    field("Icon") { iconPicker }
                    if isEditing {
                        Toggle("Archived", isOn: $isArchived)
                            .font(TTFont.bodyMedium)
                            .foregroundColor(.ttTextSecondary)
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
            Text(isEditing ? "Edit Project" : "New Project")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextPrimary)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.ttGhost)
            Button(isEditing ? "Save" : "Create") { commit() }
                .buttonStyle(.ttPrimaryCompact)
                .disabled(!canSave)
        }
        .padding(TTSpacing.lg)
    }

    private var colorPicker: some View {
        HStack(spacing: TTSpacing.sm) {
            ForEach(palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white, lineWidth: colorHex == hex ? 2 : 0))
                    .onTapGesture { colorHex = hex }
            }
        }
    }

    private var iconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TTSpacing.sm) {
                ForEach(icons, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.ttIcon(TTIcon.xl))
                        .foregroundColor(icon == symbol ? .white : .ttTextSecondary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .fill(icon == symbol ? Color(hex: colorHex) : Color.ttSurface.opacity(0.5))
                        )
                        .onTapGesture { icon = symbol }
                }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
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
        guard let project else { return }
        name = project.name
        details = project.details
        colorHex = project.colorHex
        icon = project.icon
        isArchived = project.isArchived
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let project {
            project.name = trimmed
            project.details = details
            project.colorHex = colorHex
            project.icon = icon
            project.isArchived = isArchived
            store.perform { try $0.updateProject(project) }
        } else {
            store.perform { try $0.createProject(name: trimmed, details: details, colorHex: colorHex, icon: icon) }
        }
        dismiss()
    }
}
