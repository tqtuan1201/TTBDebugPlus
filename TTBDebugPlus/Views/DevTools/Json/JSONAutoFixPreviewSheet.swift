//
//  JSONAutoFixPreviewSheet.swift
//  TTBDebugPlus
//
//  Preview Auto Fix / Auto Format mutations before applying.
//

import SwiftUI

struct JSONAutoFixPreviewSheet: View {
    let result: JSONRepairResult
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: TTSpacing.md) {
                Image(systemName: result.isValidAfterRepair ? "wrench.and.screwdriver.fill" : "exclamationmark.triangle.fill")
                    .font(.ttIcon(TTIcon.xxxl))
                    .fontWeight(.semibold)
                    .foregroundColor(result.isValidAfterRepair ? .ttPrimary : .ttWarning)

                VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                    Text("Preview Auto Fix")
                        .font(TTFont.heading2)
                        .foregroundColor(.ttTextPrimary)
                    Text(result.isValidAfterRepair
                         ? "Review changes, then apply when ready."
                         : "Partial repair — result may still be invalid.")
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextSecondary)
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.ttGhost)
                    .keyboardShortcut(.cancelAction)

                Button(action: onApply) {
                    HStack(spacing: TTSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply Fix")
                    }
                }
                .buttonStyle(.ttPrimary)
                .keyboardShortcut(.defaultAction)
                // Only allow apply when result is valid JSON
                .disabled(!result.canSafelyApply && !result.isValidAfterRepair)
            }
            .padding(TTSpacing.lg)
            .background(Color.ttSurface.opacity(0.35))
            .overlay(Rectangle().fill(Color.ttBorder.opacity(0.25)).frame(height: 1), alignment: .bottom)

            // Fix list
            if !result.fixes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TTSpacing.sm) {
                        ForEach(result.fixes) { fix in
                            HStack(spacing: TTSpacing.xs) {
                                Image(systemName: "sparkles")
                                    .font(TTFont.labelSmall)
                                Text(fix.description)
                                    .font(TTFont.labelSmall)
                            }
                            .foregroundColor(.ttPrimary)
                            .padding(.horizontal, TTSpacing.inputPaddingH)
                            .padding(.vertical, TTSpacing.xs)
                            .background(
                                Capsule().fill(Color.ttPrimary.opacity(0.12))
                            )
                        }
                    }
                    .padding(.horizontal, TTSpacing.lg)
                    .padding(.vertical, TTSpacing.inputPaddingH)
                }
                .background(Color.ttBackground)
                .overlay(Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1), alignment: .bottom)
            }

            // Stats row
            HStack(spacing: TTSpacing.lg) {
                stat(title: "Original", value: byteString(result.original))
                stat(title: "Repaired", value: byteString(result.repaired))
                HStack(spacing: TTSpacing.xs) {
                    Circle()
                        .fill(result.isValidAfterRepair ? Color.ttSuccess : Color.ttError)
                        .frame(width: 7, height: 7)
                    Text(result.isValidAfterRepair ? "Valid after fix" : "Still invalid")
                        .font(TTFont.labelSmall)
                        .foregroundColor(result.isValidAfterRepair ? .ttSuccess : .ttError)
                }
                Spacer()
                Picker("", selection: $showOriginal) {
                    Text("Repaired").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, TTSpacing.lg)
            .padding(.vertical, TTSpacing.inputPaddingH)

            if let msg = result.validationMessage, !result.isValidAfterRepair {
                HStack(spacing: TTSpacing.sm) {
                    Image(systemName: "info.circle")
                    Text(msg)
                        .font(TTFont.bodySmall)
                }
                .foregroundColor(.ttWarning)
                .padding(.horizontal, TTSpacing.lg)
                .padding(.bottom, TTSpacing.sm)
            }

            // Diff-ish preview
            ScrollView {
                Text(showOriginal ? result.original : result.repaired)
                    .font(TTFont.codeMedium)
                    .foregroundColor(.ttTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TTSpacing.lg)
            }
            .background(Color.ttBackground)
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .background(Color.ttSurface)
    }

    private func stat(title: String, value: String) -> some View {
        HStack(spacing: TTSpacing.xxs) {
            Text(title)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
            Text(value)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)
        }
    }

    private func byteString(_ s: String) -> String {
        let b = s.utf8.count
        if b < 1024 { return "\(b) B" }
        if b < 1_048_576 { return String(format: "%.1f KB", Double(b) / 1024) }
        return String(format: "%.1f MB", Double(b) / 1_048_576)
    }
}
