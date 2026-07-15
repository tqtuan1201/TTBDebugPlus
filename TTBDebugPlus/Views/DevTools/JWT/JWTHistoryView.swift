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
        HStack(spacing: TTSpacing.inputPaddingH) {
            Picker("", selection: $scope) {
                Text("All").tag(TokenScope.all)
                Text("Favorites").tag(TokenScope.favorites)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)

            HStack(spacing: TTSpacing.rowVertical) {
                Image(systemName: "magnifyingglass")
                    .font(TTFont.labelMedium)
                    .foregroundColor(.ttTextTertiary)
                TextField("Search name, source, algorithm…", text: $search)
                    .textFieldStyle(.plain)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextPrimary)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(TTFont.bodySmall).foregroundColor(.ttTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TTSpacing.inputPaddingH).padding(.vertical, TTSpacing.xs)
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
                .padding(.horizontal, TTSpacing.rowVertical).padding(.vertical, TTSpacing.inlineGapSmall)
                .background(Capsule().fill(Color.ttSurface.opacity(0.4)))
        }
        .padding(.horizontal, TTSpacing.chromeInsetH).padding(.vertical, TTSpacing.inputPaddingH)
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
                LazyVStack(spacing: TTSpacing.sm) {
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
                .padding(TTSpacing.chromeInsetH)
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
        HStack(spacing: TTSpacing.md) {
            Button(action: onToggleFavorite) {
                Image(systemName: token.isFavorite ? "star.fill" : "star")
                    .font(TTFont.bodyMedium)
                    .foregroundColor(token.isFavorite ? .ttWarning : .ttTextMuted)
            }
            .buttonStyle(.plain)
            .help(token.isFavorite ? "Unfavorite" : "Favorite")

            VStack(alignment: .leading, spacing: TTSpacing.inlineGapSmall) {
                HStack(spacing: TTSpacing.xs) {
                    Text(token.name.isEmpty ? "Untitled token" : token.name)
                        .font(TTFont.labelLarge).foregroundColor(.ttTextPrimary).lineLimit(1)
                    if !token.algorithm.isEmpty {
                        Text(token.algorithm)
                            .font(TTFont.badge).foregroundColor(.ttPrimaryLight)
                            .padding(.horizontal, TTSpacing.xs).padding(.vertical, TTSpacing.xxxs)
                            .background(Capsule().fill(Color.ttPrimary.opacity(0.14)))
                    }
                    if token.isExpired {
                        Text("EXPIRED")
                            .font(TTFont.badge).foregroundColor(.ttError)
                            .padding(.horizontal, TTSpacing.xs).padding(.vertical, TTSpacing.xxxs)
                            .background(Capsule().fill(Color.ttError.opacity(0.14)))
                    }
                }
                HStack(spacing: TTSpacing.sm) {
                    if !token.sourceLabel.isEmpty {
                        Text(token.sourceLabel).font(TTFont.bodySmall).foregroundColor(.ttTextTertiary).lineLimit(1)
                    }
                    Text(token.lastUsedAt, format: .relative(presentation: .named))
                        .font(TTFont.bodySmall).foregroundColor(.ttTextMuted)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: TTSpacing.xxs) {
                rowButton("arrow.up.forward.app", "Load into decoder", color: .ttPrimary, action: onLoad)
                rowButton("pencil", "Rename / notes", action: onEdit)
                rowButton("trash", "Delete", color: .ttError, action: onDelete)
            }
            .opacity(isHovered ? 1 : 0.55)
        }
        .padding(.horizontal, TTSpacing.md).padding(.vertical, TTSpacing.inputPaddingH)
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
                .font(TTFont.bodyMedium)
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
        VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
            Text("Edit Token").font(TTFont.heading2).foregroundColor(.ttTextPrimary)

            VStack(alignment: .leading, spacing: TTSpacing.xs) {
                Text("Name").font(TTFont.labelMedium).foregroundColor(.ttTextSecondary)
                TextField("Token name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.ttTextPrimary)
            }

            VStack(alignment: .leading, spacing: TTSpacing.xs) {
                Text("Notes").font(TTFont.labelMedium).foregroundColor(.ttTextSecondary)
                TextEditor(text: $notes)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextPrimary)
                    .frame(height: 90)
                    .padding(TTSpacing.xxs)
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
        .padding(TTSpacing.xl)
        .frame(width: 420)
        .background(Color.ttBackground)
    }
}
