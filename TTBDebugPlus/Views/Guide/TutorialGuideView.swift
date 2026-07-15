//
//  TutorialGuideView.swift
//  TTBDebugPlus
//
//  Phase 9 — beginner-friendly "how to connect" walkthrough, placed before Integration
//  Guide in the tab order. Distinct scope from Integration Guide on purpose: this is about
//  the CONNECTION mechanics (pairing an already-integrated app), not writing code — see
//  plans/2026-07-13-connection-reliability/phase-09-connection-help-ux-redesign.md Part 4.
//

import SwiftUI

struct TutorialGuideView: View {
    @State private var selectedMethod: TutorialMethod? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                prerequisiteBanner
                    .padding(.horizontal, TTSpacing.xxxl)
                    .padding(.bottom, TTSpacing.xxl)

                methodPicker
                    .padding(.horizontal, TTSpacing.xxxl)
                    .padding(.bottom, TTSpacing.xxl)

                if let method = selectedMethod {
                    walkthrough(for: method)
                        .padding(.horizontal, TTSpacing.xxxl)
                        .padding(.bottom, TTSpacing.xxl)
                        .transition(.opacity)
                }

                verificationSection
                    .padding(.horizontal, TTSpacing.xxxl)
                    .padding(.bottom, TTSpacing.xxl)

                commonIssuesSection
                    .padding(.horizontal, TTSpacing.xxxl)
                    .padding(.bottom, TTSpacing.xxxxl)
            }
        }
        .background(Color.ttBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: TTSpacing.inputPaddingH) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.ttPrimary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "hand.wave.fill")
                    .font(.ttIcon(TTIcon.xxl))
                    .foregroundColor(.ttPrimary)
            }
            VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                Text("Connect Your iPhone")
                    .font(TTFont.displayMedium)
                    .foregroundColor(.ttTextPrimary)
                Text("Step by step — no code, no reading required")
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextSecondary)
            }
        }
        .padding(.horizontal, TTSpacing.xxxl)
        .padding(.top, TTSpacing.xxl)
        .padding(.bottom, TTSpacing.xl)
    }

    private var prerequisiteBanner: some View {
        TTBanner(
            kind: .info,
            message: "This assumes your iOS app already has the SDK added and TTDebugBridge.shared.start() is called. Not done yet? See the Integration Guide tab first.",
            title: "Before you start"
        )
    }

    // MARK: - Method Picker

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: TTSpacing.md) {
            Text("CHOOSE HOW TO CONNECT")
                .font(TTFont.sidebarHeader)
                .foregroundColor(.ttTextSecondary)
                .tracking(1.2)

            HStack(spacing: TTSpacing.lg) {
                methodCard(
                    method: .bonjour,
                    icon: "antenna.radiowaves.left.and.right",
                    tint: .ttChannelBonjourForeground,
                    title: "Bonjour",
                    subtitle: "Same Wi-Fi — fully automatic"
                )
                methodCard(
                    method: .relay,
                    icon: "globe",
                    tint: .ttChannelRelayForeground,
                    title: "Relay",
                    subtitle: "Any network — scan a QR once"
                )
            }
        }
    }

    private func methodCard(method: TutorialMethod, icon: String, tint: Color, title: String, subtitle: String) -> some View {
        let isSelected = selectedMethod == method
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMethod = isSelected ? nil : method
            }
        }) {
            VStack(spacing: TTSpacing.inputPaddingH) {
                Image(systemName: icon)
                    .font(TTFont.lightDisplay(base: 32))
                    .foregroundColor(tint)
                Text(title)
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
                Text(subtitle)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .multilineTextAlignment(.center)
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(TTFont.labelMedium)
                    .foregroundColor(.ttTextTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TTSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? tint.opacity(0.1) : Color.ttSurface.opacity(0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? tint : Color.ttBorder.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Walkthrough

    @ViewBuilder
    private func walkthrough(for method: TutorialMethod) -> some View {
        CardView(title: method == .bonjour ? "BONJOUR — 3 STEPS" : "RELAY — 3 STEPS") {
            let methodSteps = steps(for: method)
            VStack(alignment: .leading, spacing: TTSpacing.lg) {
                ForEach(Array(methodSteps.enumerated()), id: \.offset) { index, step in
                    tutorialStepRow(number: index + 1, step: step)
                    if index < methodSteps.count - 1 {
                        Divider().background(Color.ttBorder.opacity(0.3))
                    }
                }
            }
        }
    }

    private func tutorialStepRow(number: Int, step: TutorialStep) -> some View {
        HStack(alignment: .top, spacing: TTSpacing.chromeInsetH) {
            ZStack {
                Circle()
                    .fill(Color.ttPrimary)
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(TTFont.codeMedium)
                    .foregroundColor(.ttTextOnAccent)
            }
            VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                Text(step.title)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
                Text(step.detail)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
            }
            Spacer()
            Image(systemName: step.icon)
                .font(TTFont.heading2)
                .foregroundColor(.ttTextTertiary)
        }
    }

    // MARK: - Verification

    private var verificationSection: some View {
        CardView(title: "HOW TO KNOW IT WORKED") {
            VStack(alignment: .leading, spacing: TTSpacing.inputPaddingH) {
                Text("Your device shows up in the sidebar with a green dot and a channel badge:")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
                HStack(spacing: TTSpacing.sm) {
                    ChannelChip(channel: .bonjour, style: .compact)
                    ChannelChip(channel: .relay(isRemoteView: false), style: .compact)
                    ChannelChip(channel: .relay(isRemoteView: true), style: .compact)
                }
                Text("The badge tells you which path it's using — helpful if you set up both.")
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextTertiary)
            }
        }
    }

    // MARK: - Common Issues

    private var commonIssuesSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.md) {
            Text("COMMON ISSUES")
                .font(TTFont.sidebarHeader)
                .foregroundColor(.ttTextSecondary)
                .tracking(1.2)

            TTBanner(
                kind: .error,
                message: "Missing Info.plist keys on iOS — this is a code setup issue, not a pairing one. See Integration Guide → Step 2.",
                title: "Xcode console shows \"NoAuth -65555\""
            )
            TTBanner(
                kind: .warning,
                message: "Check both devices share the same Wi-Fi network, and that Server is On in TTBDebugPlus (sidebar or menu bar).",
                title: "Device never appears"
            )
            TTBanner(
                kind: .warning,
                message: "On iPhone: Settings → Privacy & Security → Local Network → enable for this app. Reopen the app, then tap Reset Connection in the Debug Bridge panel.",
                title: "iOS asked for \"Local Network\" access and you tapped Don't Allow"
            )
        }
    }

    // MARK: - Step Data

    private func steps(for method: TutorialMethod) -> [TutorialStep] {
        switch method {
        case .bonjour:
            return [
                TutorialStep(
                    title: "Same Wi-Fi",
                    detail: "Connect your iPhone and this Mac to the same Wi-Fi network.",
                    icon: "wifi"
                ),
                TutorialStep(
                    title: "Turn on the Server",
                    detail: "In TTBDebugPlus, make sure Server is On (sidebar toggle or menu bar icon).",
                    icon: "power"
                ),
                TutorialStep(
                    title: "Wait a few seconds",
                    detail: "Your device appears automatically in the sidebar — nothing to tap on iPhone.",
                    icon: "checkmark.circle"
                )
            ]
        case .relay:
            return [
                TutorialStep(
                    title: "Relay turns on with the Server",
                    detail: "In TTBDebugPlus: Settings → Relay — it's already listening once the main Server is on, no separate switch.",
                    icon: "arrow.triangle.2.circlepath"
                ),
                TutorialStep(
                    title: "Scan the QR from your iPhone",
                    detail: "On iPhone: open the Debug Bridge panel → Scan QR → point the camera at the QR code shown in Settings → Relay.",
                    icon: "qrcode.viewfinder"
                ),
                TutorialStep(
                    title: "Done — saved for good",
                    detail: "Your iPhone reconnects through the relay automatically on every future launch, even on a different network.",
                    icon: "checkmark.seal"
                )
            ]
        }
    }
}

// MARK: - Model

enum TutorialMethod: Equatable {
    case bonjour
    case relay
}

struct TutorialStep {
    let title: String
    let detail: String
    let icon: String
}

#Preview {
    TutorialGuideView()
        .frame(width: 900, height: 900)
        .preferredColorScheme(.dark)
}
