//
//  Spacing.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Design system spacing tokens based on 4px/8px grid.
//  Values scale with DesignSystemConfig.spacingScale (applied metrics).
//

import SwiftUI

// MARK: - Spacing Tokens

enum TTSpacing {
    private static var cfg: DesignSystemConfig { DesignSystemConfig.shared }

    private static func s(_ base: CGFloat) -> CGFloat { cfg.scaledSpacing(base) }

    // Base scale (4px grid)
    static var xxxs: CGFloat { s(2) }
    static var xxs: CGFloat { s(4) }
    static var xs: CGFloat { s(6) }
    static var sm: CGFloat { s(8) }
    static var md: CGFloat { s(12) }
    static var lg: CGFloat { s(16) }
    static var xl: CGFloat { s(20) }
    static var xxl: CGFloat { s(24) }
    static var xxxl: CGFloat { s(32) }
    static var xxxxl: CGFloat { s(40) }

    // Semantic aliases — Rows
    static var rowVertical: CGFloat { s(7) }
    static var rowHorizontal: CGFloat { s(16) }

    // Semantic aliases — Sections
    static var sectionPadding: CGFloat { s(16) }
    static var cardPadding: CGFloat { s(16) }

    // Semantic aliases — Toolbar / Filter
    static var toolbarVertical: CGFloat { s(8) }
    static var toolbarHorizontal: CGFloat { s(12) }
    static var filterBarGap: CGFloat { s(6) }

    // Semantic aliases — Inline elements
    static var inlineGapTiny: CGFloat { s(2) }
    static var inlineGapSmall: CGFloat { s(3) }
    static var inlineGapMedium: CGFloat { s(4) }
    static var inlineGapLarge: CGFloat { s(6) }
    static var inlineGapXL: CGFloat { s(8) }

    // Semantic aliases — Buttons
    static var buttonPaddingH: CGFloat { s(20) }
    static var buttonPaddingV: CGFloat { s(10) }
    static var buttonCompactH: CGFloat { s(12) }
    static var buttonCompactV: CGFloat { s(6) }

    // Semantic aliases — Input fields
    static var inputPaddingH: CGFloat { s(10) }
    static var inputPaddingV: CGFloat { s(5) }

    // Semantic aliases — Badges
    static var badgePaddingH: CGFloat { s(8) }
    static var badgePaddingV: CGFloat { s(3) }

    // Semantic aliases — App chrome (sidebar / tab bar / status / menu bar)
    /// Tight icon↔label gaps (legacy 5pt)
    static var tight: CGFloat { s(5) }
    /// Brand / chrome horizontal inset (legacy 14pt)
    static var chromeInsetH: CGFloat { s(14) }
    /// Brand / chrome vertical inset (legacy 10pt)
    static var chromeInsetV: CGFloat { s(10) }
    /// Tab bar title leading (legacy 20pt)
    static var tabTitleLeading: CGFloat { s(20) }
    /// Tab cluster leading after title (legacy 24pt)
    static var tabClusterLeading: CGFloat { s(24) }
    /// Status bar / chrome bar height (legacy 32pt)
    static var statusBarHeight: CGFloat { s(32) }
    /// Icon tool button hit target (legacy 28pt)
    static var controlHit: CGFloat { s(28) }
    /// Primary action min height in sidebar (legacy 36pt)
    static var controlMinHeight: CGFloat { s(36) }
    /// Accessible control target. Never shrinks below the macOS/iOS 44pt baseline.
    static var accessibleControlHit: CGFloat { max(44, s(44)) }
    /// DebugKit brand artwork in compact chrome.
    static var compactBrandIcon: CGFloat { max(40, s(40)) }
    /// Compact menu bar console width. May grow with user spacing preferences.
    static var menuBarPanelWidth: CGFloat { max(320, s(320)) }
    /// Empty / hero icon circle (legacy 80pt)
    static var emptyStateIcon: CGFloat { s(80) }
    /// Dev tool card icon tile (legacy 42pt)
    static var toolIconTile: CGFloat { s(42) }

    // Semantic aliases — Residual layout (Phase 4)
    /// 1pt micro pad / stacked hairline gap (badges, segmented toolbars)
    static var hairline: CGFloat { s(1) }
    /// Nested content indent under step titles (Integration Guide, legacy 46pt)
    static var nestIndent: CGFloat { s(46) }
    /// Nested row indent under menu section icons (legacy 52pt)
    static var menuRowIndent: CGFloat { s(52) }
    /// Wide sheet horizontal padding (Welcome, legacy 60pt)
    static var sheetWidePadding: CGFloat { s(60) }
    /// Large section stack gap (Usage Guide, legacy 28pt)
    static var sectionGapLarge: CGFloat { s(28) }
}

// MARK: - Spacing View Modifier

struct TTContentPadding: ViewModifier {
    let horizontal: CGFloat
    let vertical: CGFloat

    func body(content: Content) -> some View {
        content.padding(.horizontal, horizontal).padding(.vertical, vertical)
    }
}

extension View {
    func ttPadding(_ spacing: CGFloat) -> some View {
        padding(spacing)
    }

    func ttPadding(h: CGFloat, v: CGFloat) -> some View {
        modifier(TTContentPadding(horizontal: h, vertical: v))
    }

    func ttRowPadding() -> some View {
        modifier(TTContentPadding(horizontal: TTSpacing.rowHorizontal, vertical: TTSpacing.rowVertical))
    }

    func ttSectionPadding() -> some View {
        padding(TTSpacing.sectionPadding)
    }

    func ttToolbarPadding() -> some View {
        modifier(TTContentPadding(horizontal: TTSpacing.toolbarHorizontal, vertical: TTSpacing.toolbarVertical))
    }
}
