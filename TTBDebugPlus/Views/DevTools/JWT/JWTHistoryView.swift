//
//  JWTHistoryView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Saved-token history with indexed search, favorites, sorting, rename, and
//  load-back. Backed by the SwiftData token vault via TokenStore.
//

import SwiftUI
import SwiftData

struct JWTHistoryView: View {
    @Environment(TokenStore.self) private var store

    /// Load a token back into the decoder/verifier.
    var onLoad: (String) -> Void = { _ in }

    @State private var search = ""
    @State private var scope: TokenScope = .all
    @State private var sort: TokenSortOrder = .recentlyUsed
    @State private var editing: SavedToken?
    @State private var pendingDelete: SavedToken?

    private var rows: [SavedToken] {
        _ = store.revision  // establish observation dependency
        return store.repository.fetch(scope: scope, search: search, sort: sort, limit: 300, offset: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.ttBorder.opacity(0.3))
            content
        }
        .background(Color.ttBackground)
        .sheet(item: $editing) { token in
            JWTTokenEditSheet(token: token) { name, notes in
                store.perform { try $0.updateMetadata(token, name: name, notes: notes) }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
        .confirmationDialog(
            "Delete this token from history?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { token in
            Button("Delete", role: .destructive) {
                store.perform { try $0.delete(token) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This removes the saved token. This cannot be undone.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $scope) {
                Text("All").tag(TokenScope.all)
                Text("Favorites").tag(TokenScope.favorites)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ttTextTertiary)
                TextField("Search name, source, algorithm…", text: $search)
                    .textFieldStyle(.plain)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextPrimary)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(.ttTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: TTRadius.sm).fill(Color.ttSurface.opacity(0.4)))

            Menu {
                ForEach(TokenSortOrder.allCases) { order in
                    Button(order.rawValue) { sort = order }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(TTFont.labelSmall).foregroundColor(.ttTextSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text("\(rows.count)")
                .font(TTFont.badge).foregroundColor(.ttTextTertiary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.ttSurface.opacity(0.4)))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.ttSurface.opacity(0.08))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            JWTEmptyState(
                icon: "clock.arrow.circlepath",
                title: search.isEmpty ? "No Saved Tokens" : "No Matches",
                subtitle: search.isEmpty
                    ? "Tokens you save from the Decoder appear here, searchable and offline."
                    : "No saved tokens match “\(search)”."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { token in
                        JWTHistoryRow(
                            token: token,
                            onLoad: { onLoad(token.token) },
                            onToggleFavorite: { store.perform { try $0.toggleFavorite(token) } },
                            onEdit: { editing = token },
                            onDelete: { pendingDelete = token }
                        )
                    }
                }
                .padding(14)
            }
        }
    }
}

// MARK: - Row

struct JWTHistoryRow: View {
    let token: SavedToken
    let onLoad: () -> Void
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleFavorite) {
                Image(systemName: token.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundColor(token.isFavorite ? .ttWarning : .ttTextMuted)
            }
            .buttonStyle(.plain)
            .help(token.isFavorite ? "Unfavorite" : "Favorite")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(token.name.isEmpty ? "Untitled token" : token.name)
                        .font(TTFont.labelLarge).foregroundColor(.ttTextPrimary).lineLimit(1)
                    if !token.algorithm.isEmpty {
                        Text(token.algorithm)
                            .font(TTFont.badge).foregroundColor(.ttPrimaryLight)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.ttPrimary.opacity(0.14)))
                    }
                    if token.isExpired {
                        Text("EXPIRED")
                            .font(TTFont.badge).foregroundColor(.ttError)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.ttError.opacity(0.14)))
                    }
                }
                HStack(spacing: 8) {
                    if !token.sourceLabel.isEmpty {
                        Text(token.sourceLabel).font(TTFont.bodySmall).foregroundColor(.ttTextTertiary).lineLimit(1)
                    }
                    Text(token.lastUsedAt, format: .relative(presentation: .named))
                        .font(TTFont.bodySmall).foregroundColor(.ttTextMuted)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                rowButton("arrow.up.forward.app", "Load into decoder", color: .ttPrimary, action: onLoad)
                rowButton("pencil", "Rename / notes", action: onEdit)
                rowButton("trash", "Delete", color: .ttError, action: onDelete)
            }
            .opacity(isHovered ? 1 : 0.55)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(Color.ttSurface.opacity(isHovered ? 0.45 : 0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(Color.ttBorder.opacity(0.2), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: TTRadius.md))
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onLoad)
        .help("Double-click to load into the decoder")
    }

    private func rowButton(_ icon: String, _ help: String, color: Color = .ttTextSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: TTRadius.sm).fill(Color.ttSurface.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Edit Sheet

struct JWTTokenEditSheet: View {
    let token: SavedToken
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var notes: String

    init(token: SavedToken, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.token = token
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: token.name)
        _notes = State(initialValue: token.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Token").font(TTFont.heading2).foregroundColor(.ttTextPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(TTFont.labelMedium).foregroundColor(.ttTextSecondary)
                TextField("Token name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.ttTextPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes").font(TTFont.labelMedium).foregroundColor(.ttTextSecondary)
                TextEditor(text: $notes)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextPrimary)
                    .frame(height: 90)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: TTRadius.sm).fill(Color.ttSurface.opacity(0.4)))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(name, notes) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color.ttBackground)
    }
}
