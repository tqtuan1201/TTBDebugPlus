//
//  EmptyStateView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  2026-07-15: Phase 2 — spacing/typography tokens.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: TTSpacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.ttSurface)
                    .frame(width: TTSpacing.emptyStateIcon, height: TTSpacing.emptyStateIcon)

                Image(systemName: icon)
                    .font(TTFont.lightDisplay(base: 32))
                    .foregroundColor(.ttTextSecondary)
            }

            // Text
            VStack(spacing: TTSpacing.sm) {
                Text(title)
                    .font(TTFont.heading2)
                    .foregroundColor(.ttTextPrimary)

                Text(subtitle)
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Action Button
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: TTSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.ttPrimary)
                .padding(.top, TTSpacing.sm)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ttBackground)
    }
}

#Preview {
    EmptyStateView(
        icon: AppIcon.connectionOffline,
        title: "No Device Connected",
        subtitle: "Connect an iOS device running TTBaseUIKit to start debugging. Make sure both devices are on the same network.",
        actionTitle: "View Setup Guide"
    )
    .preferredColorScheme(.dark)
}
