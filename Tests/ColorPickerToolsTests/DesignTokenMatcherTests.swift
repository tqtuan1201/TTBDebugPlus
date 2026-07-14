//
//  DesignTokenMatcherTests.swift
//  ColorPickerToolsTests
//

import XCTest
@testable import ColorPickerTools

final class DesignTokenMatcherTests: XCTestCase {

    func testExactPrimaryMatch() {
        guard let rgb = ColorFormatEngine.parseHex("#2563EB") else {
            return XCTFail("parse failed")
        }
        let hsb = ColorFormatEngine.hsb(from: rgb)
        let matches = DesignTokenMatcher.matches(for: hsb)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.contains(where: { $0.tokenName == ".ttPrimary" }))
        if let best = matches.first {
            XCTAssertGreaterThanOrEqual(best.similarity, 0.99)
        }
    }

    func testFarColorMayHaveNoMatch() {
        // Highly saturated magenta unlikely near catalog
        let hsb = ColorHSB(hue: 0.9, saturation: 1, brightness: 1, alpha: 1)
        let matches = DesignTokenMatcher.matches(for: hsb, minSimilarity: 0.95)
        // Soft assertion: either empty or low count; primary goal is no crash
        XCTAssertLessThanOrEqual(matches.count, 3)
    }
}
