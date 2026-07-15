//
//  ButtonStyles.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Button styles with macOS hover support — spacing/radius via design tokens.
//

import SwiftUI

// MARK: - Primary Button Style
struct TTPrimaryButtonStyle: ButtonStyle {
    var isCompact: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, isCompact: isCompact, isHovered: $isHovered)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isCompact: Bool
        @Binding var isHovered: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(isCompact ? TTFont.labelMedium : TTFont.labelLarge)
                .foregroundColor(isEnabled ? .ttTextOnAccent : .ttTextOnAccent.opacity(0.55))
                .padding(.horizontal, isCompact ? TTSpacing.buttonCompactH : TTSpacing.buttonPaddingH)
                .padding(.vertical, isCompact ? TTSpacing.buttonCompactV : TTSpacing.buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(Color.ttPrimary)
                        .opacity(isEnabled
                            ? (configuration.isPressed ? 0.8 : (isHovered ? 0.9 : 1.0))
                            : 0.45)
                )
                .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
                .animation(TTAnimation.normal, value: configuration.isPressed)
                .animation(TTAnimation.normal, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Secondary Button Style
struct TTSecondaryButtonStyle: ButtonStyle {
    var isCompact: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, isCompact: isCompact, isHovered: $isHovered)
    }

    private struct SecondaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isCompact: Bool
        @Binding var isHovered: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(isCompact ? TTFont.labelMedium : TTFont.labelLarge)
                .foregroundColor(isEnabled ? .ttTextPrimary : .ttTextMuted)
                .padding(.horizontal, isCompact ? TTSpacing.buttonCompactH : TTSpacing.buttonPaddingH)
                .padding(.vertical, isCompact ? TTSpacing.buttonCompactV : TTSpacing.buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(isEnabled
                            ? (isHovered ? Color.ttSurfaceHover : Color.ttSurface)
                            : Color.ttSurface.opacity(0.55))
                        .opacity(configuration.isPressed && isEnabled ? 0.7 : 1.0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(
                            isEnabled
                                ? (isHovered ? Color.ttPrimary.opacity(0.5) : Color.ttBorder)
                                : Color.ttBorder.opacity(0.45),
                            lineWidth: 1
                        )
                )
                .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
                .animation(TTAnimation.normal, value: configuration.isPressed)
                .animation(TTAnimation.normal, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Outlined Button Style
struct TTOutlinedButtonStyle: ButtonStyle {
    var color: Color = .ttPrimary
    var isCompact: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        OutlinedButtonBody(configuration: configuration, color: color, isCompact: isCompact, isHovered: $isHovered)
    }

    private struct OutlinedButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let isCompact: Bool
        @Binding var isHovered: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(isCompact ? TTFont.labelMedium : TTFont.labelLarge)
                .foregroundColor(isEnabled ? color : .ttTextMuted)
                .padding(.horizontal, isCompact ? TTSpacing.buttonCompactH : TTSpacing.buttonPaddingH)
                .padding(.vertical, isCompact ? TTSpacing.buttonCompactV : TTSpacing.buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(isEnabled
                            ? color.opacity(configuration.isPressed ? 0.15 : (isHovered ? 0.08 : 0.0))
                            : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(isEnabled ? color : Color.ttBorder.opacity(0.5), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
                .animation(TTAnimation.normal, value: configuration.isPressed)
                .animation(TTAnimation.normal, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Inverted Button Style
struct TTInvertedButtonStyle: ButtonStyle {
    var isCompact: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        InvertedButtonBody(configuration: configuration, isCompact: isCompact, isHovered: $isHovered)
    }

    private struct InvertedButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isCompact: Bool
        @Binding var isHovered: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(isCompact ? TTFont.labelMedium : TTFont.labelLarge)
                .foregroundColor(isEnabled ? .ttBackground : .ttTextMuted)
                .padding(.horizontal, isCompact ? TTSpacing.buttonCompactH : TTSpacing.buttonPaddingH)
                .padding(.vertical, isCompact ? TTSpacing.buttonCompactV : TTSpacing.buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(Color.ttTextPrimary)
                        .opacity(isEnabled
                            ? (configuration.isPressed ? 0.8 : (isHovered ? 0.9 : 1.0))
                            : 0.35)
                )
                .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
                .animation(TTAnimation.normal, value: configuration.isPressed)
                .animation(TTAnimation.normal, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Ghost Button (Toolbar style)
struct TTGhostButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration, isHovered: $isHovered)
    }

    private struct GhostButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Binding var isHovered: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(TTFont.labelMedium)
                .foregroundColor(
                    isEnabled
                        ? (configuration.isPressed ? .ttTextPrimary : (isHovered ? .ttTextPrimary : .ttTextSecondary))
                        : .ttTextMuted
                )
                .padding(TTSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(isEnabled
                            ? (configuration.isPressed ? Color.ttSurfaceHover : (isHovered ? Color.ttSurface : Color.clear))
                            : Color.clear)
                )
                .animation(TTAnimation.fast, value: configuration.isPressed)
                .animation(TTAnimation.fast, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Sidebar Item Button Style
struct TTSidebarItemStyle: ButtonStyle {
    var isSelected: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        SidebarItemBody(configuration: configuration, isSelected: isSelected, isHovered: $isHovered)
    }

    private struct SidebarItemBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Binding var isHovered: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(TTFont.sidebarItem)
                .foregroundColor(
                    isEnabled
                        ? (isSelected ? .ttPrimary : .ttTextSecondary)
                        : .ttTextMuted
                )
                .padding(.horizontal, TTSpacing.md)
                .padding(.vertical, TTSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(isSelected
                            ? Color.ttPrimary.opacity(0.12)
                            : (configuration.isPressed
                                ? Color.ttSurfaceHover
                                : (isHovered ? Color.ttSurface.opacity(0.6) : Color.clear)))
                )
                .animation(TTAnimation.normal, value: isSelected)
                .animation(TTAnimation.fast, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Button Style Extensions
extension ButtonStyle where Self == TTPrimaryButtonStyle {
    static var ttPrimary: TTPrimaryButtonStyle { TTPrimaryButtonStyle() }
    static var ttPrimaryCompact: TTPrimaryButtonStyle { TTPrimaryButtonStyle(isCompact: true) }
}

extension ButtonStyle where Self == TTSecondaryButtonStyle {
    static var ttSecondary: TTSecondaryButtonStyle { TTSecondaryButtonStyle() }
    static var ttSecondaryCompact: TTSecondaryButtonStyle { TTSecondaryButtonStyle(isCompact: true) }
}

extension ButtonStyle where Self == TTOutlinedButtonStyle {
    static var ttOutlined: TTOutlinedButtonStyle { TTOutlinedButtonStyle() }
}

extension ButtonStyle where Self == TTInvertedButtonStyle {
    static var ttInverted: TTInvertedButtonStyle { TTInvertedButtonStyle() }
}

extension ButtonStyle where Self == TTGhostButtonStyle {
    static var ttGhost: TTGhostButtonStyle { TTGhostButtonStyle() }
}
