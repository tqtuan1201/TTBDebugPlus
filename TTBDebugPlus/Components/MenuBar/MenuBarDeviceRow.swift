//
//  MenuBarDeviceRow.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Compact device row for menu bar dropdown
//  2026-07-15: Phase 2 — spacing/typography tokens.
//

import SwiftUI

struct MenuBarDeviceRow: View {
    @Environment(ConnectionManager.self) private var connectionManager
    let session: DeviceSession

    @State private var isHovered = false

    private var online: Bool { session.isOnline(relativeTo: connectionManager.uiNow) }
    private var warning: Bool { session.isHeartbeatWarning(relativeTo: connectionManager.uiNow) }

    var body: some View {
        HStack(spacing: TTSpacing.sm) {
            // Device icon
            Image(systemName: session.isSimulator ? AppIcon.simulator : AppIcon.device)
                .font(.ttIcon(TTIcon.md))
                .foregroundColor(online ? .ttSuccess : .ttTextMuted)
                .frame(width: TTIcon.xxl)

            // Device info
            VStack(alignment: .leading, spacing: TTSpacing.hairline) {
                Text(session.displayName)
                    .font(TTFont.labelLarge)
                    .lineLimit(1)

                Text(session.osVersionString)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextSecondary)
            }

            Spacer()

            // Status dot: green / amber / offline
            Circle()
                .fill(online ? (warning ? Color.ttWarning : Color.ttSuccess) : Color.ttTextMuted.opacity(0.5))
                .frame(width: TTSpacing.xs, height: TTSpacing.xs)
        }
        .padding(.horizontal, TTSpacing.md)
        .padding(.vertical, TTSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.xs)
                .fill(isHovered ? Color.ttSurfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
