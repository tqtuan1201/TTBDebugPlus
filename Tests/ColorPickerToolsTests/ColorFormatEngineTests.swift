//
//  ColorFormatEngineTests.swift
//  ColorPickerToolsTests
//

import XCTest
@testable import ColorPickerTools

final class ColorFormatEngineTests: XCTestCase {

    func testParseHexRRGGBB() {
        let rgb = ColorFormatEngine.parseHex("#2563EB")
        XCTAssertNotNil(rgb)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.r), 37)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.g), 99)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.b), 235)
        XCTAssertEqual(rgb!.a, 1, accuracy: 0.001)
    }

    func testParseHexWithoutHash() {
        let rgb = ColorFormatEngine.parseHex("2563EB")
        XCTAssertNotNil(rgb)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.r), 37)
    }

    func testParseHexShort() {
        let rgb = ColorFormatEngine.parseHex("#FFF")
        XCTAssertNotNil(rgb)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.r), 255)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.g), 255)
        XCTAssertEqual(ColorFormatEngine.channel255(rgb!.b), 255)
    }

    func testParseHexInvalid() {
        XCTAssertNil(ColorFormatEngine.parseHex("not-a-color"))
        XCTAssertNil(ColorFormatEngine.parseHex("#GG0000"))
    }

    func testHexStringFromRGB() {
        let rgb = ColorFormatEngine.RGB(r: 37.0 / 255, g: 99.0 / 255, b: 235.0 / 255, a: 1)
        XCTAssertEqual(ColorFormatEngine.hexString(from: rgb), "#2563EB")
    }

    func testRGBString() {
        guard let rgb = ColorFormatEngine.parseHex("#2563EB") else {
            return XCTFail("parse failed")
        }
        let hsb = ColorFormatEngine.hsb(from: rgb)
        let s = ColorFormatEngine.string(for: .rgb, hsb: hsb)
        XCTAssertEqual(s, "rgb(37, 99, 235)")
    }

    func testSwiftUIHexForm() {
        guard let rgb = ColorFormatEngine.parseHex("#2563EB") else {
            return XCTFail("parse failed")
        }
        let hsb = ColorFormatEngine.hsb(from: rgb)
        let s = ColorFormatEngine.string(for: .swiftUI, hsb: hsb)
        XCTAssertTrue(s.contains("Color(hex:"))
        XCTAssertTrue(s.contains("2563EB"))
    }

    func testUIColorAndNSColorStrings() {
        guard let rgb = ColorFormatEngine.parseHex("#2563EB") else {
            return XCTFail("parse failed")
        }
        let hsb = ColorFormatEngine.hsb(from: rgb)
        XCTAssertTrue(ColorFormatEngine.string(for: .uiColor, hsb: hsb).contains("UIColor(red:"))
        XCTAssertTrue(ColorFormatEngine.string(for: .nsColor, hsb: hsb).contains("NSColor(srgbRed:"))
    }

    func testHSBRoundTrip() {
        let original = ColorHSB(hue: 0.6, saturation: 1, brightness: 1, alpha: 1)
        let rgb = ColorFormatEngine.rgb(from: original)
        let back = ColorFormatEngine.hsb(from: rgb)
        XCTAssertEqual(back.hue, original.hue, accuracy: 0.02)
        XCTAssertEqual(back.saturation, original.saturation, accuracy: 0.02)
        XCTAssertEqual(back.brightness, original.brightness, accuracy: 0.02)
    }
}
