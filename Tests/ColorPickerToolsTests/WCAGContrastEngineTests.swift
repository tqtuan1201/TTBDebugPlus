//
//  WCAGContrastEngineTests.swift
//  ColorPickerToolsTests
//

import XCTest
@testable import ColorPickerTools

final class WCAGContrastEngineTests: XCTestCase {

    func testBlackOnWhiteIs21() {
        let result = WCAGContrastEngine.contrastRatio(
            fgR: 0, fgG: 0, fgB: 0,
            bgR: 1, bgG: 1, bgB: 1
        )
        XCTAssertEqual(result.ratio, 21.0, accuracy: 0.05)
        XCTAssertTrue(result.aaNormal)
        XCTAssertTrue(result.aaLarge)
        XCTAssertTrue(result.aaaNormal)
        XCTAssertTrue(result.aaaLarge)
    }

    func testLowContrastFailsAANormal() {
        // Light gray on white — typically fails AA normal
        let result = WCAGContrastEngine.contrastRatio(
            fgR: 0.7, fgG: 0.7, fgB: 0.7,
            bgR: 1, bgG: 1, bgB: 1
        )
        XCTAssertLessThan(result.ratio, 4.5)
        XCTAssertFalse(result.aaNormal)
    }
}
