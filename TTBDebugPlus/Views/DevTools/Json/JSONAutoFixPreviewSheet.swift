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
            HStack(spacing: 12) {
                Image(systemName: result.isValidAfterRepair ? "wrench.and.screwdriver.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(result.isValidAfterRepair ? .ttPrimary : .ttWarning)

                VStack(alignment: .leading, spacing: 2) {
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
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply Fix")
                    }
                }
                .buttonStyle(.ttPrimary)
                .keyboardShortcut(.defaultAction)
                // Only allow apply when result is valid JSON
                .disabled(!result.canSafelyApply && !result.isValidAfterRepair)
            }
            .padding(16)
            .background(Color.ttSurface.opacity(0.35))
            .overlay(Rectangle().fill(Color.ttBorder.opacity(0.25)).frame(height: 1), alignment: .bottom)

            // Fix list
            if !result.fixes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(result.fixes) { fix in
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(fix.description)
                                    .font(TTFont.labelSmall)
                            }
                            .foregroundColor(.ttPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.ttPrimary.opacity(0.12))
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.ttBackground)
                .overlay(Rectangle().fill(Color.ttBorder.opacity(0.15)).frame(height: 1), alignment: .bottom)
            }

            // Stats row
            HStack(spacing: 16) {
                stat(title: "Original", value: byteString(result.original))
                stat(title: "Repaired", value: byteString(result.repaired))
                HStack(spacing: 6) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if let msg = result.validationMessage, !result.isValidAfterRepair {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(msg)
                        .font(TTFont.bodySmall)
                }
                .foregroundColor(.ttWarning)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Diff-ish preview
            ScrollView {
                Text(showOriginal ? result.original : result.repaired)
                    .font(TTFont.codeMedium)
                    .foregroundColor(.ttTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color.ttBackground)
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .background(Color.ttSurface)
    }

    private func stat(title: String, value: String) -> some View {
        HStack(spacing: 4) {
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
