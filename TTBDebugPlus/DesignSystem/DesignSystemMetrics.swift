//
//  DesignSystemMetrics.swift
//  TTBDebugPlus
//
//  Pure layout math for typography / spacing scales.
//  No SwiftUI dependency — shared by DesignSystemConfig and unit tests (SPM).
//

import CoreGraphics
import Foundation

// MARK: - Density preset values (HIG-safe)

public enum DesignSystemDensity: String, CaseIterable, Sendable {
    case compact
    case standard // "default" in UI
    case comfortable
    case large

    public var fontScale: CGFloat {
        switch self {
        case .compact: return 0.90
        case .standard: return 1.0
        case .comfortable: return 1.10
        case .large: return 1.15
        }
    }

    public var spacingScale: CGFloat {
        switch self {
        case .compact: return 0.92
        case .standard: return 1.0
        case .comfortable: return 1.08
        case .large: return 1.12
        }
    }

    public var lineHeightExtra: CGFloat {
        switch self {
        case .compact: return 0
        case .standard: return 0
        case .comfortable: return 1
        case .large: return 2
        }
    }
}

// MARK: - Pure metrics

public enum DesignSystemMetrics {
    public static let fontScaleRange: ClosedRange<CGFloat> = 0.85...1.20
    public static let spacingScaleRange: ClosedRange<CGFloat> = 0.90...1.15
    public static let lineHeightExtraRange: ClosedRange<CGFloat> = 0...4

    public static func clampFontScale(_ value: CGFloat) -> CGFloat {
        min(max(value, fontScaleRange.lowerBound), fontScaleRange.upperBound)
    }

    public static func clampSpacingScale(_ value: CGFloat) -> CGFloat {
        min(max(value, spacingScaleRange.lowerBound), spacingScaleRange.upperBound)
    }

    public static func clampLineHeight(_ value: CGFloat) -> CGFloat {
        min(max(value, lineHeightExtraRange.lowerBound), lineHeightExtraRange.upperBound)
    }

    /// Role heuristics from TTFont base sizes — prevent layout blowouts / unreadably small type.
    public static func fontBounds(forBase base: CGFloat) -> ClosedRange<CGFloat> {
        switch base {
        case 28...: // display
            return 24...36
        case 20..<28: // heading1-ish
            return 17...30
        case 15..<20: // heading3 / large body
            return 13...22
        case 13..<15: // body/label large
            return 11...17
        case 12..<13: // code medium / timestamp
            return 10...15
        case 11..<12: // body small / code small / status
            return 10...14
        default: // ≤10 badge / label small
            return 9...12
        }
    }

    public static func scaledFont(base: CGFloat, fontScale: CGFloat) -> CGFloat {
        let scale = clampFontScale(fontScale)
        let scaled = base * scale
        let bounds = fontBounds(forBase: base)
        return min(max(scaled, bounds.lowerBound), bounds.upperBound)
    }

    public static func scaledSpacing(base: CGFloat, spacingScale: CGFloat) -> CGFloat {
        let scale = clampSpacingScale(spacingScale)
        if base <= 0 { return 0 }
        let scaled = base * scale
        return max(1, (scaled * 2).rounded() / 2) // 0.5 pt grid
    }

    public static func scaledIcon(base: CGFloat, fontScale: CGFloat) -> CGFloat {
        let scale = clampFontScale(fontScale)
        let scaled = base * scale
        return min(max(scaled, 7), 24)
    }

    /// Graph / canvas type that also tracks zoom (`nodeScale`) and global font scale.
    public static func graphFontSize(
        base: CGFloat,
        nodeScale: CGFloat,
        fontScale: CGFloat,
        minimum: CGFloat
    ) -> CGFloat {
        let zoomed = base * max(0.5, nodeScale) * clampFontScale(fontScale)
        return max(minimum, zoomed)
    }

    public static func matchingDensity(
        fontScale: CGFloat,
        spacingScale: CGFloat,
        lineHeightExtra: CGFloat
    ) -> DesignSystemDensity? {
        DesignSystemDensity.allCases.first {
            abs($0.fontScale - fontScale) < 0.001
                && abs($0.spacingScale - spacingScale) < 0.001
                && abs($0.lineHeightExtra - lineHeightExtra) < 0.001
        }
    }

    // MARK: - Export / canvas composites (Phase 5)

    /// Combine ImageRenderer/export raster scale with global design metrics.
    /// Result is always positive and finite.
    public static func compositeExportScale(
        exportScale: CGFloat,
        metricScale: CGFloat
    ) -> CGFloat {
        let export = max(0.01, exportScale.isFinite ? exportScale : 1)
        let metric = max(0.01, metricScale.isFinite ? metricScale : 1)
        return export * metric
    }

    /// Annotation / freehand text size: stroke-driven geometry with density-aware floor.
    public static func annotationFontSize(
        lineWidth: CGFloat,
        multiplier: CGFloat,
        minimumBase: CGFloat,
        fontScale: CGFloat
    ) -> CGFloat {
        let floor = scaledFont(base: minimumBase, fontScale: fontScale)
        let geometric = max(0, lineWidth) * multiplier
        return max(floor, geometric)
    }

    /// Suggest a density from a relative accessibility text preference (1.0 = default).
    /// Used when mapping macOS “larger text” style preferences into app density.
    public static func suggestedDensity(forAccessibilityTextScale scale: CGFloat) -> DesignSystemDensity {
        switch scale {
        case ..<0.95: return .compact
        case 0.95..<1.05: return .standard
        case 1.05..<1.12: return .comfortable
        default: return .large
        }
    }
}
