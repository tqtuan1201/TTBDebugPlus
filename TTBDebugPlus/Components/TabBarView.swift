//
//  TabBarView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Main navigation tab bar with icons — Guide tab moved to sidebar
//  2026-07-10: removed blue selection underline + bottom hairline for flat chrome.
//  2026-07-14: grey out device tabs while debug server is stopped.
//  2026-07-15: Phase 2 — spacing/typography tokens.
//

import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionManager.self) var connectionManager

    var body: some View {
        HStack(spacing: 0) {
            // App title (detail pane) — white via design token
            Text(AppBrand.name)
                .font(TTFont.heading3)
                .foregroundColor(.ttTextPrimary)
                .padding(.leading, TTSpacing.tabTitleLeading)

            // Tab Items (excluding Guide — sidebar-only)
            HStack(spacing: 0) {
                ForEach(Array(AppTab.tabBarCases.enumerated()), id: \.element.id) { index, tab in
                    let needsServer = tab.requiresLiveServer
                    let serverOff = !connectionManager.isLifecycleActive
                    let isGated = needsServer && serverOff

                    TabItemView(
                        tab: tab,
                        isSelected: appState.selectedTab == tab,
                        shortcutNumber: index + 1,
                        isGated: isGated
                    ) {
                        withAnimation(.easeInOut(duration: TTAnimation.durationSlow)) {
                            if isGated {
                                appState.serverRequiredHint =
                                    "Start Server to use \(tab.rawValue). Dev Tools stay available without the server."
                            } else if tab == .devtools {
                                appState.serverRequiredHint = nil
                                appState.openDevToolsMenu()
                            } else {
                                appState.serverRequiredHint = nil
                                appState.selectedTab = tab
                            }
                        }
                    }
                }
            }
            .padding(.leading, TTSpacing.tabClusterLeading)

            Spacer()

            // Toolbar Actions
            toolbarActions
        }
        .padding(.vertical, TTSpacing.chromeInsetV)
        .background(Color.ttBackground)
        // No bottom hairline / no blue selection bar — flat canvas
    }

    private var toolbarActions: some View {
        HStack(spacing: TTSpacing.sm) {
            // Dynamic version badge
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            Text("v\(version)")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
                .padding(.horizontal, TTSpacing.badgePaddingH)
                .padding(.vertical, TTSpacing.badgePaddingV)
                .background(
                    Capsule()
                        .fill(Color.ttSurface)
                )
        }
        .padding(.trailing, TTSpacing.lg)
    }
}

// MARK: - Individual Tab Item
struct TabItemView: View {
    let tab: AppTab
    let isSelected: Bool
    var shortcutNumber: Int = 0
    /// True when this tab needs the debug server and the server is currently stopped.
    var isGated: Bool = false
    let action: () -> Void

    private var shortcutKey: KeyEquivalent {
        guard shortcutNumber > 0, shortcutNumber <= 9 else { return "0" }
        return KeyEquivalent(Character("\(shortcutNumber)"))
    }

    private var labelColor: Color {
        if isGated { return .ttTextMuted }
        return isSelected ? .ttPrimary : .ttTextSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: TTSpacing.tight) {
                Image(systemName: tab.icon)
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(labelColor)
                Text(tab.rawValue)
                    .font(TTFont.tabLabel)
                    .foregroundColor(labelColor)

                // Keyboard shortcut hint
                if shortcutNumber > 0 {
                    Text("⌘\(shortcutNumber)")
                        .font(TTFont.badge)
                        .foregroundColor(.ttTextMuted)
                        .padding(.horizontal, TTSpacing.xxs)
                        .padding(.vertical, TTSpacing.hairline)
                        .background(
                            RoundedRectangle(cornerRadius: TTRadius.xs)
                                .fill(Color.ttSurface.opacity(0.6))
                        )
                }
            }
            .padding(.horizontal, TTSpacing.lg)
            .padding(.vertical, TTSpacing.xs)
            .opacity(isGated ? 0.55 : 1)
            // Selected state via text/icon color only — no underline
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcutKey, modifiers: .command)
        .help(isGated ? "Start Server to use \(tab.rawValue)" : tab.rawValue)
        .accessibilityLabel(isGated ? "\(tab.rawValue), requires server" : tab.rawValue)
    }
}

#Preview {
    TabBarView()
        .environment(AppState())
        .environment(ConnectionManager())
        .preferredColorScheme(.dark)
}
