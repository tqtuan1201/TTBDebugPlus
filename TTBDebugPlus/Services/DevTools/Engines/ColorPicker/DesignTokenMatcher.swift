//
//  DesignTokenMatcher.swift
//  TTBDebugPlus
//
//  Hardcoded light-hex snapshot of semantic tokens from Colors.swift.
//  Keep in sync when brand tokens change. Pure Foundation.
//

import Foundation

enum DesignTokenMatcher {

    struct TokenDefinition: Sendable {
        let name: String
        let lightHex: String
    }

    /// Light-scheme semantic tokens (sync with `Colors.swift`).
    static let catalog: [TokenDefinition] = [
        .init(name: ".ttPrimary", lightHex: "#2563EB"),
        .init(name: ".ttPrimaryLight", lightHex: "#3B82F6"),
        .init(name: ".ttPrimaryDark", lightHex: "#1D4ED8"),
        .init(name: ".ttSecondary", lightHex: "#3B82F6"),
        .init(name: ".ttBackground", lightHex: "#F1F5F9"),
        .init(name: ".ttSurface", lightHex: "#FFFFFF"),
        .init(name: ".ttSurfaceLight", lightHex: "#E2E8F0"),
        .init(name: ".ttBorder", lightHex: "#CBD5E1"),
        .init(name: ".ttTextPrimary", lightHex: "#0F172A"),
        .init(name: ".ttTextSecondary", lightHex: "#334155"),
        .init(name: ".ttTextTertiary", lightHex: "#475569"),
        .init(name: ".ttTextMuted", lightHex: "#94A3B8"),
        .init(name: ".ttSuccess", lightHex: "#16A34A"),
        .init(name: ".ttError", lightHex: "#DC2626"),
        .init(name: ".ttWarning", lightHex: "#D97706"),
        .init(name: ".ttInfo", lightHex: "#2563EB"),
        .init(name: ".ttMethodGet", lightHex: "#22C55E"),
        .init(name: ".ttMethodPost", lightHex: "#3B82F6"),
        .init(name: ".ttMethodPut", lightHex: "#F59E0B"),
        .init(name: ".ttMethodDelete", lightHex: "#EF4444"),
        .init(name: ".ttMethodPatch", lightHex: "#A855F7"),
    ]

    private static let maxDistance = sqrt(3.0 * 255.0 * 255.0)

    /// Returns matches with similarity ≥ `minSimilarity`, sorted best-first (max 3).
    static func matches(
        for hsb: ColorHSB,
        minSimilarity: Double = 0.85,
        limit: Int = 3
    ) -> [TokenMatch] {
        let rgb = ColorFormatEngine.rgb(from: hsb)
        let r = Double(ColorFormatEngine.channel255(rgb.r))
        let g = Double(ColorFormatEngine.channel255(rgb.g))
        let b = Double(ColorFormatEngine.channel255(rgb.b))

        var results: [TokenMatch] = []
        for token in catalog {
            guard let tokenRGB = ColorFormatEngine.parseHex(token.lightHex) else { continue }
            let tr = Double(ColorFormatEngine.channel255(tokenRGB.r))
            let tg = Double(ColorFormatEngine.channel255(tokenRGB.g))
            let tb = Double(ColorFormatEngine.channel255(tokenRGB.b))
            let d = sqrt(pow(r - tr, 2) + pow(g - tg, 2) + pow(b - tb, 2))
            let similarity = max(0, min(1, 1 - d / maxDistance))
            if similarity >= minSimilarity {
                results.append(
                    TokenMatch(
                        tokenName: token.name,
                        tokenHex: token.lightHex.uppercased(),
                        similarity: similarity
                    )
                )
            }
        }

        return results
            .sorted { lhs, rhs in
                if abs(lhs.similarity - rhs.similarity) > 0.0001 {
                    return lhs.similarity > rhs.similarity
                }
                return lhs.tokenName < rhs.tokenName
            }
            .prefix(limit)
            .map { $0 }
    }
}
