//
//  FormatOutputPanel.swift
//  TTBDebugPlus
//

import SwiftUI

struct FormatOutputPanel: View {
    @Bindable var viewModel: ColorPickerToolViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CardView(title: "FORMAT OUTPUT") {
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                ForEach(ColorFormat.allCases) { format in
                    formatRow(format)
                }

                HStack {
                    Spacer()
                    Button {
                        viewModel.copyAllFormats()
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.ttSecondaryCompact)
                    .accessibilityLabel("Copy all color formats")
                }
                .padding(.top, TTSpacing.xs)
            }
        }
    }

    private func formatRow(_ format: ColorFormat) -> some View {
        let isCopied = viewModel.lastCopiedFormat == format
        return HStack(alignment: .center, spacing: TTSpacing.sm) {
            Text(format.displayName)
                .font(TTFont.labelMedium)
                .foregroundColor(.ttTextSecondary)
                .frame(width: 72, alignment: .leading)

            Text(viewModel.formatString(format))
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.copyFormat(format)
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.ttIcon(TTIcon.lg))
            }
            .buttonStyle(.ttGhost)
            .help("Copy \(format.displayName)")
            .accessibilityLabel("Copy \(format.displayName)")
        }
        .padding(.horizontal, TTSpacing.sm)
        .padding(.vertical, TTSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.sm)
                .fill(isCopied ? Color.ttPrimary.opacity(0.15) : Color.clear)
        )
        .animation(reduceMotion ? nil : TTAnimation.fast, value: isCopied)
    }
}
