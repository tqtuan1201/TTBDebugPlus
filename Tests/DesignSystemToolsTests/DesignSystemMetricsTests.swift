//
//  DesignSystemMetricsTests.swift
//  DesignSystemToolsTests
//
//  Phase 4 — pure metrics: clamps, density presets, font/spacing scale, graph sizes.
//

import XCTest
@testable import DesignSystemTools

final class DesignSystemMetricsTests: XCTestCase {

    // MARK: - Clamps

    func testFontScaleClamp() {
        XCTAssertEqual(DesignSystemMetrics.clampFontScale(0.5), 0.85, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemMetrics.clampFontScale(1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemMetrics.clampFontScale(2.0), 1.20, accuracy: 0.0001)
    }

    func testSpacingScaleClamp() {
        XCTAssertEqual(DesignSystemMetrics.clampSpacingScale(0.5), 0.90, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemMetrics.clampSpacingScale(1.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemMetrics.clampSpacingScale(1.5), 1.15, accuracy: 0.0001)
    }

    func testLineHeightClamp() {
        XCTAssertEqual(DesignSystemMetrics.clampLineHeight(-2), 0, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemMetrics.clampLineHeight(2), 2, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemMetrics.clampLineHeight(10), 4, accuracy: 0.0001)
    }

    // MARK: - Density presets (HIG matrix)

    func testDensityPresetsWithinSafeRanges() {
        for density in DesignSystemDensity.allCases {
            XCTAssertTrue(
                DesignSystemMetrics.fontScaleRange.contains(density.fontScale),
                "\(density) fontScale out of range"
            )
            XCTAssertTrue(
                DesignSystemMetrics.spacingScaleRange.contains(density.spacingScale),
                "\(density) spacingScale out of range"
            )
            XCTAssertTrue(
                DesignSystemMetrics.lineHeightExtraRange.contains(density.lineHeightExtra),
                "\(density) lineHeight out of range"
            )
        }
    }

    func testStandardDensityIsBaseline() {
        XCTAssertEqual(DesignSystemDensity.standard.fontScale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemDensity.standard.spacingScale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(DesignSystemDensity.standard.lineHeightExtra, 0, accuracy: 0.0001)
    }

    func testMatchingDensity() {
        let d = DesignSystemDensity.comfortable
        let match = DesignSystemMetrics.matchingDensity(
            fontScale: d.fontScale,
            spacingScale: d.spacingScale,
            lineHeightExtra: d.lineHeightExtra
        )
        XCTAssertEqual(match, .comfortable)

        let custom = DesignSystemMetrics.matchingDensity(
            fontScale: 1.03,
            spacingScale: 1.0,
            lineHeightExtra: 0
        )
        XCTAssertNil(custom)
    }

    // MARK: - Scaled font (default scale preserves base within bounds)

    func testScaledFontDefaultPreservesBody() {
        let size = DesignSystemMetrics.scaledFont(base: 13, fontScale: 1.0)
        XCTAssertEqual(size, 13, accuracy: 0.001)
    }

    func testScaledFontCompactStillReadableBadge() {
        let size = DesignSystemMetrics.scaledFont(base: 10, fontScale: 0.90)
        // 10 * 0.9 = 9, within badge bounds 9...12
        XCTAssertGreaterThanOrEqual(size, 9)
        XCTAssertLessThanOrEqual(size, 12)
    }

    func testScaledFontLargeDoesNotBlowDisplay() {
        let size = DesignSystemMetrics.scaledFont(base: 32, fontScale: 1.20)
        // bounds for display ≥28: 24...36
        XCTAssertLessThanOrEqual(size, 36)
        XCTAssertGreaterThanOrEqual(size, 24)
    }

    func testScaledFontExtremeScaleClamped() {
        let huge = DesignSystemMetrics.scaledFont(base: 13, fontScale: 5.0)
        let tiny = DesignSystemMetrics.scaledFont(base: 13, fontScale: 0.1)
        XCTAssertLessThanOrEqual(huge, 17) // body/label large upper
        XCTAssertGreaterThanOrEqual(tiny, 11) // body/label large lower
    }

    // MARK: - Spacing

    func testScaledSpacingDefault() {
        XCTAssertEqual(DesignSystemMetrics.scaledSpacing(base: 8, spacingScale: 1.0), 8, accuracy: 0.001)
        XCTAssertEqual(DesignSystemMetrics.scaledSpacing(base: 16, spacingScale: 1.0), 16, accuracy: 0.001)
    }

    func testScaledSpacingNeverCollapsesPositive() {
        let v = DesignSystemMetrics.scaledSpacing(base: 2, spacingScale: 0.90)
        XCTAssertGreaterThanOrEqual(v, 1)
    }

    func testScaledSpacingZeroStaysZero() {
        XCTAssertEqual(DesignSystemMetrics.scaledSpacing(base: 0, spacingScale: 1.12), 0, accuracy: 0.001)
    }

    func testScaledSpacingHalfPointGrid() {
        // 12 * 1.08 = 12.96 → rounds to 13.0 on 0.5 grid? (12.96*2)=25.92 → 26/2 = 13
        let v = DesignSystemMetrics.scaledSpacing(base: 12, spacingScale: 1.08)
        XCTAssertEqual(v * 2, (v * 2).rounded(), accuracy: 0.001)
    }

    // MARK: - Icons

    func testScaledIconClamps() {
        let small = DesignSystemMetrics.scaledIcon(base: 7, fontScale: 0.85)
        let large = DesignSystemMetrics.scaledIcon(base: 20, fontScale: 1.20)
        XCTAssertGreaterThanOrEqual(small, 7)
        XCTAssertLessThanOrEqual(large, 24)
    }

    // MARK: - Graph / zoom

    func testGraphFontSizeRespectsMinimumAndZoom() {
        let s = DesignSystemMetrics.graphFontSize(
            base: 10,
            nodeScale: 0.5,
            fontScale: 1.0,
            minimum: 9
        )
        // 10 * 0.5 * 1.0 = 5 → min 9
        XCTAssertEqual(s, 9, accuracy: 0.001)
    }

    func testGraphFontSizeTracksGlobalFontScale() {
        let base = DesignSystemMetrics.graphFontSize(
            base: 10, nodeScale: 1.0, fontScale: 1.0, minimum: 8
        )
        let large = DesignSystemMetrics.graphFontSize(
            base: 10, nodeScale: 1.0, fontScale: 1.15, minimum: 8
        )
        XCTAssertEqual(base, 10, accuracy: 0.001)
        XCTAssertEqual(large, 11.5, accuracy: 0.001)
        XCTAssertGreaterThan(large, base)
    }

    // MARK: - Font bounds roles

    func testFontBoundsRoles() {
        XCTAssertEqual(DesignSystemMetrics.fontBounds(forBase: 32).upperBound, 36)
        XCTAssertEqual(DesignSystemMetrics.fontBounds(forBase: 13).lowerBound, 11)
        XCTAssertEqual(DesignSystemMetrics.fontBounds(forBase: 10).lowerBound, 9)
    }

    // MARK: - Phase 5: export / annotation / a11y density

    func testCompositeExportScale() {
        XCTAssertEqual(
            DesignSystemMetrics.compositeExportScale(exportScale: 2.0, metricScale: 1.10),
            2.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            DesignSystemMetrics.compositeExportScale(exportScale: 0, metricScale: 1.0),
            0.01,
            accuracy: 0.0001
        )
    }

    func testAnnotationFontSizeUsesFloorAndGeometry() {
        // Thin stroke → floor at scaled minimum
        let thin = DesignSystemMetrics.annotationFontSize(
            lineWidth: 1, multiplier: 3.5, minimumBase: 11, fontScale: 1.0
        )
        XCTAssertEqual(thin, 11, accuracy: 0.001)

        // Thick stroke → geometric size wins
        let thick = DesignSystemMetrics.annotationFontSize(
            lineWidth: 8, multiplier: 3.5, minimumBase: 11, fontScale: 1.0
        )
        XCTAssertEqual(thick, 28, accuracy: 0.001)

        // Comfortable density raises the floor
        let floorLarge = DesignSystemMetrics.annotationFontSize(
            lineWidth: 1, multiplier: 3.5, minimumBase: 11, fontScale: 1.15
        )
        XCTAssertGreaterThan(floorLarge, 11)
    }

    func testSuggestedDensityFromAccessibilityScale() {
        XCTAssertEqual(DesignSystemMetrics.suggestedDensity(forAccessibilityTextScale: 0.9), .compact)
        XCTAssertEqual(DesignSystemMetrics.suggestedDensity(forAccessibilityTextScale: 1.0), .standard)
        XCTAssertEqual(DesignSystemMetrics.suggestedDensity(forAccessibilityTextScale: 1.08), .comfortable)
        XCTAssertEqual(DesignSystemMetrics.suggestedDensity(forAccessibilityTextScale: 1.2), .large)
    }
}
