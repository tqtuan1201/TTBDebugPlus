//
//  PaletteHistoryView.swift
//  TTBDebugPlus
//

import SwiftUI

struct PaletteHistoryView: View {
    @Bindable var viewModel: ColorPickerToolViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CardView(
            title: "SESSION PALETTE",
            titleTrailing: AnyView(paletteActions)
        ) {
            if viewModel.sessionPalette.isEmpty {
                Text("Pick or add colors for today’s session. History clears on a new calendar day.")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Session palette empty")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TTSpacing.sm) {
                        ForEach(viewModel.sessionPalette) { entry in
                            swatch(entry)
                        }
                    }
                }
            }
        }
    }

    private var paletteActions: some View {
        HStack(spacing: TTSpacing.xs) {
            Button {
                viewModel.addCurrentToPalette()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.ttSecondaryCompact)
            .accessibilityLabel("Add current color to palette")

            Button {
                _ = viewModel.exportPaletteJSON()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.ttSecondaryCompact)
            .disabled(!viewModel.canExportPalette)
            .accessibilityLabel("Export palette as JSON")

            Button {
                viewModel.clearPalette()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.ttSecondaryCompact)
            .disabled(viewModel.sessionPalette.isEmpty)
            .accessibilityLabel("Clear session palette")
        }
    }

    private func swatch(_ entry: PaletteColorEntry) -> some View {
        let selected = entry.hex.caseInsensitiveCompare(viewModel.normalizedHex) == .orderedSame
        let color = Color(
            hue: entry.hue,
            saturation: entry.saturation,
            brightness: entry.brightness,
            opacity: entry.alpha
        )

        return Button {
            viewModel.selectPaletteEntry(entry)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(selected ? Color.ttPrimary : Color.ttBorder.opacity(0.6), lineWidth: selected ? 2.5 : 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .scaleEffect(selected && !reduceMotion ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .help(entry.hex)
        .accessibilityLabel("Color \(entry.hex)")
        .accessibilityHint("Selects this color")
        .animation(reduceMotion ? nil : TTAnimation.spring, value: selected)
    }
}
