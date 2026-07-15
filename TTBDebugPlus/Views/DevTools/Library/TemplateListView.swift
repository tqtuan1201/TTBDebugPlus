//
//  TemplateListView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Middle pane: search + tag/sort filters + a lazily-paginated template list.
//

import SwiftUI

struct TemplateListView: View {
    @Environment(LibraryStore.self) private var store
    @Bindable var viewModel: TemplateLibraryViewModel
    let tags: [TemplateTag]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().overlay(Color.ttBorder.opacity(0.2))
            content
        }
        .background(Color.ttBackground)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: TTSpacing.xs) {
            HStack(spacing: TTSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(.ttTextTertiary)
                TextField("Search templates…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextPrimary)
                    .onChange(of: viewModel.searchText) { _, _ in
                        viewModel.searchChanged(repo: store.repository)
                    }
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                        viewModel.reload(repo: store.repository)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ttIcon(TTIcon.md))
                            .foregroundColor(.ttTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TTSpacing.sm)
            .padding(.vertical, TTSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.sm)
                    .fill(Color.ttSurface.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.sm)
                        .stroke(Color.ttBorder.opacity(0.3)))
            )

            HStack(spacing: TTSpacing.xs) {
                sortMenu
                if !tags.isEmpty { tagMenu }
                Spacer()
                Text("\(viewModel.totalCount)")
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextTertiary)
            }
        }
        .padding(.horizontal, TTSpacing.md)
        .padding(.vertical, TTSpacing.sm)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TemplateSortOrder.allCases) { order in
                Button(action: {
                    viewModel.sortOrder = order
                    viewModel.reload(repo: store.repository)
                }) {
                    Label(order.rawValue, systemImage: order.icon)
                }
            }
        } label: {
            HStack(spacing: TTSpacing.xxs) {
                Image(systemName: "arrow.up.arrow.down")
                Text(viewModel.sortOrder.rawValue)
            }
            .font(TTFont.labelSmall)
            .foregroundColor(.ttTextSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort order")
    }

    private var tagMenu: some View {
        Menu {
            Button("All Tags") {
                viewModel.selectedTagID = nil
                viewModel.reload(repo: store.repository)
            }
            Divider()
            ForEach(tags) { tag in
                Button(action: {
                    viewModel.selectedTagID = tag.id
                    viewModel.reload(repo: store.repository)
                }) {
                    Label(tag.name, systemImage: viewModel.selectedTagID == tag.id ? "checkmark" : "tag")
                }
            }
        } label: {
            HStack(spacing: TTSpacing.xxs) {
                Image(systemName: "tag")
                Text(selectedTagName)
            }
            .font(TTFont.labelSmall)
            .foregroundColor(viewModel.selectedTagID == nil ? .ttTextSecondary : .ttPrimary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by tag")
    }

    private var selectedTagName: String {
        guard let id = viewModel.selectedTagID,
              let tag = tags.first(where: { $0.id == id }) else { return "Tags" }
        return tag.name
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.templates.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: TTSpacing.xxs) {
                    ForEach(viewModel.templates) { template in
                        TemplateRowView(
                            template: template,
                            isSelected: viewModel.selectedTemplateID == template.id
                        )
                        .onTapGesture { viewModel.selectedTemplateID = template.id }
                        .onAppear {
                            // Lazy pagination: load more as the last rows appear.
                            if template.id == viewModel.templates.last?.id {
                                viewModel.loadNextPage(repo: store.repository)
                            }
                        }
                    }

                    if viewModel.canLoadMore {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, TTSpacing.sm)
                    }
                }
                .padding(.horizontal, TTSpacing.sm)
                .padding(.vertical, TTSpacing.xs)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: TTSpacing.md) {
            Spacer()
            Image(systemName: viewModel.searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(TTFont.lightDisplay(base: 28))
                .foregroundColor(.ttTextMuted)
            Text(viewModel.searchText.isEmpty ? "No templates here yet" : "No matches")
                .font(TTFont.bodyMedium)
                .foregroundColor(.ttTextTertiary)
            Text(viewModel.searchText.isEmpty
                 ? "Save any viewed JSON as a template to see it here."
                 : "Try a different search or filter.")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
