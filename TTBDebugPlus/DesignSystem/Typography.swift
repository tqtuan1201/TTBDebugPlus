//
//  Typography.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Scale-aware via DesignSystemConfig (font scale + text emphasis + line height).
//

import AppKit
import SwiftUI

// MARK: - Typography System

enum TTFont {
    private static var cfg: DesignSystemConfig { DesignSystemConfig.shared }

    private static func system(
        size base: CGFloat,
        weight: Font.Weight,
        design: Font.Design = .default
    ) -> Font {
        .system(
            size: cfg.scaledFont(base),
            weight: cfg.emphasisWeight(weight),
            design: design
        )
    }

    // Display
    static var displayLarge: Font { system(size: 32, weight: .bold) }
    static var displayMedium: Font { system(size: 28, weight: .bold) }

    // Headings
    static var heading1: Font { system(size: 24, weight: .bold) }
    static var heading2: Font { system(size: 20, weight: .semibold) }
    static var heading3: Font { system(size: 17, weight: .semibold) }

    // Body
    static var bodyLarge: Font { system(size: 15, weight: .regular) }
    static var bodyMedium: Font { system(size: 13, weight: .regular) }
    static var bodySmall: Font { system(size: 11, weight: .regular) }

    // Labels
    static var labelLarge: Font { system(size: 13, weight: .semibold) }
    static var labelMedium: Font { system(size: 11, weight: .semibold) }
    static var labelSmall: Font { system(size: 10, weight: .medium) }

    // Code (Monospaced)
    static var codeLarge: Font { system(size: 14, weight: .regular, design: .monospaced) }
    static var codeMedium: Font { system(size: 12, weight: .regular, design: .monospaced) }
    static var codeSmall: Font { system(size: 11, weight: .regular, design: .monospaced) }

    // Special
    static var tabLabel: Font { system(size: 13, weight: .medium) }
    static var sidebarItem: Font { system(size: 13, weight: .medium) }
    static var sidebarHeader: Font { system(size: 11, weight: .bold) }
    static var statusBar: Font { system(size: 11, weight: .regular, design: .monospaced) }
    static var badge: Font { system(size: 10, weight: .bold, design: .monospaced) }
    static var timestamp: Font { system(size: 12, weight: .regular, design: .monospaced) }

    // MARK: Special constructions

    /// Empty-state / hero icon type (light weight, still scale-clamped).
    static func lightDisplay(base: CGFloat = 32) -> Font {
        .system(size: cfg.scaledFont(base), weight: .light)
    }

    /// Zoomable canvas / JSON graph type (node zoom × global font scale).
    static func graph(
        base: CGFloat,
        nodeScale: CGFloat,
        minimum: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(
            size: cfg.graphFontSize(base: base, nodeScale: nodeScale, minimum: minimum),
            weight: cfg.emphasisWeight(weight),
            design: design
        )
    }

    /// AppKit bridge — scaled system font for `NSTextField` / attributes.
    static func nsSystem(ofSize base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let size = cfg.scaledFont(base)
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Text Style Modifiers

struct TTTextStyle: ViewModifier {
    let font: Font
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundColor(color)
            .lineSpacing(DesignSystemConfig.shared.lineHeightExtra)
    }
}

extension View {
    func ttHeading1() -> some View {
        modifier(TTTextStyle(font: TTFont.heading1, color: .ttTextPrimary))
    }

    func ttHeading2() -> some View {
        modifier(TTTextStyle(font: TTFont.heading2, color: .ttTextPrimary))
    }

    func ttHeading3() -> some View {
        modifier(TTTextStyle(font: TTFont.heading3, color: .ttTextPrimary))
    }

    func ttBody() -> some View {
        modifier(TTTextStyle(font: TTFont.bodyMedium, color: .ttTextPrimary))
    }

    func ttBodySecondary() -> some View {
        modifier(TTTextStyle(font: TTFont.bodyMedium, color: .ttTextSecondary))
    }

    func ttCode() -> some View {
        modifier(TTTextStyle(font: TTFont.codeMedium, color: .ttTextPrimary))
    }

    func ttLabel() -> some View {
        // Field / form labels — secondary for AA on both schemes
        modifier(TTTextStyle(font: TTFont.labelMedium, color: .ttTextSecondary))
    }

    func ttLabelSmall() -> some View {
        modifier(TTTextStyle(font: TTFont.labelSmall, color: .ttTextSecondary))
    }

    /// Disabled control caption — muted only
    func ttDisabled() -> some View {
        modifier(TTTextStyle(font: TTFont.bodyMedium, color: .ttTextMuted))
    }

    /// Selected / active control text
    func ttSelected() -> some View {
        modifier(TTTextStyle(font: TTFont.labelMedium, color: .ttPrimary))
    }

    /// Text on solid brand/status fills
    func ttOnAccent() -> some View {
        modifier(TTTextStyle(font: TTFont.labelMedium, color: .ttTextOnAccent))
    }

    func ttCodeSmall() -> some View {
        modifier(TTTextStyle(font: TTFont.codeSmall, color: .ttTextPrimary))
    }

    func ttTimestamp() -> some View {
        modifier(TTTextStyle(font: TTFont.timestamp, color: .ttTextSecondary))
    }

    func ttBadge() -> some View {
        modifier(TTTextStyle(font: TTFont.badge, color: .ttTextPrimary))
    }

    func ttStatusBar() -> some View {
        modifier(TTTextStyle(font: TTFont.statusBar, color: .ttTextSecondary))
    }

    func ttSidebarHeader() -> some View {
        // Section/column chrome headers
        modifier(TTTextStyle(font: TTFont.sidebarHeader, color: .ttTextTertiary))
    }

    func ttSidebarItem() -> some View {
        modifier(TTTextStyle(font: TTFont.sidebarItem, color: .ttTextSecondary))
    }

    /// Placeholder / idle chrome text (filter labels, empty hints)
    func ttPlaceholder() -> some View {
        modifier(TTTextStyle(font: TTFont.bodyMedium, color: .ttTextPlaceholder))
    }

    func ttDisplayLarge() -> some View {
        modifier(TTTextStyle(font: TTFont.displayLarge, color: .ttTextPrimary))
    }

    func ttDisplayMedium() -> some View {
        modifier(TTTextStyle(font: TTFont.displayMedium, color: .ttTextPrimary))
    }
}
