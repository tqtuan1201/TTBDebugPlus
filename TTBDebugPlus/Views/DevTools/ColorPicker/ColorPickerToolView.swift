//
//  ColorPickerToolView.swift
//  TTBDebugPlus
//
//  Dev Tools workbench: screen pick, HSB wheel, formats, palette, WCAG, tokens.
//

import SwiftUI

struct ColorPickerToolView: View {
    @State private var viewModel = ColorPickerToolViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if let status = viewModel.statusMessage {
                statusStrip(status)
            }

            if let hint = viewModel.samplerHint {
                TTBanner(kind: .warning, message: hint)
                    .padding(.horizontal, TTSpacing.sectionPadding)
                    .padding(.top, TTSpacing.sm)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.md) {
                    HStack(alignment: .top, spacing: TTSpacing.md) {
                        colorControlsCard
                            .frame(minWidth: 280, maxWidth: 360)
                        FormatOutputPanel(viewModel: viewModel)
                            .frame(maxWidth: .infinity)
                    }

                    PaletteHistoryView(viewModel: viewModel)
                    WCAGContrastPanel(viewModel: viewModel)
                    DesignTokenMatchPanel(viewModel: viewModel)
                }
                .padding(TTSpacing.sectionPadding)
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: TTSpacing.md) {
            Text("Sample screen colors and export developer-ready code.")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextSecondary)
                .lineLimit(1)

            Spacer()

            Button {
                Task { await viewModel.pickFromScreen() }
            } label: {
                Label(
                    viewModel.isSampling ? "Picking…" : "Pick Screen",
                    systemImage: AppIcon.colorPicker
                )
            }
            .buttonStyle(.ttPrimary)
            .disabled(viewModel.isSampling)
            .accessibilityLabel("Pick color from screen")
            .accessibilityHint("Opens system eyedropper")
            .help("Sample any on-screen pixel")
        }
        .padding(.horizontal, TTSpacing.sectionPadding)
        .padding(.vertical, 10)
        .background(Color.ttSurface.opacity(0.25))
    }

    private func statusStrip(_ status: String) -> some View {
        // Use banner success surfaces (AA-safe) instead of status.opacity(0.12) + canvas text.
        HStack(spacing: TTSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(TTBannerKind.success.foreground)
            Text(status)
                .font(TTFont.bodySmall)
                .foregroundColor(TTBannerKind.success.foreground)
            Spacer()
        }
        .padding(.horizontal, TTSpacing.sectionPadding)
        .padding(.vertical, 6)
        .background(TTBannerKind.success.background)
        .transition(reduceMotion ? .opacity : TTAnimation.fadeIn)
        .accessibilityLabel(status)
    }

    // MARK: - Color controls

    private var colorControlsCard: some View {
        CardView(title: "COLOR") {
            VStack(alignment: .leading, spacing: TTSpacing.md) {
                HStack(spacing: TTSpacing.md) {
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(Color(nsColor: viewModel.previewNSColor))
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: TTRadius.md)
                                .stroke(Color.ttBorder, lineWidth: 1)
                        )
                        .accessibilityLabel("Selected color preview \(viewModel.normalizedHex)")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.normalizedHex)
                            .font(TTFont.codeLarge)
                            .foregroundColor(.ttTextPrimary)
                        Text(viewModel.formatString(.rgb))
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextSecondary)
                    }
                    Spacer(minLength: 0)
                }

                ColorWheelView(
                    hue: $viewModel.hue,
                    saturation: $viewModel.saturation,
                    brightness: viewModel.brightness
                )
                .frame(height: 200)
                .onChange(of: viewModel.hue) { _, _ in viewModel.hexInput = viewModel.normalizedHex }
                .onChange(of: viewModel.saturation) { _, _ in viewModel.hexInput = viewModel.normalizedHex }

                sliderRow("Brightness", value: $viewModel.brightness)
                sliderRow("Saturation", value: $viewModel.saturation)
                sliderRow("Alpha", value: $viewModel.alpha)

                HStack(spacing: TTSpacing.sm) {
                    TextField("#RRGGBB", text: $viewModel.hexInput)
                        .textFieldStyle(.roundedBorder)
                        .font(TTFont.codeLarge)
                        .frame(maxWidth: 160)
                        .onSubmit { viewModel.applyHexInput() }
                        .accessibilityLabel("Hex color")

                    Button("Apply") {
                        viewModel.applyHexInput()
                    }
                    .buttonStyle(.ttSecondaryCompact)
                    .accessibilityLabel("Apply hex color")

                    Spacer()
                }

                if let error = viewModel.hexInputError {
                    Text(error)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttError)
                        .accessibilityLabel(error)
                }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: TTSpacing.sm) {
            Text(title)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextSecondary)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(Color.ttPrimary)
                .onChange(of: value.wrappedValue) { _, _ in
                    viewModel.hexInput = viewModel.normalizedHex
                    viewModel.hexInputError = nil
                }
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

#Preview {
    ColorPickerToolView()
        .frame(width: 900, height: 700)
        .preferredColorScheme(.dark)
}
