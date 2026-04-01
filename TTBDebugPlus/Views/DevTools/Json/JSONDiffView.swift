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
                HStack(spacing: 6) {
                    Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1)
                    Text("DIFF RESULTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.ttTextMuted)
                        .tracking(1.5)
                    Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.ttSurface.opacity(0.15))
                
                // Diff results — fills remaining space
                diffResultsView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            if !initialLeft.isEmpty {
                leftJSON = initialLeft
            }
        }
    }
    
    // MARK: - Header
    private var diffHeader: some View {
        HStack(spacing: 12) {
            // Icon with glow
            ZStack {
                Circle()
                    .fill(Color.ttPrimary.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: "rectangle.on.rectangle")
                    .font(.ttIcon(TTIcon.lg))
                    .foregroundColor(.ttPrimary)
            }
            
            Text("JSON Compare")
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextPrimary)
            
            Spacer()
            
            if let result = diffResult {
                // Stats badges
                HStack(spacing: 10) {
                    statBadge(count: result.stats.added, label: "Added", color: .ttSuccess, icon: "plus.circle.fill")
                    statBadge(count: result.stats.removed, label: "Removed", color: .ttError, icon: "minus.circle.fill")
                    statBadge(count: result.stats.changed, label: "Changed", color: .ttWarning, icon: "arrow.triangle.2.circlepath")
                }
                
                Divider().frame(height: 16)
                
                // Navigate diffs
                if result.stats.hasChanges {
                    HStack(spacing: 4) {
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
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.ttIcon(TTIcon.md))
                    Text("Compare")
                        .font(TTFont.labelMedium)
                }
            }
            .buttonStyle(.ttPrimaryCompact)
            .disabled(leftJSON.isEmpty || rightJSON.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.ttSurface.opacity(0.15))
    }
    
    private func statBadge(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.ttIcon(TTIcon.xs))
                .foregroundColor(color)
            Text("\(count)")
                .font(TTFont.badge)
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.ttTextTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.08))
        )
    }
    
    // MARK: - Input Panes
    private func diffInputPane(title: String, text: Binding<String>, side: DiffSide) -> some View {
        VStack(spacing: 0) {
            // Pane header
            HStack(spacing: 8) {
                // Side indicator dot
                Circle()
                    .fill(side == .left ? Color.ttError.opacity(0.6) : Color.ttSuccess.opacity(0.6))
                    .frame(width: 6, height: 6)
                
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.ttTextSecondary)
                    .tracking(0.6)
                
                Spacer()
                
                // Character count
                if !text.wrappedValue.isEmpty {
                    Text("\(text.wrappedValue.count) chars")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.ttTextMuted)
                }
                
                // Action buttons
                HStack(spacing: 2) {
                    Button(action: {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            text.wrappedValue = str
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.ttIcon(TTIcon.xs))
                            Text("Paste")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.ttSurface.opacity(0.25))
            .overlay(
                Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1),
                alignment: .bottom
            )
            
            // Text input — fills all remaining space
            TextEditor(text: text)
                .font(Font.system(size: 12, weight: .regular, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundColor(.ttTextPrimary)
                .background(Color.ttBackground.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    // Placeholder
                    Group {
                        if text.wrappedValue.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: side == .left ? "doc.text" : "doc.text.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.ttTextMuted.opacity(0.5))
                                Text("Paste JSON here")
                                    .font(.system(size: 11, weight: .medium))
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
            VStack(spacing: 10) {
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
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.ttSuccess.opacity(0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
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
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.ttWarning.opacity(0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
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
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.ttSurface.opacity(0.5))
                        .frame(width: 56, height: 56)
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(.ttTextMuted)
                }
                Text("Ready to Compare")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextSecondary)
                Text("Paste JSON on both sides and click Compare")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                
                // Keyboard shortcut hint
                HStack(spacing: 4) {
                    KeyboardShortcutBadge(key: "⌘")
                    KeyboardShortcutBadge(key: "V")
                    Text("to paste")
                        .font(.system(size: 9, weight: .medium))
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
                                .padding(.leading, 12)
                                .padding(.trailing, 4)
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
                            HStack(spacing: 4) {
                                Text("+")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.ttSuccess)
                                Text(node.rightValue ?? "")
                                    .font(TTFont.codeMedium)
                                    .foregroundColor(.ttSuccess)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        case .removed:
                            HStack(spacing: 4) {
                                Text("−")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.ttError)
                                Text(node.leftValue ?? "")
                                    .font(TTFont.codeMedium)
                                    .foregroundColor(.ttError)
                                    .strikethrough()
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        case .changed(let old, let new):
                            HStack(spacing: 6) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
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
}

// MARK: - Keyboard Shortcut Badge (reusable component)
private struct KeyboardShortcutBadge: View {
    let key: String
    
    var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.ttTextTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
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
