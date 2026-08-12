//
//  UsageGuideView.swift
//  DebugKit
//
//  Created by TuanTruong on 2026-03-27.
//  macOS app feature guide, keyboard shortcuts, tips & export reference
//

import SwiftUI

struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.sectionGapLarge) {
                // Header
                VStack(alignment: .leading, spacing: TTSpacing.sm) {
                    HStack(spacing: TTSpacing.inputPaddingH) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.ttSuccess.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: AppIcon.guide)
                                .font(.ttIcon(TTIcon.xxl))
                                .foregroundColor(.ttSuccess)
                        }
                        
                        VStack(alignment: .leading, spacing: TTSpacing.xxxs) {
                            Text("How to Use DebugKit")
                                .font(TTFont.displayMedium)
                                .foregroundColor(.ttTextPrimary)
                            Text("Learn what each feature does and how to get the most out of it")
                                .font(TTFont.bodyMedium)
                                .foregroundColor(.ttTextSecondary)
                        }
                    }
                }
                
                // Feature Guides
                Text("FEATURES")
                    .font(TTFont.sidebarHeader)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.8)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TTSpacing.lg) {
                    featureGuideCard(
                        icon: AppIcon.console,
                        title: "Console",
                        color: .ttSuccess,
                        features: [
                            "View real-time app logs streamed from iOS",
                            "Filter by level: All, Errors, Warnings, Debug",
                            "Search text with highlight matching",
                            "Click a log entry to see JSON payload details",
                            "Auto-scroll follows new entries in LIVE mode"
                        ]
                    )
                    
                    featureGuideCard(
                        icon: AppIcon.network,
                        title: "Network",
                        color: .ttPrimary,
                        features: [
                            "Inspect all API requests with status codes",
                            "Filter by status: 2xx, 4xx, 5xx",
                            "View request/response headers & JSON body",
                            "Waterfall timing bars for performance",
                            "Export any request as cURL command"
                        ]
                    )
                    
                    featureGuideCard(
                        icon: AppIcon.device,
                        title: "Device",
                        color: .ttWarning,
                        features: [
                            "Capture remote screenshots from iOS",
                            "Record mode: auto-capture every 2 seconds",
                            "Annotate with freehand, arrows, shapes, text",
                            "Toggle dark mode, reduced motion, accessibility",
                            "Send app lifecycle commands (launch, kill, reset)"
                        ]
                    )
                    
                    featureGuideCard(
                        icon: "chart.xyaxis.line",
                        title: "Performance",
                        color: .ttError,
                        features: [
                            "Real-time CPU & Memory usage charts",
                            "Network bandwidth (upload/download)",
                            "FPS counter and disk usage",
                            "API analytics: avg response time, error rate",
                            "Slow request & duplicate request detection"
                        ]
                    )
                    
                    featureGuideCard(
                        icon: "bubble.left.and.text.bubble.right.fill",
                        title: "Feedback",
                        color: .purple,
                        features: [
                            "Create bug reports with title & description",
                            "Auto-tag: UI/UX, Network, Crash, Performance",
                            "Attach screenshots (with or without annotations)",
                            "Export reports as Markdown files",
                            "Mark reports as resolved / reopened"
                        ]
                    )
                    
                    featureGuideCard(
                        icon: "square.and.arrow.up.fill",
                        title: "Export",
                        color: .cyan,
                        features: [
                            "HAR 1.2 — compatible with Chrome DevTools",
                            "cURL — replay requests in Terminal",
                            "Markdown — structured bug reports",
                            "JSON — copy raw payloads",
                            "NSSharingServicePicker — system share sheet"
                        ]
                    )

                    featureGuideCard(
                        icon: AppIcon.localhostServers,
                        title: "Localhost Servers",
                        color: .ttPrimary,
                        features: [
                            "Dev Tools → Localhost: list TCP listeners (port, PID, process)",
                            "Save project servers with command, folder, and preferred port",
                            "Start / stop / restart with live log tail",
                            "Soft-stop or force-kill with confirmation (system ports protected)",
                            "Conflict sheet when a preferred port is already in use"
                        ]
                    )

                    featureGuideCard(
                        icon: AppIcon.colorPicker,
                        title: "Color Picker",
                        color: .ttInfo,
                        features: [
                            "Dev Tools → Color Picker: sample any on-screen pixel",
                            "Copy Hex, RGB, HSL, SwiftUI, UIColor, NSColor, and CSS",
                            "Session palette for today’s debug colors (export JSON)",
                            "WCAG contrast check for foreground vs background",
                            "Match picked colors to design tokens (e.g. .ttPrimary)"
                        ]
                    )
                }
                
                // Keyboard Shortcuts
                Text("KEYBOARD SHORTCUTS")
                    .font(TTFont.sidebarHeader)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.8)
                
                CardView(title: "") {
                    VStack(spacing: 0) {
                        shortcutRow(keys: "⌘ K", action: "Clear console logs", isAlternate: false)
                        shortcutRow(keys: "⌘ F", action: "Focus search field", isAlternate: true)
                        shortcutRow(keys: "⇧ ⌘ C", action: "Capture screenshot from iOS device", isAlternate: false)
                        shortcutRow(keys: "⇧ ⌘ E", action: "Export current session", isAlternate: true)
                        shortcutRow(keys: "⌘ ,", action: "Open Settings", isAlternate: false)
                        shortcutRow(keys: "⌘ 1–5", action: "Switch between tabs", isAlternate: true)
                    }
                }
                
                // Pro Tips
                Text("PRO TIPS")
                    .font(TTFont.sidebarHeader)
                    .foregroundColor(.ttTextTertiary)
                    .tracking(0.8)
                
                VStack(spacing: TTSpacing.md) {
                    tipCard(
                        icon: "arrow.clockwise.circle.fill",
                        title: "Replay API Requests",
                        description: "Copy any request as cURL from the Network tab, paste into Terminal to replay. Edit headers or body as needed.",
                        color: .ttPrimary
                    )
                    
                    tipCard(
                        icon: AppIcon.localhostServers,
                        title: "Free a stuck port without Terminal",
                        description: "Open Dev Tools → Localhost → Live Ports, select the process on :3000 (or any port), Soft Stop first, then Force Kill only if needed. Protected DebugKit ports cannot be killed here.",
                        color: .ttWarning
                    )

                    tipCard(
                        icon: AppIcon.colorPicker,
                        title: "Copy Swift colors without leaving the app",
                        description: "Open Dev Tools → Color Picker, use Pick Screen on a UI bug, then Copy UIColor or SwiftUI. Set Foreground and Background to check WCAG AA/AAA before you ship.",
                        color: .ttInfo
                    )

                    tipCard(
                        icon: "doc.badge.arrow.up.fill",
                        title: "HAR Export for Team Sharing",
                        description: "Export your session as HAR file → open in Chrome DevTools (Network → Import HAR) or Proxyman for team-level analysis.",
                        color: .ttSuccess
                    )
                    
                    tipCard(
                        icon: "pencil.tip.crop.circle.fill",
                        title: "Annotate Before Sharing",
                        description: "Capture a screenshot → tap Annotate → draw arrows, circles, or text to highlight bugs → Share with your team using the system share sheet.",
                        color: .ttWarning
                    )
                    
                    tipCard(
                        icon: "shield.checkered",
                        title: "Production Safety",
                        description: "Always wrap TTDebugBridge.shared.start() in #if DEBUG to ensure zero impact on production builds. The bridge is a complete no-op when not started.",
                        color: .ttError
                    )
                    
                    tipCard(
                        icon: AppIcon.connectionHealth,
                        title: "Multiple Devices",
                        description: "DebugKit supports multiple connected devices simultaneously. Use the sidebar to switch between devices and view their individual logs.",
                        color: .purple
                    )
                }
            }
            .padding(.horizontal, TTSpacing.xxxl)
            .padding(.vertical, TTSpacing.xxl)
        }
        .background(Color.ttBackground)
    }
    
    // MARK: - Feature Guide Card
    private func featureGuideCard(icon: String, title: String, color: Color, features: [String]) -> some View {
        VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
            HStack(spacing: TTSpacing.inputPaddingH) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.ttIcon(TTIcon.xxl))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextPrimary)
            }
            
            VStack(alignment: .leading, spacing: TTSpacing.sm) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: TTSpacing.sm) {
                        Image(systemName: "checkmark")
                            .font(.ttIcon(TTIcon.xs))
                            .foregroundColor(color)
                            .padding(.top, TTSpacing.inlineGapSmall)
                        Text(feature)
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextSecondary)
                    }
                }
            }
        }
        .padding(TTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.ttSurface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.ttBorder.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Shortcut Row
    private func shortcutRow(keys: String, action: String, isAlternate: Bool) -> some View {
        HStack {
            // Key badges
            HStack(spacing: TTSpacing.xxs) {
                ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
                    Text(key)
                        .font(TTFont.codeMedium)
                        .foregroundColor(.ttTextPrimary)
                        .padding(.horizontal, TTSpacing.sm)
                        .padding(.vertical, TTSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.ttSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.ttBorder, lineWidth: 1)
                                )
                        )
                }
            }
            .frame(width: 120, alignment: .leading)
            
            Text(action)
                .font(TTFont.bodyMedium)
                .foregroundColor(.ttTextSecondary)
            
            Spacer()
        }
        .padding(.horizontal, TTSpacing.chromeInsetH)
        .padding(.vertical, TTSpacing.inputPaddingH)
        .background(isAlternate ? Color.ttSurface.opacity(0.15) : Color.clear)
    }
    
    // MARK: - Tip Card
    private func tipCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: TTSpacing.chromeInsetH) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.xxl))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                Text(title)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
                Text(description)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .lineSpacing(2)
            }
        }
        .padding(TTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.ttSurface.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.ttBorder.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    UsageGuideView()
        .frame(width: 900, height: 900)
        .preferredColorScheme(.dark)
}
