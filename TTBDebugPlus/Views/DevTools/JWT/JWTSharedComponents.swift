//
//  JWTSharedComponents.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Reusable building blocks for the JWT Debugger sub-tools. Inherits the app
//  design system (TTFont / Color.tt* / TTRadius) and mirrors the card / action
//  idioms used by CaseConverterToolView.
//

import AppKit
import SwiftUI

// MARK: - Section Card

struct JWTSectionCard<Content: View>: View {
    let title: String
    let icon: String
    var accessory: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextSecondary)
                Spacer()
                if let accessory { accessory }
            }
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(Color.ttSurface.opacity(0.36))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Copy Button

struct JWTCopyButton: View {
    let text: String
    var label: String = "Copy"
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(TTFont.labelSmall)
                .foregroundColor(copied ? .ttSuccess : .ttTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(copied ? Color.ttSuccess.opacity(0.1) : Color.ttSurface.opacity(0.35))
                )
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help("Copy to clipboard")
    }

    private func copy() {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Action Button (full width)

struct JWTActionButton: View {
    let title: String
    let icon: String
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(TTFont.labelMedium)
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var foreground: Color {
        if disabled { return .ttTextMuted }
        return prominent ? .white : .ttTextSecondary
    }

    private var background: Color {
        if disabled { return Color.ttSurface.opacity(0.18) }
        return prominent ? Color.ttPrimary.opacity(0.85) : Color.ttSurface.opacity(0.42)
    }
}

// MARK: - Mono Editor (input)

struct JWTMonoEditor: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(TTFont.codeMedium)
            .foregroundColor(.ttTextPrimary)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .padding(10)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(TTFont.codeMedium)
                        .foregroundColor(.ttTextMuted)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(Color.ttBackground.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: TTRadius.md)
                            .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Mono Read-only Display

struct JWTMonoDisplay: View {
    let text: String
    var placeholder: String = "—"

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(TTFont.codeMedium)
                .foregroundColor(text.isEmpty ? .ttTextMuted : .ttTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(Color.ttBackground.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Colorized Token (header.payload.signature)

struct JWTColorizedToken: View {
    let token: String

    var body: some View {
        let segments = token.components(separatedBy: ".")
        return Text(attributed(segments))
            .font(TTFont.codeSmall)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(Color.ttBackground.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: TTRadius.md)
                            .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                    )
            )
    }

    private func attributed(_ segments: [String]) -> AttributedString {
        let colors: [Color] = [.ttPrimaryLight, .ttJsonString, .ttSuccess]
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            var piece = AttributedString(segment)
            piece.foregroundColor = index < colors.count ? colors[index] : .ttTextSecondary
            result.append(piece)
            if index < segments.count - 1 {
                var dot = AttributedString(".")
                dot.foregroundColor = .ttTextMuted
                result.append(dot)
            }
        }
        return result
    }
}

// MARK: - Claim Row

struct JWTClaimRowView: View {
    let claim: JWTClaimRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(claim.key)
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttJsonKey)
                if let description = claim.description {
                    Text(description)
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.ttSurface.opacity(0.4)))
                }
                Spacer()
                if let severity = claim.severity {
                    Image(systemName: severity.icon)
                        .font(.system(size: 10))
                        .foregroundColor(severity.color)
                }
            }
            Text(claim.value)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .textSelection(.enabled)
                .lineLimit(3)
            if let annotation = claim.annotation {
                Text(annotation)
                    .font(TTFont.bodySmall)
                    .foregroundColor(claim.severity?.color ?? .ttTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.12)).frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Security Finding Row

struct JWTFindingRowView: View {
    let finding: JWTSecurityFinding

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.severity.icon)
                .font(.system(size: 13))
                .foregroundColor(finding.severity.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(finding.title)
                        .font(TTFont.labelMedium)
                        .foregroundColor(.ttTextPrimary)
                    Text(finding.severity.label)
                        .font(TTFont.badge)
                        .foregroundColor(finding.severity.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(finding.severity.color.opacity(0.14)))
                }
                Text(finding.detail)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.sm)
                .fill(finding.severity.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .stroke(finding.severity.color.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

// MARK: - Empty State

struct JWTEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Color.ttSurface.opacity(0.4)).frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(.ttTextMuted)
            }
            Text(title)
                .font(TTFont.heading3)
                .foregroundColor(.ttTextSecondary)
            Text(subtitle)
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pane Header

struct JWTPaneHeader: View {
    let title: String
    let icon: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextSecondary)
            Spacer()
            if let trailing { trailing }
        }
    }
}
