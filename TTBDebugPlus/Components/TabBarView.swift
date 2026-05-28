//
//  TabBarView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Main navigation tab bar with icons — Guide tab moved to sidebar
//

import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) var appState
    
    var body: some View {
        HStack(spacing: 0) {
            // App Title
            Text("TTBDebugPlus")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextPrimary)
                .padding(.leading, 20)
            
            // Tab Items (excluding Guide — sidebar-only)
            HStack(spacing: 0) {
                ForEach(Array(AppTab.tabBarCases.enumerated()), id: \.element.id) { index, tab in
                    TabItemView(
                        tab: tab,
                        isSelected: appState.selectedTab == tab,
                        shortcutNumber: index + 1
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if tab == .devtools {
                                appState.openDevToolsMenu()
                            } else {
                                appState.selectedTab = tab
                            }
                        }
                    }
                }
            }
            .padding(.leading, 24)
            
            Spacer()
            
            // Toolbar Actions
            toolbarActions
        }
        .padding(.vertical, 8)
        .background(Color.ttBackground)
        .overlay(
            Rectangle()
                .fill(Color.ttBorder.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var toolbarActions: some View {
        HStack(spacing: 8) {
            // Dynamic version badge
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            Text("v\(version)")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.ttSurface)
                )
        }
        .padding(.trailing, 16)
    }
}

// MARK: - Individual Tab Item
struct TabItemView: View {
    let tab: AppTab
    let isSelected: Bool
    var shortcutNumber: Int = 0
    let action: () -> Void
    
    private var shortcutKey: KeyEquivalent {
        guard shortcutNumber > 0, shortcutNumber <= 9 else { return "0" }
        return KeyEquivalent(Character("\(shortcutNumber)"))
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .ttPrimary : .ttTextTertiary)
                    Text(tab.rawValue)
                        .font(TTFont.tabLabel)
                        .foregroundColor(isSelected ? .ttPrimary : .ttTextSecondary)
                    
                    // Keyboard shortcut hint
                    if shortcutNumber > 0 {
                        Text("⌘\(shortcutNumber)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.ttTextMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.ttSurface.opacity(0.6))
                            )
                    }
                }
                
                // Active indicator line
                Rectangle()
                    .fill(isSelected ? Color.ttPrimary : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcutKey, modifiers: .command)
    }
}

#Preview {
    TabBarView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
