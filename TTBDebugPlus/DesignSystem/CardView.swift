//
//  CardView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//

import SwiftUI

// MARK: - Card Container
struct CardView<Content: View>: View {
    var title: String? = nil
    var titleTrailing: AnyView? = nil
    var padding: CGFloat = TTSpacing.cardPadding
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: TTSpacing.md) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(TTFont.sidebarHeader)
                        .foregroundColor(.ttTextSecondary)
                        .tracking(1.2)
                    
                    Spacer()
                    
                    if let trailing = titleTrailing {
                        trailing
                    }
                }
            }
            
            content()
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.lg)
                .fill(Color.ttSurface.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.lg)
                        .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: TTSpacing.xs, y: TTSpacing.inlineGapSmall)
        )
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    var color: Color = .ttSuccess
    /// Preferred: high-contrast soft surfaces via `TTBannerKind` (Light/Dark safe).
    var kind: TTBannerKind? = nil
    var style: BadgeStyle = .filled
    
    enum BadgeStyle {
        case filled, outlined, soft, dot
    }
    
    var body: some View {
        switch style {
        case .filled:
            Text(text)
                .font(TTFont.badge)
                .foregroundColor(.ttTextOnAccent)
                .padding(.horizontal, TTSpacing.badgePaddingH)
                .padding(.vertical, TTSpacing.badgePaddingV)
                .background(
                    Capsule().fill(kind?.border ?? color)
                )
            
        case .outlined:
            // Soft fill + strong fg (never bare accent stroke alone on canvas)
            Text(text)
                .font(TTFont.badge)
                .foregroundColor(kind?.foreground ?? color)
                .padding(.horizontal, TTSpacing.badgePaddingH)
                .padding(.vertical, TTSpacing.badgePaddingV)
                .background(
                    Capsule()
                        .fill(kind?.background ?? color.opacity(0.14))
                        .overlay(
                            Capsule().stroke(kind?.border ?? color, lineWidth: 1)
                        )
                )

        case .soft:
            TTStatusPill(text: text, kind: kind ?? .info)
            
        case .dot:
            HStack(spacing: TTSpacing.xs) {
                Circle()
                    .fill(kind?.border ?? color)
                    .frame(width: TTSpacing.xs, height: TTSpacing.xs)
                Text(text)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextSecondary)
            }
        }
    }
}

// MARK: - Method Badge
struct HTTPMethodBadge: View {
    let method: String
    
    var body: some View {
        Text(method.uppercased())
            .font(TTFont.badge)
            .foregroundColor(.ttTextOnAccent)
            .padding(.horizontal, TTSpacing.xs)
            .padding(.vertical, TTSpacing.xxxs)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.xs)
                    .fill(Color.forHTTPMethod(method))
            )
    }
}

// MARK: - Status Code Badge
struct StatusCodeBadge: View {
    let code: Int
    
    var body: some View {
        let kind = TTBannerKind.fromStatusCode(code)
        Text("\(code)")
            .font(TTFont.badge)
            .fontWeight(.bold)
            .foregroundColor(kind.foreground)
            .padding(.horizontal, TTSpacing.xs)
            .padding(.vertical, TTSpacing.xxxs)
            .background(
                Capsule()
                    .fill(kind.background)
                    .overlay(Capsule().stroke(kind.border.opacity(0.55), lineWidth: 1))
            )
    }
}

// MARK: - Log Level Badge
struct LogLevelBadge: View {
    let level: String
    
    var iconName: String {
        switch level.lowercased() {
        case "error": return "xmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "info": return "info.circle.fill"
        case "debug": return "wrench.and.screwdriver.fill"
        default: return "circle.fill"
        }
    }
    
    private var kind: TTBannerKind {
        TTBannerKind.fromLogLevel(level)
    }
    
    var body: some View {
        Image(systemName: iconName)
            .font(.ttIcon(TTIcon.lg))
            .fontWeight(.semibold)
            .foregroundColor(level.lowercased() == "debug" ? .ttTextTertiary : kind.foreground)
            .accessibilityLabel(level)
    }
}

// MARK: - Section Divider
struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ttBorder.opacity(0.3))
            .frame(height: 1)
    }
}

// MARK: - Connection Status Indicator
struct ConnectionIndicator: View {
    var isConnected: Bool
    var label: String? = nil
    
    var body: some View {
        HStack(spacing: TTSpacing.xs) {
            Circle()
                .fill(isConnected ? Color.ttSuccess : Color.ttError)
                .frame(width: TTSpacing.sm, height: TTSpacing.sm)
                .overlay(
                    Circle()
                        .fill(isConnected ? Color.ttSuccess : Color.ttError)
                        .frame(width: TTSpacing.sm, height: TTSpacing.sm)
                        .blur(radius: isConnected ? 4 : 0)
                        .opacity(isConnected ? 0.5 : 0)
                )
            
            if let label = label {
                Text(label)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextSecondary)
            }
        }
    }
}

// MARK: - Device Badge
/// Compact colored badge showing which device a request came from
struct DeviceBadge: View {
    let deviceName: String
    let deviceId: String
    var compact: Bool = false
    
    private var deviceColor: Color {
        Color.forDevice(deviceId)
    }
    
    private var shortName: String {
        // Shorten "iPhone 15 Pro Max" → "iPhone 15P"
        let parts = deviceName.split(separator: " ")
        if parts.count <= 2 { return deviceName }
        let first = parts[0]
        let rest = parts.dropFirst().map { String($0.prefix(1)) }.joined()
        return "\(first) \(rest)"
    }
    
    var body: some View {
        if compact {
            // Dot-only mode for narrow layouts
            Circle()
                .fill(deviceColor)
                .frame(width: TTSpacing.xs, height: TTSpacing.xs)
                .help(deviceName)
        } else {
            HStack(spacing: TTSpacing.xxs) {
                Circle()
                    .fill(deviceColor)
                    .frame(width: TTSpacing.xs, height: TTSpacing.xs)
                Text(shortName)
                    .font(TTFont.codeSmall)
                    .foregroundColor(deviceColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, TTSpacing.xs)
            .padding(.vertical, TTSpacing.xxxs)
            .background(
                Capsule()
                    .fill(deviceColor.opacity(0.12))
            )
            .help(deviceName)
        }
    }
}
