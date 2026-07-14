//
//  WCAGContrastPanel.swift
//  TTBDebugPlus
//

import SwiftUI

struct WCAGContrastPanel: View {
    @Bindable var viewModel: ColorPickerToolViewModel

    var body: some View {
        CardView(title: "WCAG CONTRAST") {
            VStack(alignment: .leading, spacing: TTSpacing.md) {
                HStack(spacing: TTSpacing.md) {
                    colorRole(title: "Foreground", hsb: viewModel.foregroundHSB) {
                        viewModel.setAsForeground()
                    }
                    colorRole(title: "Background", hsb: viewModel.backgroundHSB) {
                        viewModel.setAsBackground()
                    }
                    Spacer(minLength: 0)
                    ratioBlock
                }

                if let result = viewModel.wcagResult {
                    badgeRow(result)
                } else {
                    Text("Set both foreground and background to compute contrast.")
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextSecondary)
                }
            }
        }
    }

    private var ratioBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Ratio")
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
            if let result = viewModel.wcagResult {
                Text(String(format: "%.2f:1", result.ratio))
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                    .accessibilityLabel(String(format: "Contrast ratio %.2f to 1", result.ratio))
            } else {
                Text("—")
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextMuted)
            }
        }
    }

    private func colorRole(title: String, hsb: ColorHSB?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            Text(title)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
            HStack(spacing: TTSpacing.sm) {
                Circle()
                    .fill(previewColor(hsb))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.ttBorder, lineWidth: 1))
                Button("Set \(title)") {
                    action()
                }
                .buttonStyle(.ttSecondaryCompact)
                .accessibilityLabel("Set \(title.lowercased()) from current color")
            }
        }
    }

    private func badgeRow(_ result: WCAGResult) -> some View {
        HStack(spacing: TTSpacing.sm) {
            badge("AA Normal", pass: result.aaNormal)
            badge("AA Large", pass: result.aaLarge)
            badge("AAA Normal", pass: result.aaaNormal)
            badge("AAA Large", pass: result.aaaLarge)
            Spacer(minLength: 0)
        }
    }

    private func badge(_ title: String, pass: Bool) -> some View {
        TTStatusPill(
            text: "\(title) \(pass ? "Pass" : "Fail")",
            kind: pass ? .success : .error
        )
        .accessibilityLabel("\(title) \(pass ? "pass" : "fail")")
    }

    private func previewColor(_ hsb: ColorHSB?) -> Color {
        guard let hsb else { return Color.ttSurfaceLight }
        return Color(
            hue: hsb.hue,
            saturation: hsb.saturation,
            brightness: hsb.brightness,
            opacity: hsb.alpha
        )
    }
}

// MARK: - Design token match

struct DesignTokenMatchPanel: View {
    @Bindable var viewModel: ColorPickerToolViewModel

    var body: some View {
        CardView(title: "DESIGN TOKEN MATCH") {
            let matches = viewModel.designTokenMatches
            if matches.isEmpty {
                Text("No close design token (≥ 85% similarity) for \(viewModel.normalizedHex).")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
            } else {
                VStack(alignment: .leading, spacing: TTSpacing.sm) {
                    ForEach(matches) { match in
                        HStack(spacing: TTSpacing.sm) {
                            Circle()
                                .fill(Color(hex: match.tokenHex))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.ttBorder.opacity(0.5), lineWidth: 1))
                            Text(match.tokenName)
                                .font(TTFont.codeMedium)
                                .foregroundColor(.ttTextPrimary)
                            Text(match.tokenHex)
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextSecondary)
                            Spacer()
                            let pct = Int((match.similarity * 100).rounded())
                            TTStatusPill(
                                text: match.similarity >= 0.999 ? "Exact" : "\(pct)%",
                                kind: match.similarity >= 0.999 ? .success : .info
                            )
                        }
                        .accessibilityLabel("\(match.tokenName) \(match.tokenHex) similarity \(Int(match.similarity * 100)) percent")
                    }
                }
            }
        }
    }
}
