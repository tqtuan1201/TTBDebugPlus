//
//  Colors.swift
//  TTBDebugPlus
//
//  Adaptive design tokens for Light + Dark (Apple HIG / WCAG AA).
//  Text hierarchy is calibrated for readable contrast on surfaces — never use
//  muted tokens for primary body copy.
//

import AppKit
import SwiftUI

// MARK: - Adaptive helpers

extension Color {
    /// Dynamic color that switches with the effective appearance (light/dark).
    static func ttAdaptive(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.ttHex(isDark ? dark : light)
        }))
    }

    /// Static (non-adaptive) hex — status accents, charts, syntax.
    static func ttFixed(_ hex: String) -> Color {
        Color(nsColor: NSColor.ttHex(hex))
    }
}

extension NSColor {
    static func ttHex(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return NSColor(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Design Tokens

extension Color {
    // MARK: Brand / Primary (same both schemes — brand blue)

    static let ttPrimary = ttAdaptive(light: "#2563EB", dark: "#3B82F6")
    static let ttPrimaryLight = ttAdaptive(light: "#3B82F6", dark: "#60A5FA")
    static let ttPrimaryDark = ttAdaptive(light: "#1D4ED8", dark: "#2563EB")
    static let ttSecondary = ttAdaptive(light: "#3B82F6", dark: "#60A5FA")

    // MARK: Surfaces (light canvas / dark slate)

    /// App chrome canvas
    static let ttBackground = ttAdaptive(light: "#F1F5F9", dark: "#0F172A")
    /// Elevated cards / panels
    static let ttSurface = ttAdaptive(light: "#FFFFFF", dark: "#1E293B")
    /// Nested / inset surfaces
    static let ttSurfaceLight = ttAdaptive(light: "#E2E8F0", dark: "#334155")
    /// Hover fill
    static let ttSurfaceHover = ttAdaptive(light: "#E8EEF5", dark: "#283548")

    // MARK: Borders

    static let ttBorder = ttAdaptive(light: "#CBD5E1", dark: "#334155")
    static let ttBorderLight = ttAdaptive(light: "#E2E8F0", dark: "#475569")

    // MARK: Text hierarchy (WCAG AA on paired surfaces)
    //
    // Role              | Light on #F1F5F9 / #FFF | Dark on #0F172A / #1E293B | Use for
    // ------------------|-------------------------|---------------------------|------------------
    // ttTextPrimary     | #0F172A (~16:1)         | #F8FAFC (~17:1)           | Body, titles, values
    // ttTextSecondary   | #334155 (~8:1)          | #CBD5E1 (~10:1)           | Meta, timestamps, secondary body
    // ttTextTertiary    | #475569 (~6:1)          | #A8B4C4 (~6:1)            | Labels / chrome only
    // ttTextMuted       | #94A3B8 (~3:1)          | #6B7C90 (~4:1)            | Disabled / decorative ONLY
    // ttTextPlaceholder | #64748B                 | #94A3B8                   | Field placeholders
    // ttTextOnAccent    | #FFFFFF                 | #FFFFFF                   | Text on solid brand/status fills
    // ttTextLink        | brand                   | brand light               | Interactive links
    //
    // Status messaging: ALWAYS use TTBanner / TTStatusPill / banner surface tokens.
    // NEVER pair status accent (ttError/ttWarning/…) as body text on status.opacity(0.1x).

    static let ttTextPrimary = ttAdaptive(light: "#0F172A", dark: "#F8FAFC")
    static let ttTextSecondary = ttAdaptive(light: "#334155", dark: "#CBD5E1")
    /// Labels / chrome — kept ≥ ~5:1 on canvas in both schemes
    static let ttTextTertiary = ttAdaptive(light: "#475569", dark: "#A8B4C4")
    /// Disabled / decorative ONLY — do not use for body copy
    static let ttTextMuted = ttAdaptive(light: "#94A3B8", dark: "#6B7C90")
    /// Field placeholders (slightly stronger than muted for readability)
    static let ttTextPlaceholder = ttAdaptive(light: "#64748B", dark: "#94A3B8")
    /// Text drawn on solid primary / status capsules (always light for contrast).
    static let ttTextOnAccent = ttFixed("#FFFFFF")
    static let ttTextLink = ttPrimary

    // MARK: Semantic status (accent hue; pair with banner surfaces, not as body text on canvas)

    static let ttSuccess = ttAdaptive(light: "#16A34A", dark: "#22C55E")
    static let ttError = ttAdaptive(light: "#DC2626", dark: "#EF4444")
    static let ttWarning = ttAdaptive(light: "#D97706", dark: "#F59E0B")
    static let ttInfo = ttAdaptive(light: "#2563EB", dark: "#3B82F6")

    // MARK: Banner surfaces + on-banner text (high contrast — do NOT use status.opacity(0.12) alone)

    static let ttBannerInfoBackground = ttAdaptive(light: "#DBEAFE", dark: "#1E3A5F")
    static let ttBannerInfoForeground = ttAdaptive(light: "#1E3A8A", dark: "#BFDBFE")
    static let ttBannerInfoBorder = ttAdaptive(light: "#93C5FD", dark: "#3B82F6")

    static let ttBannerSuccessBackground = ttAdaptive(light: "#DCFCE7", dark: "#14532D")
    static let ttBannerSuccessForeground = ttAdaptive(light: "#14532D", dark: "#BBF7D0")
    static let ttBannerSuccessBorder = ttAdaptive(light: "#86EFAC", dark: "#22C55E")

    // Warning: dark fg boosted for AA on brown surfaces (avoids “sunken” amber-on-slate)
    static let ttBannerWarningBackground = ttAdaptive(light: "#FEF3C7", dark: "#451A03")
    static let ttBannerWarningForeground = ttAdaptive(light: "#78350F", dark: "#FEF08C")
    static let ttBannerWarningBorder = ttAdaptive(light: "#F59E0B", dark: "#FBBF24")

    static let ttBannerErrorBackground = ttAdaptive(light: "#FEE2E2", dark: "#450A0A")
    static let ttBannerErrorForeground = ttAdaptive(light: "#7F1D1D", dark: "#FECACA")
    static let ttBannerErrorBorder = ttAdaptive(light: "#F87171", dark: "#F87171")

    // MARK: Connection channel (category axis — Bonjour vs Relay — NOT severity; Phase 9).
    // Same background/foreground/border triad discipline as the banner surfaces above, so
    // `ChannelChip` reads correctly in both Light and Dark instead of a raw `.blue`/`.purple`.

    static let ttChannelBonjourBackground = ttAdaptive(light: "#DBEAFE", dark: "#1E3A5F")
    static let ttChannelBonjourForeground = ttAdaptive(light: "#1E3A8A", dark: "#BFDBFE")
    static let ttChannelBonjourBorder = ttAdaptive(light: "#93C5FD", dark: "#3B82F6")

    static let ttChannelRelayBackground = ttAdaptive(light: "#EDE9FE", dark: "#3B0764")
    static let ttChannelRelayForeground = ttAdaptive(light: "#5B21B6", dark: "#DDD6FE")
    static let ttChannelRelayBorder = ttAdaptive(light: "#C4B5FD", dark: "#A78BFA")

    static let ttChannelRelayRemoteBackground = ttAdaptive(light: "#F3E8FF", dark: "#2E1065")
    static let ttChannelRelayRemoteForeground = ttAdaptive(light: "#7E22CE", dark: "#E9D5FF")
    static let ttChannelRelayRemoteBorder = ttAdaptive(light: "#D8B4FE", dark: "#C084FC")

    // MARK: HTTP / JSON / Logs (fixed hues — ok on both schemes with care)

    static let ttMethodGet = ttFixed("#22C55E")
    static let ttMethodPost = ttFixed("#3B82F6")
    static let ttMethodPut = ttFixed("#F59E0B")
    static let ttMethodDelete = ttFixed("#EF4444")
    static let ttMethodPatch = ttFixed("#A855F7")

    static let ttStatus2xx = ttFixed("#22C55E")
    static let ttStatus3xx = ttFixed("#3B82F6")
    static let ttStatus4xx = ttFixed("#F59E0B")
    static let ttStatus5xx = ttFixed("#EF4444")

    static let ttJsonKey = ttAdaptive(light: "#2563EB", dark: "#60A5FA")
    static let ttJsonString = ttAdaptive(light: "#C2410C", dark: "#FB923C")
    static let ttJsonNumber = ttAdaptive(light: "#15803D", dark: "#4ADE80")
    static let ttJsonBool = ttAdaptive(light: "#7E22CE", dark: "#C084FC")
    static let ttJsonNull = ttTextTertiary
    static let ttJsonBrace = ttTextTertiary

    static let ttLogError = ttError
    static let ttLogWarning = ttWarning
    static let ttLogInfo = ttInfo
    static let ttLogDebug = ttTextMuted

    // Legacy light aliases (map to adaptive surfaces for callers still using names)
    static let ttLightBackground = ttBackground
    static let ttLightSurface = ttSurface
    static let ttLightBorder = ttBorder

    // MARK: Hex Color Init (static — prefer ttAdaptive / ttFixed for tokens)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Status helpers

extension Color {
    static func forStatusCode(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .ttStatus2xx
        case 300..<400: return .ttStatus3xx
        case 400..<500: return .ttStatus4xx
        case 500..<600: return .ttStatus5xx
        default: return .ttTextSecondary
        }
    }

    static func forHTTPMethod(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .ttMethodGet
        case "POST": return .ttMethodPost
        case "PUT": return .ttMethodPut
        case "DELETE": return .ttMethodDelete
        case "PATCH": return .ttMethodPatch
        default: return .ttTextSecondary
        }
    }

    static func forLogLevel(_ level: String) -> Color {
        switch level.lowercased() {
        case "error": return .ttLogError
        case "warning": return .ttLogWarning
        case "info": return .ttLogInfo
        case "debug": return .ttLogDebug
        default: return .ttTextSecondary
        }
    }

    private static let deviceColorPalette: [Color] = [
        ttFixed("#06B6D4"),
        ttFixed("#F97316"),
        ttFixed("#A855F7"),
        ttFixed("#EC4899"),
        ttFixed("#14B8A6"),
        ttFixed("#6366F1"),
        ttFixed("#84CC16"),
        ttFixed("#F43F5E"),
    ]

    static func forDevice(_ deviceId: String) -> Color {
        var hash: UInt64 = 5381
        for char in deviceId.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(char)
        }
        return deviceColorPalette[Int(hash % UInt64(deviceColorPalette.count))]
    }

    /// Alternating row — adaptive subtle tint
    static let ttRowAlternate = ttAdaptive(light: "#E2E8F0", dark: "#1E293B").opacity(0.45)
}

// MARK: - Opacity Tokens

enum TTOpacity {
    static let subtle: Double = 0.03
    static let faint: Double = 0.08
    static let light: Double = 0.12
    static let medium: Double = 0.15
    static let border: Double = 0.3
    static let strong: Double = 0.5
    static let heavy: Double = 0.6
    static let surface: Double = 0.75
}

// MARK: - Interactive text state colors

enum TTTextState {
    /// Default readable body
    static let primary = Color.ttTextPrimary
    /// Supporting / secondary
    static let secondary = Color.ttTextSecondary
    /// Idle chrome / column labels
    static let tertiary = Color.ttTextTertiary
    /// Disabled controls only
    static let disabled = Color.ttTextMuted
    /// Placeholder in fields
    static let placeholder = Color.ttTextPlaceholder
    /// Selected accent (tabs, active filters)
    static let selected = Color.ttPrimary
    /// Hover emphasis (same as primary on most canvases)
    static let hover = Color.ttTextPrimary
    /// On filled brand/status buttons
    static let onAccent = Color.ttTextOnAccent
}
