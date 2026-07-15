//
//  IconSizes.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Design system icon size tokens (scale with DesignSystemConfig.fontScale).
//

import SwiftUI

// MARK: - Icon Size Tokens

/// Standard icon sizes for SF Symbols used with `.font(.ttIcon(...))`
enum TTIcon {
    private static var cfg: DesignSystemConfig { DesignSystemConfig.shared }

    private static func i(_ base: CGFloat) -> CGFloat { cfg.scaledIcon(base) }

    static var xxxs: CGFloat { i(7) }
    static var xxs: CGFloat { i(8) }
    static var xs: CGFloat { i(9) }
    static var sm: CGFloat { i(10) }
    static var md: CGFloat { i(11) }
    static var lg: CGFloat { i(12) }
    static var xl: CGFloat { i(14) }
    static var xxl: CGFloat { i(16) }
    static var xxxl: CGFloat { i(20) }
}

// MARK: - Icon Font Helpers

extension Font {
    /// Convenience for SF Symbol icon sizing (respects applied layout metrics).
    static func ttIcon(_ size: CGFloat) -> Font {
        // `size` may already be a scaled TTIcon token; avoid double-scaling when
        // callers pass TTIcon.* (already scaled). Pass-through as-is.
        .system(size: size)
    }
}
