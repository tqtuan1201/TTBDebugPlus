//
//  ColorFormatEngine.swift
//  TTBDebugPlus
//
//  Pure color conversion and developer format strings (Foundation only).
//

import Foundation

enum ColorFormatEngine {

    // MARK: - Parsed RGB

    struct RGB: Equatable, Sendable {
        var r: Double // 0...1
        var g: Double
        var b: Double
        var a: Double
    }

    // MARK: - HSB ↔ RGB

    static func rgb(from hsb: ColorHSB) -> RGB {
        let h = clamp01(hsb.hue)
        let s = clamp01(hsb.saturation)
        let v = clamp01(hsb.brightness)
        let a = clamp01(hsb.alpha)

        if s < 0.0001 {
            return RGB(r: v, g: v, b: v, a: a)
        }

        let sector = h * 6
        let i = Int(sector) % 6
        let f = sector - floor(sector)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))

        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(r: r, g: g, b: b, a: a)
    }

    static func hsb(from rgb: RGB) -> ColorHSB {
        let r = clamp01(rgb.r)
        let g = clamp01(rgb.g)
        let b = clamp01(rgb.b)
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var h: Double = 0
        if delta > 0.0001 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                if h < 0 { h += 6 }
                h /= 6
            } else if maxC == g {
                h = (((b - r) / delta) + 2) / 6
            } else {
                h = (((r - g) / delta) + 4) / 6
            }
        }

        let s = maxC < 0.0001 ? 0 : delta / maxC
        return ColorHSB(hue: clamp01(h), saturation: clamp01(s), brightness: clamp01(maxC), alpha: clamp01(rgb.a))
    }

    // MARK: - Hex parse / format

    /// Accepts #RGB, #RRGGBB, #AARRGGBB, with or without `#`.
    static func parseHex(_ raw: String) -> RGB? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()

        guard cleaned.range(of: "^[0-9A-F]+$", options: .regularExpression) != nil else {
            return nil
        }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        switch cleaned.count {
        case 3:
            let r = Double((value >> 8) & 0xF) * 17 / 255
            let g = Double((value >> 4) & 0xF) * 17 / 255
            let b = Double(value & 0xF) * 17 / 255
            return RGB(r: r, g: g, b: b, a: 1)
        case 6:
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            return RGB(r: r, g: g, b: b, a: 1)
        case 8:
            let a = Double((value >> 24) & 0xFF) / 255
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            return RGB(r: r, g: g, b: b, a: a)
        default:
            return nil
        }
    }

    static func hexString(from rgb: RGB, uppercase: Bool = true) -> String {
        let r = channel255(rgb.r)
        let g = channel255(rgb.g)
        let b = channel255(rgb.b)
        let includeAlpha = rgb.a < 0.999
        let body: String
        if includeAlpha {
            let a = channel255(rgb.a)
            body = String(format: "%02X%02X%02X%02X", a, r, g, b)
        } else {
            body = String(format: "%02X%02X%02X", r, g, b)
        }
        let hex = "#" + body
        return uppercase ? hex : hex.lowercased()
    }

    static func normalizedHex(from hsb: ColorHSB) -> String {
        hexString(from: rgb(from: hsb), uppercase: true)
    }

    // MARK: - Format strings

    static func string(for format: ColorFormat, hsb: ColorHSB) -> String {
        let c = rgb(from: hsb)
        switch format {
        case .hex:
            return hexString(from: c)
        case .rgb:
            return rgbString(c)
        case .hsl:
            return hslString(from: hsb)
        case .swiftUI:
            return swiftUIString(c)
        case .uiColor:
            return uiColorString(c)
        case .nsColor:
            return nsColorString(c)
        case .css:
            return cssString(c)
        }
    }

    static func allFormatsBlock(hsb: ColorHSB) -> String {
        ColorFormat.allCases.map { format in
            "\(format.displayName): \(string(for: format, hsb: hsb))"
        }.joined(separator: "\n")
    }

    // MARK: - Private format helpers

    private static func rgbString(_ c: RGB) -> String {
        let r = channel255(c.r)
        let g = channel255(c.g)
        let b = channel255(c.b)
        if c.a < 0.999 {
            return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, c.a)
        }
        return "rgb(\(r), \(g), \(b))"
    }

    private static func hslString(from hsb: ColorHSB) -> String {
        // Convert HSB to HSL for output
        let s = clamp01(hsb.saturation)
        let v = clamp01(hsb.brightness)
        let l = v * (1 - s / 2)
        let sl: Double
        if l < 0.0001 || l > 0.9999 {
            sl = 0
        } else {
            sl = (v - l) / min(l, 1 - l)
        }
        let hDeg = Int((clamp01(hsb.hue) * 360).rounded()) % 360
        let sPct = Int((sl * 100).rounded())
        let lPct = Int((l * 100).rounded())
        if hsb.alpha < 0.999 {
            return String(format: "hsla(%d, %d%%, %d%%, %.2f)", hDeg, sPct, lPct, hsb.alpha)
        }
        return "hsl(\(hDeg), \(sPct)%, \(lPct)%)"
    }

    private static func swiftUIString(_ c: RGB) -> String {
        let hexBody = hexString(from: RGB(r: c.r, g: c.g, b: c.b, a: 1))
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if c.a < 0.999 {
            return String(
                format: "Color(red: %.3f, green: %.3f, blue: %.3f, opacity: %.2f)",
                c.r, c.g, c.b, c.a
            )
        }
        return "Color(hex: \"\(hexBody)\")"
    }

    private static func uiColorString(_ c: RGB) -> String {
        String(
            format: "UIColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)",
            c.r, c.g, c.b, c.a
        )
    }

    private static func nsColorString(_ c: RGB) -> String {
        String(
            format: "NSColor(srgbRed: %.3f, green: %.3f, blue: %.3f, alpha: %.2f)",
            c.r, c.g, c.b, c.a
        )
    }

    private static func cssString(_ c: RGB) -> String {
        let hex = hexString(from: c, uppercase: false)
        return "color: \(hex);"
    }

    // MARK: - Utils

    static func clamp01(_ v: Double) -> Double {
        min(1, max(0, v))
    }

    static func channel255(_ v: Double) -> Int {
        Int((clamp01(v) * 255).rounded())
    }
}
