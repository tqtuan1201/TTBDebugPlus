//
//  JSONDiffView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Side-by-side JSON diff with color-coded markers
//

import SwiftUI

struct JSONDiffView: View {
    var initialLeft: String = ""
    @State private var leftJSON: String = ""
    @State private var rightJSON: String = ""
    @State private var diffResult: DiffResult?
    @State private var isComputing: Bool = false
    @State private var currentDiffIndex: Int = 0
    @State private var hoveredSide: DiffSide? = nil

    private enum DefaultsKey {
        static let leftJSON = "devTools.jsonDiff.leftJSON"
        static let rightJSON = "devTools.jsonDiff.rightJSON"
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                diffHeader
                
                Divider().background(Color.ttBorder.opacity(0.3))
                
                // Input panes — proportional height (40% of available, min 180)
                let inputHeight = max(180, geometry.size.height * 0.35)
                
                HSplitView {
                    // Left pane
                    diffInputPane(title: "LEFT — Original", text: $leftJSON, side: .left)
                        .frame(minWidth: 280, maxWidth: .infinity)
                    
                    // Right pane
                    diffInputPane(title: "RIGHT — Modified", text: $rightJSON, side: .right)
                        .frame(minWidth: 280, maxWidth: .infinity)
                }
                .frame(minHeight: 160, idealHeight: inputHeight, maxHeight: .infinity)
                
                // Separator with drag hint
                HStack(spacing: TTSpacing.xs) {
                    Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1)
                    Text("DIFF RESULTS")
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextMuted)
                        .tracking(1.5)
                    Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1)
                }
                .padding(.horizontal, TTSpacing.lg)
                .padding(.vertical, TTSpacing.xs)
                .background(Color.ttSurface.opacity(0.15))
                
                // Diff results — fills remaining space
                diffResultsView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            restoreState()
            if !initialLeft.isEmpty {
                leftJSON = initialLeft
            }
            saveState()
            if !leftJSON.isEmpty && !rightJSON.isEmpty {
                executeDiff()
            }
        }
        .onChange(of: leftJSON) { _, _ in
            saveState()
        }
        .onChange(of: rightJSON) { _, _ in
            saveState()
        }
        .onChange(of: initialLeft) { _, newValue in
            guard !newValue.isEmpty else { return }
            leftJSON = newValue
        }
    }
    
    // MARK: - Header
    private var diffHeader: some View {
        HStack(spacing: TTSpacing.md) {
            // Icon with glow
            ZStack {
                Circle()
                    .fill(Color.ttPrimary.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: AppIcon.jsonDiff)
                    .font(.ttIcon(TTIcon.lg))
                    .foregroundColor(.ttPrimary)
            }
            
            Text("JSON Compare")
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextPrimary)
            
            Spacer()
            
            if let result = diffResult {
                // Stats badges
                HStack(spacing: TTSpacing.inputPaddingH) {
                    statBadge(count: result.stats.added, label: "Added", color: .ttSuccess, icon: "plus.circle.fill")
                    statBadge(count: result.stats.removed, label: "Removed", color: .ttError, icon: "minus.circle.fill")
                    statBadge(count: result.stats.changed, label: "Changed", color: .ttWarning, icon: "arrow.triangle.2.circlepath")
                }
                
                Divider().frame(height: 16)
                
                // Navigate diffs
                if result.stats.hasChanges {
                    HStack(spacing: TTSpacing.xxs) {
                        Button(action: { navigateDiff(-1) }) {
                            Image(systemName: "chevron.up")
                                .font(.ttIcon(TTIcon.sm))
                        }
                        .buttonStyle(.ttGhost)
                        
                        Text("\(currentDiffIndex + 1)/\(result.stats.total)")
                            .font(TTFont.badge)
                            .foregroundColor(.ttTextTertiary)
                            .monospacedDigit()
                        
                        Button(action: { navigateDiff(1) }) {
                            Image(systemName: "chevron.down")
                                .font(.ttIcon(TTIcon.sm))
                        }
                        .buttonStyle(.ttGhost)
                    }
                }
            }
            
            // Compare button
            Button(action: executeDiff) {
                HStack(spacing: TTSpacing.tight) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.ttIcon(TTIcon.md))
                    Text("Compare")
                        .font(TTFont.labelMedium)
                }
            }
            .buttonStyle(.ttPrimaryCompact)
            .disabled(leftJSON.isEmpty || rightJSON.isEmpty)
        }
        .padding(.horizontal, TTSpacing.chromeInsetH)
        .padding(.vertical, TTSpacing.inputPaddingH)
        .background(Color.ttSurface.opacity(0.15))
    }
    
    private func statBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: TTSpacing.xxs) {
            Image(systemName: icon)
                .font(.ttIcon(TTIcon.xs))
                .foregroundColor(color)
            Text("\(count)")
                .font(TTFont.badge)
                .foregroundColor(color)
            Text(label)
                .font(TTFont.badge)
                .foregroundColor(.ttTextTertiary)
        }
        .padding(.horizontal, TTSpacing.sm)
        .padding(.vertical, TTSpacing.inlineGapSmall)
        .background(
            Capsule()
                .fill(color.opacity(0.08))
        )
    }
    
    // MARK: - Input Panes
    private func diffInputPane(title: String, text: Binding<String>, side: DiffSide) -> some View {
        VStack(spacing: 0) {
            // Pane header
            HStack(spacing: TTSpacing.sm) {
                // Side indicator dot
                Circle()
                    .fill(side == .left ? Color.ttError.opacity(0.6) : Color.ttSuccess.opacity(0.6))
                    .frame(width: 6, height: 6)
                
                Text(title)
                    .font(TTFont.badge)
                    .foregroundColor(.ttTextSecondary)
                    .tracking(0.6)
                
                Spacer()
                
                // Character count
                if !text.wrappedValue.isEmpty {
                    Text("\(text.wrappedValue.count) chars")
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextMuted)
                }
                
                // Action buttons
                HStack(spacing: TTSpacing.xxxs) {
                    Button(action: {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            text.wrappedValue = str
                        }
                    }) {
                        HStack(spacing: TTSpacing.inlineGapSmall) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.ttIcon(TTIcon.xs))
                            Text("Paste")
                                .font(TTFont.badge)
                        }
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, TTSpacing.xs)
                        .padding(.vertical, TTSpacing.inlineGapSmall)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.ttSurface.opacity(hoveredSide == side ? 0.6 : 0))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    if !text.wrappedValue.isEmpty {
                        Button(action: { text.wrappedValue = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, TTSpacing.md)
            .padding(.vertical, TTSpacing.rowVertical)
            .background(Color.ttSurface.opacity(0.25))
            .overlay(
                Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1),
                alignment: .bottom
            )
            
            // Text input — fills all remaining space
            TextEditor(text: text)
                .font(TTFont.codeMedium)
                .scrollContentBackground(.hidden)
                .foregroundColor(.ttTextPrimary)
                .background(Color.ttBackground.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    // Placeholder
                    Group {
                        if text.wrappedValue.isEmpty {
                            VStack(spacing: TTSpacing.xs) {
                                Image(systemName: side == .left ? "doc.text" : "doc.text.fill")
                                    .font(TTFont.heading2)
                                    .foregroundColor(.ttTextMuted.opacity(0.5))
                                Text("Paste JSON here")
                                    .font(TTFont.labelMedium)
                                    .foregroundColor(.ttTextMuted.opacity(0.5))
                            }
                        }
                    }
                )
        }
        .onHover { isHovered in
            hoveredSide = isHovered ? side : nil
        }
        .overlay(
            // Left border for right pane
            Group {
                if side == .right {
                    Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(width: 1)
                }
            },
            alignment: .leading
        )
    }
    
    enum DiffSide { case left, right }
    
    // MARK: - Results
    @ViewBuilder
    private var diffResultsView: some View {
        if isComputing {
            VStack(spacing: TTSpacing.inputPaddingH) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.ttPrimary)
                Text("Computing structural diff...")
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = diffResult {
            if !result.stats.hasChanges && result.error == nil {
                VStack(spacing: TTSpacing.inputPaddingH) {
                    ZStack {
                        Circle()
                            .fill(Color.ttSuccess.opacity(0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: "checkmark.circle.fill")
                            .font(TTFont.displayMedium)
                            .foregroundColor(.ttSuccess)
                    }
                    Text("Identical")
                        .font(TTFont.heading3)
                        .foregroundColor(.ttSuccess)
                    Text("No differences found between left and right JSON")
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = result.error {
                VStack(spacing: TTSpacing.inputPaddingH) {
                    ZStack {
                        Circle()
                            .fill(Color.ttWarning.opacity(0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(TTFont.displayMedium)
                            .foregroundColor(.ttWarning)
                    }
                    Text("Parse Error")
                        .font(TTFont.heading3)
                        .foregroundColor(.ttWarning)
                    Text(error)
                        .font(TTFont.codeSmall)
                        .foregroundColor(.ttTextSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                diffNodesList(result.nodes)
            }
        } else {
            VStack(spacing: TTSpacing.chromeInsetH) {
                ZStack {
                    Circle()
                        .fill(Color.ttSurface.opacity(0.5))
                        .frame(width: 56, height: 56)
                    Image(systemName: AppIcon.jsonDiff)
                        .font(TTFont.heading1)
                        .foregroundColor(.ttTextMuted)
                }
                Text("Ready to Compare")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextSecondary)
                Text("Paste JSON on both sides and click Compare")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                
                // Keyboard shortcut hint
                HStack(spacing: TTSpacing.xxs) {
                    KeyboardShortcutBadge(key: "⌘")
                    KeyboardShortcutBadge(key: "V")
                    Text("to paste")
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func diffNodesList(_ nodes: [DiffNode]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let changedNodes = nodes.filter { node in
                    switch node.type {
                    case .unchanged: return false
                    default: return true
                    }
                }
                
                ForEach(changedNodes) { node in
                    HStack(spacing: 0) {
                        // Indent guides
                        ForEach(0..<node.indent, id: \.self) { level in
                            Rectangle()
                                .fill(Color.ttBorder.opacity(0.08))
                                .frame(width: 1)
                                .padding(.leading, TTSpacing.md)
                                .padding(.trailing, TTSpacing.xxs)
                        }
                        
                        // Type icon
                        Image(systemName: node.type.icon)
                            .font(.ttIcon(TTIcon.sm))
                            .foregroundColor(node.type.color)
                            .frame(width: 20)
                        
                        // Path — proportional width
                        Text(node.path)
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 120, maxWidth: 300, alignment: .leading)
                        
                        Spacer().frame(width: 8)
                        
                        // Values
                        switch node.type {
                        case .added:
                            HStack(spacing: TTSpacing.xxs) {
                                Text("+")
                                    .font(TTFont.badge)
                                    .foregroundColor(.ttSuccess)
                                Text(node.rightValue ?? "")
                                    .font(TTFont.codeMedium)
                                    .foregroundColor(.ttSuccess)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        case .removed:
                            HStack(spacing: TTSpacing.xxs) {
                                Text("−")
                                    .font(TTFont.badge)
                                    .foregroundColor(.ttError)
                                Text(node.leftValue ?? "")
                                    .font(TTFont.codeMedium)
                                    .foregroundColor(.ttError)
                                    .strikethrough()
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        case .changed(let old, let new):
                            HStack(spacing: TTSpacing.xs) {
                                Text(old)
                                    .font(TTFont.codeMedium)
                                    .foregroundColor(.ttError)
                                    .strikethrough()
                                    .lineLimit(2)
                                Image(systemName: "arrow.right")
                                    .font(.ttIcon(TTIcon.xxs))
                                    .foregroundColor(.ttWarning)
                                Text(new)
                                    .font(TTFont.codeMedium)
                                    .foregroundColor(.ttSuccess)
                                    .lineLimit(2)
                            }
                            .textSelection(.enabled)
                        case .unchanged:
                            EmptyView()
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, TTSpacing.chromeInsetH)
                    .padding(.vertical, TTSpacing.rowVertical)
                    .background(diffRowBackground(node.type))
                    .overlay(
                        Rectangle().fill(Color.ttBorder.opacity(0.06)).frame(height: 1),
                        alignment: .bottom
                    )
                }
            }
        }
    }
    
    private func diffRowBackground(_ type: DiffNodeType) -> Color {
        switch type {
        case .added: return Color.ttSuccess.opacity(0.04)
        case .removed: return Color.ttError.opacity(0.04)
        case .changed: return Color.ttWarning.opacity(0.04)
        case .unchanged: return Color.clear
        }
    }
    
    // MARK: - Actions
    
    private func executeDiff() {
        isComputing = true
        currentDiffIndex = 0
        
        let left = leftJSON
        let right = rightJSON
        Task.detached(priority: .userInitiated) {
            let result = JSONDiffEngine.diff(left: left, right: right)
            await MainActor.run {
                diffResult = result
                isComputing = false
            }
        }
    }
    
    private func navigateDiff(_ direction: Int) {
        guard let result = diffResult else { return }
        let total = result.stats.total
        guard total > 0 else { return }
        currentDiffIndex = (currentDiffIndex + direction + total) % total
    }

    private func restoreState() {
        leftJSON = UserDefaults.standard.string(forKey: DefaultsKey.leftJSON) ?? ""
        rightJSON = UserDefaults.standard.string(forKey: DefaultsKey.rightJSON) ?? ""
    }

    private func saveState() {
        UserDefaults.standard.set(leftJSON, forKey: DefaultsKey.leftJSON)
        UserDefaults.standard.set(rightJSON, forKey: DefaultsKey.rightJSON)
    }
}

// MARK: - Keyboard Shortcut Badge (reusable component)
private struct KeyboardShortcutBadge: View {
    let key: String
    
    var body: some View {
        Text(key)
            .font(TTFont.badge)
            .foregroundColor(.ttTextTertiary)
            .padding(.horizontal, TTSpacing.tight)
            .padding(.vertical, TTSpacing.xxxs)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.ttSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.ttBorder.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }
}
