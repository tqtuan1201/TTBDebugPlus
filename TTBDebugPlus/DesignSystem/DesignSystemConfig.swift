//
//  DesignSystemConfig.swift
//  TTBDebugPlus
//
//  Runtime typography & spacing metrics.
//  Applied values drive TTFont / TTSpacing / TTIcon; Settings edits draft until Apply.
//  Pure math lives in DesignSystemMetrics (unit-tested via SPM).
//

import Foundation
import SwiftUI

// MARK: - Text emphasis

enum TTTextEmphasis: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return "Regular"
        case .medium: return "Medium"
        }
    }
}

// MARK: - Density presets (UI layer over DesignSystemDensity)

enum TTDensityPreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case `default`
    case comfortable
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .default: return "Default"
        case .comfortable: return "Comfortable"
        case .large: return "Large"
        }
    }

    var detail: String {
        switch self {
        case .compact: return "Denser chrome for tool-heavy layouts"
        case .default: return "Baseline design system (1.0)"
        case .comfortable: return "Slightly larger type and gaps"
        case .large: return "Maximum readability within safe clamps"
        }
    }

    var metricsDensity: DesignSystemDensity {
        switch self {
        case .compact: return .compact
        case .default: return .standard
        case .comfortable: return .comfortable
        case .large: return .large
        }
    }

    var fontScale: CGFloat { metricsDensity.fontScale }
    var spacingScale: CGFloat { metricsDensity.spacingScale }
    var lineHeightExtra: CGFloat { metricsDensity.lineHeightExtra }

    static func from(metrics: DesignSystemDensity) -> TTDensityPreset {
        switch metrics {
        case .compact: return .compact
        case .standard: return .default
        case .comfortable: return .comfortable
        case .large: return .large
        }
    }
}

// MARK: - Config

/// Single source of truth for applied layout metrics. Injected via environment;
/// `TTFont` / `TTSpacing` read `shared` so existing call sites stay unchanged.
/// Bump `appliedRevision` on Apply so root views re-render.
@Observable
final class DesignSystemConfig {
    static let shared = DesignSystemConfig()

    // MARK: Limits (forwarded from pure metrics)

    static let fontScaleRange = DesignSystemMetrics.fontScaleRange
    static let spacingScaleRange = DesignSystemMetrics.spacingScaleRange
    static let lineHeightExtraRange = DesignSystemMetrics.lineHeightExtraRange

    // MARK: Persistence keys

    private enum Keys {
        static let fontScale = "ttFontScale"
        static let spacingScale = "ttSpacingScale"
        static let lineHeightExtra = "ttLineHeightExtra"
        static let textEmphasis = "ttTextEmphasis"
    }

    // MARK: Applied metrics

    private(set) var fontScale: CGFloat
    private(set) var spacingScale: CGFloat
    private(set) var lineHeightExtra: CGFloat
    private(set) var textEmphasis: TTTextEmphasis
    /// Incremented on every successful Apply / Reset so SwiftUI can force refresh.
    private(set) var appliedRevision: Int = 0

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedFont = defaults.object(forKey: Keys.fontScale) as? Double
        let storedSpacing = defaults.object(forKey: Keys.spacingScale) as? Double
        let storedLine = defaults.object(forKey: Keys.lineHeightExtra) as? Double
        let storedEmphasis = defaults.string(forKey: Keys.textEmphasis)

        fontScale = DesignSystemMetrics.clampFontScale(CGFloat(storedFont ?? 1.0))
        spacingScale = DesignSystemMetrics.clampSpacingScale(CGFloat(storedSpacing ?? 1.0))
        lineHeightExtra = DesignSystemMetrics.clampLineHeight(CGFloat(storedLine ?? 0))
        textEmphasis = TTTextEmphasis(rawValue: storedEmphasis ?? "") ?? .regular
    }

    /// Test / preview helper — isolated UserDefaults suite (does not touch `shared`).
    static func makeIsolated(suiteName: String = "ttb.designsystem.tests") -> DesignSystemConfig {
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return DesignSystemConfig(defaults: suite)
    }

    // MARK: Apply / Reset

    func apply(
        fontScale: CGFloat,
        spacingScale: CGFloat,
        lineHeightExtra: CGFloat,
        textEmphasis: TTTextEmphasis
    ) {
        self.fontScale = DesignSystemMetrics.clampFontScale(fontScale)
        self.spacingScale = DesignSystemMetrics.clampSpacingScale(spacingScale)
        self.lineHeightExtra = DesignSystemMetrics.clampLineHeight(lineHeightExtra)
        self.textEmphasis = textEmphasis
        persist()
        appliedRevision &+= 1
    }

    func applyPreset(_ preset: TTDensityPreset, textEmphasis: TTTextEmphasis? = nil) {
        apply(
            fontScale: preset.fontScale,
            spacingScale: preset.spacingScale,
            lineHeightExtra: preset.lineHeightExtra,
            textEmphasis: textEmphasis ?? self.textEmphasis
        )
    }

    func resetToDefault() {
        apply(
            fontScale: TTDensityPreset.default.fontScale,
            spacingScale: TTDensityPreset.default.spacingScale,
            lineHeightExtra: TTDensityPreset.default.lineHeightExtra,
            textEmphasis: .regular
        )
    }

    // MARK: Scaling helpers

    func scaledFont(_ base: CGFloat) -> CGFloat {
        DesignSystemMetrics.scaledFont(base: base, fontScale: fontScale)
    }

    /// Same clamps as `scaledFont`, but with an explicit scale (Settings draft preview).
    func scaledFontPreview(base: CGFloat, fontScale: CGFloat) -> CGFloat {
        DesignSystemMetrics.scaledFont(base: base, fontScale: fontScale)
    }

    func scaledSpacing(_ base: CGFloat) -> CGFloat {
        DesignSystemMetrics.scaledSpacing(base: base, spacingScale: spacingScale)
    }

    func scaledIcon(_ base: CGFloat) -> CGFloat {
        DesignSystemMetrics.scaledIcon(base: base, fontScale: fontScale)
    }

    /// JSON graph / zoomable canvas type size.
    func graphFontSize(base: CGFloat, nodeScale: CGFloat, minimum: CGFloat) -> CGFloat {
        DesignSystemMetrics.graphFontSize(
            base: base,
            nodeScale: nodeScale,
            fontScale: fontScale,
            minimum: minimum
        )
    }

    /// Export footer / ImageRenderer: raster `exportScale` × applied font scale.
    func exportFontScale(exportScale: CGFloat) -> CGFloat {
        DesignSystemMetrics.compositeExportScale(exportScale: exportScale, metricScale: fontScale)
    }

    /// Export footer / ImageRenderer: raster `exportScale` × applied spacing scale.
    func exportSpacingScale(exportScale: CGFloat) -> CGFloat {
        DesignSystemMetrics.compositeExportScale(exportScale: exportScale, metricScale: spacingScale)
    }

    /// Annotation text / step counters with density-aware minimum.
    func annotationFontSize(lineWidth: CGFloat, multiplier: CGFloat, minimumBase: CGFloat) -> CGFloat {
        DesignSystemMetrics.annotationFontSize(
            lineWidth: lineWidth,
            multiplier: multiplier,
            minimumBase: minimumBase,
            fontScale: fontScale
        )
    }

    /// Optional weight lift when Text Emphasis = Medium (hierarchy preserved, clamped at bold).
    func emphasisWeight(_ base: Font.Weight) -> Font.Weight {
        guard textEmphasis == .medium else { return base }
        if base == .ultraLight { return .thin }
        if base == .thin { return .light }
        if base == .light { return .regular }
        if base == .regular { return .medium }
        if base == .medium { return .semibold }
        if base == .semibold { return .bold }
        if base == .bold { return .bold }
        if base == .heavy { return .heavy }
        if base == .black { return .black }
        return base
    }

    func matchingPreset() -> TTDensityPreset? {
        DesignSystemMetrics.matchingDensity(
            fontScale: fontScale,
            spacingScale: spacingScale,
            lineHeightExtra: lineHeightExtra
        ).map(TTDensityPreset.from(metrics:))
    }

    // MARK: Private

    private func persist() {
        defaults.set(Double(fontScale), forKey: Keys.fontScale)
        defaults.set(Double(spacingScale), forKey: Keys.spacingScale)
        defaults.set(Double(lineHeightExtra), forKey: Keys.lineHeightExtra)
        defaults.set(textEmphasis.rawValue, forKey: Keys.textEmphasis)
    }
}
