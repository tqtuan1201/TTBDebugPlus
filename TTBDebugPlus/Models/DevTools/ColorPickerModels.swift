//
//  ColorPickerModels.swift
//  TTBDebugPlus
//
//  Data models for the Color Picker Dev Tool.
//

import Foundation

// MARK: - Format

enum ColorFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case hex
    case rgb
    case hsl
    case swiftUI
    case uiColor
    case nsColor
    case css

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hex: return "Hex"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftUI: return "SwiftUI"
        case .uiColor: return "UIColor"
        case .nsColor: return "NSColor"
        case .css: return "CSS"
        }
    }
}

// MARK: - Palette

struct PaletteColorEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var hex: String
    var hue: Double
    var saturation: Double
    var brightness: Double
    var alpha: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        hex: String,
        hue: Double,
        saturation: Double,
        brightness: Double,
        alpha: Double = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.hex = hex
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        self.alpha = alpha
        self.createdAt = createdAt
    }
}

// MARK: - Token match

struct TokenMatch: Identifiable, Hashable, Sendable {
    var id: String { tokenName }
    let tokenName: String
    let tokenHex: String
    let similarity: Double
}

// MARK: - WCAG

struct WCAGResult: Equatable, Sendable {
    let ratio: Double
    let aaNormal: Bool
    let aaLarge: Bool
    let aaaNormal: Bool
    let aaaLarge: Bool

    static let empty = WCAGResult(
        ratio: 0,
        aaNormal: false,
        aaLarge: false,
        aaaNormal: false,
        aaaLarge: false
    )
}

// MARK: - HSB components

struct ColorHSB: Equatable, Sendable {
    var hue: Double
    var saturation: Double
    var brightness: Double
    var alpha: Double

    static let `default` = ColorHSB(hue: 0.61, saturation: 0.85, brightness: 0.92, alpha: 1)
}
