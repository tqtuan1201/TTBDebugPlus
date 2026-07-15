//
//  TTBanner.swift
//  TTBDebugPlus
//
//  High-contrast inline message banner (info / success / warning / error).
//  Use this instead of ad-hoc `statusColor.opacity(0.12)` + status-colored text,
//  which fails Light/Dark contrast and looks “sunken”.
//

import SwiftUI

// MARK: - Kind

enum TTBannerKind: String, CaseIterable {
    case info
    case success
    case warning
    case error

    var background: Color {
        switch self {
        case .info: return .ttBannerInfoBackground
        case .success: return .ttBannerSuccessBackground
        case .warning: return .ttBannerWarningBackground
        case .error: return .ttBannerErrorBackground
        }
    }

    var foreground: Color {
        switch self {
        case .info: return .ttBannerInfoForeground
        case .success: return .ttBannerSuccessForeground
        case .warning: return .ttBannerWarningForeground
        case .error: return .ttBannerErrorForeground
        }
    }

    var border: Color {
        switch self {
        case .info: return .ttBannerInfoBorder
        case .success: return .ttBannerSuccessBorder
        case .warning: return .ttBannerWarningBorder
        case .error: return .ttBannerErrorBorder
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Banner

struct TTBanner: View {
    let kind: TTBannerKind
    let message: String
    var title: String? = nil
    var iconVisible: Bool = true
    /// Optional trailing control (e.g. dismiss, action button).
    var trailing: AnyView? = nil

    init(
        kind: TTBannerKind,
        message: String,
        title: String? = nil,
        iconVisible: Bool = true,
        trailing: AnyView? = nil
    ) {
        self.kind = kind
        self.message = message
        self.title = title
        self.iconVisible = iconVisible
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: TTSpacing.inputPaddingH) {
            if iconVisible {
                Image(systemName: kind.icon)
                    .font(.ttIcon(TTIcon.xl))
                    .fontWeight(.semibold)
                    .foregroundColor(kind.foreground)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: TTSpacing.inlineGapSmall) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(TTFont.labelMedium)
                        .foregroundColor(kind.foreground)
                }
                Text(message)
                    .font(TTFont.bodySmall)
                    .foregroundColor(kind.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            if let trailing {
                trailing
            }
        }
        .padding(.leading, TTSpacing.chromeInsetH)
        .padding(.trailing, TTSpacing.md)
        .padding(.vertical, TTSpacing.chromeInsetV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.sm)
                .fill(kind.background)
        )
        .overlay(alignment: .leading) {
            // High-visibility leading accent (prevents “flat sunk” bars)
            Rectangle()
                .fill(kind.border)
                .frame(width: 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: TTRadius.sm)
                .stroke(kind.border.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TTRadius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.map { "\($0). \(message)" } ?? message)
    }
}

// MARK: - Status pill (readable on both schemes)

struct TTStatusPill: View {
    let text: String
    var kind: TTBannerKind = .info
    /// When true, use solid accent fill + on-accent text (for filled chips).
    var solid: Bool = false
    var showsDot: Bool = false

    var body: some View {
        HStack(spacing: TTSpacing.tight) {
            if showsDot {
                Circle()
                    .fill(solid ? Color.ttTextOnAccent : kind.border)
                    .frame(width: TTSpacing.xs, height: TTSpacing.xs)
            }
            Text(text)
                .font(TTFont.badge)
                .foregroundColor(solid ? .ttTextOnAccent : kind.foreground)
        }
        .padding(.horizontal, TTSpacing.badgePaddingH)
        .padding(.vertical, TTSpacing.xxs)
        .background(
            Capsule()
                .fill(solid ? kind.border : kind.background)
                .overlay(
                    Capsule()
                        .stroke(kind.border.opacity(solid ? 0 : 0.65), lineWidth: 1)
                )
        )
        .accessibilityLabel(text)
    }
}

// MARK: - Soft semantic chip (icons + short labels)

/// Icon + optional label using banner surfaces (never status.opacity(0.12) alone).
struct TTSemanticChip: View {
    let kind: TTBannerKind
    var icon: String? = nil
    var label: String? = nil
    var solid: Bool = false

    var body: some View {
        HStack(spacing: TTSpacing.tight) {
            if let icon {
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.md))
                    .fontWeight(.semibold)
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(TTFont.badge)
            }
        }
        .foregroundColor(solid ? .ttTextOnAccent : kind.foreground)
        .padding(.horizontal, label == nil ? TTSpacing.xs : TTSpacing.badgePaddingH)
        .padding(.vertical, TTSpacing.xxs)
        .background(
            Capsule()
                .fill(solid ? kind.border : kind.background)
                .overlay(
                    Capsule()
                        .stroke(kind.border.opacity(solid ? 0 : 0.55), lineWidth: 1)
                )
        )
    }
}

// MARK: - Connection Channel Chip (Phase 9)

/// Bonjour / Relay / Relay Remote indicator — same capsule/padding/font language as
/// `TTSemanticChip` for visual consistency, but takes its own color triad instead of
/// `TTBannerKind` since connection channel is a CATEGORY axis (which path), not a SEVERITY
/// axis (is something wrong) — forcing it through `.info`/`.warning`/etc would be semantically
/// wrong even where the hues happen to look similar.
struct ChannelChip: View {
    let channel: ConnectionChannel
    /// `.compact` (icon + short label, e.g. "Relay") fits a sidebar row. `.full` (icon + full
    /// sentence, e.g. "Relay (Relay nội bộ)") is for places with room to actually explain —
    /// Connection Health cards, not list rows.
    var style: Style = .compact
    enum Style { case compact, full }

    private var colors: (background: Color, foreground: Color, border: Color) {
        switch channel {
        case .bonjour:
            return (.ttChannelBonjourBackground, .ttChannelBonjourForeground, .ttChannelBonjourBorder)
        case .relay(let isRemoteView):
            return isRemoteView
                ? (.ttChannelRelayRemoteBackground, .ttChannelRelayRemoteForeground, .ttChannelRelayRemoteBorder)
                : (.ttChannelRelayBackground, .ttChannelRelayForeground, .ttChannelRelayBorder)
        }
    }

    var body: some View {
        HStack(spacing: TTSpacing.tight) {
            Image(systemName: channel.badgeIcon)
                .font(.ttIcon(TTIcon.sm))
                .fontWeight(.semibold)
            Text(style == .compact ? channel.badgeLabel : channel.fullDescription)
                .font(TTFont.badge)
        }
        .foregroundColor(colors.foreground)
        .padding(.horizontal, TTSpacing.badgePaddingH)
        .padding(.vertical, TTSpacing.xxs)
        .background(
            Capsule()
                .fill(colors.background)
                .overlay(
                    Capsule()
                        .stroke(colors.border.opacity(0.65), lineWidth: 1)
                )
        )
        .accessibilityLabel(channel.fullDescription)
        .help(channel.fullDescription)
    }
}

// MARK: - Convenience

extension TTBannerKind {
    /// Map HTTP / log / runtime semantics to a banner kind.
    static func fromLogLevel(_ level: String) -> TTBannerKind {
        switch level.lowercased() {
        case "error": return .error
        case "warning": return .warning
        case "info": return .info
        default: return .info
        }
    }

    static func fromStatusCode(_ code: Int) -> TTBannerKind {
        switch code {
        case 200..<300: return .success
        case 300..<400: return .info
        case 400..<500: return .warning
        case 500..<600: return .error
        default: return .info
        }
    }

    /// Prefer explicit `TTBannerKind` at call sites; this is a fallback only.
    static func fromStatusColor(_ color: Color) -> TTBannerKind {
        .warning
    }
}
