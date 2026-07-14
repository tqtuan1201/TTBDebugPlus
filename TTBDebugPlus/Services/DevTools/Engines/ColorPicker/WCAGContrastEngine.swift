//
//  WCAGContrastEngine.swift
//  TTBDebugPlus
//
//  WCAG 2.x contrast ratio from sRGB components (Foundation only).
//  P0: alpha is ignored (treated as opaque).
//

import Foundation

enum WCAGContrastEngine {

    /// Contrast ratio using relative luminance. Inputs are 0...1 sRGB channels.
    static func contrastRatio(
        fgR: Double, fgG: Double, fgB: Double,
        bgR: Double, bgG: Double, bgB: Double
    ) -> WCAGResult {
        let l1 = relativeLuminance(r: fgR, g: fgG, b: fgB)
        let l2 = relativeLuminance(r: bgR, g: bgG, b: bgB)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        let ratio = (lighter + 0.05) / (darker + 0.05)
        return result(ratio: ratio)
    }

    static func contrastRatio(fg: ColorFormatEngine.RGB, bg: ColorFormatEngine.RGB) -> WCAGResult {
        contrastRatio(fgR: fg.r, fgG: fg.g, fgB: fg.b, bgR: bg.r, bgG: bg.g, bgB: bg.b)
    }

    static func contrastRatio(fg: ColorHSB, bg: ColorHSB) -> WCAGResult {
        contrastRatio(fg: ColorFormatEngine.rgb(from: fg), bg: ColorFormatEngine.rgb(from: bg))
    }

    static func result(ratio: Double) -> WCAGResult {
        WCAGResult(
            ratio: ratio,
            aaNormal: ratio >= 4.5,
            aaLarge: ratio >= 3.0,
            aaaNormal: ratio >= 7.0,
            aaaLarge: ratio >= 4.5
        )
    }

    // MARK: - Luminance

    static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linearize(_ c: Double) -> Double {
            let v = ColorFormatEngine.clamp01(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let R = linearize(r)
        let G = linearize(g)
        let B = linearize(b)
        return 0.2126 * R + 0.7152 * G + 0.0722 * B
    }
}
