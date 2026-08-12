//
//  WelcomeSheet.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  First-launch onboarding sheet with 3 pages
//

import SwiftUI

struct WelcomeSheet: View {
    @Binding var isPresented: Bool
    @State private var currentPage: Int = 0
    
    private let totalPages = 3
    
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                heroPage.tag(0)
                featuresPage.tag(1)
                quickStartPage.tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(width: 680, height: 460)
            
            // Bottom controls
            HStack {
                // Page dots
                HStack(spacing: TTSpacing.sm) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.ttPrimary : Color.ttBorder)
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .animation(.spring(duration: 0.3), value: currentPage)
                    }
                }
                
                Spacer()
                
                // Navigation
                HStack(spacing: TTSpacing.md) {
                    if currentPage > 0 {
                        Button("Back") {
                            withAnimation { currentPage -= 1 }
                        }
                        .buttonStyle(.ttSecondaryCompact)
                    }
                    
                    if currentPage < totalPages - 1 {
                        Button("Skip") {
                            isPresented = false
                        }
                        .buttonStyle(.ttGhost)
                        
                        Button("Next") {
                            withAnimation { currentPage += 1 }
                        }
                        .buttonStyle(.ttPrimaryCompact)
                    } else {
                        Button("Get Started") {
                            isPresented = false
                        }
                        .buttonStyle(.ttPrimary)
                    }
                }
            }
            .padding(.horizontal, TTSpacing.xxxl)
            .padding(.bottom, TTSpacing.xxl)
        }
        .background(Color.ttBackground)
        .frame(width: 680, height: 520)
    }
    
    // MARK: - Page 1: Hero
    private var heroPage: some View {
        VStack(spacing: TTSpacing.xxl) {
            Spacer()
            
            // App icon gradient
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ttPrimary.opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 120
                        )
                    )
                    .frame(width: 200, height: 200)
                
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [Color.ttPrimary, Color.ttPrimary.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .shadow(color: .ttPrimary.opacity(0.4), radius: 20, y: 8)
                    
                    Image(systemName: "ant.circle.fill")
                        .font(TTFont.displayLarge)
                        .foregroundColor(.ttTextPrimary)
                }
            }
            
            VStack(spacing: TTSpacing.sm) {
                Text(AppBrand.name)
                    .font(TTFont.displayLarge)
                    .foregroundColor(.ttTextPrimary)
                
                Text(AppBrand.tagline)
                    .font(TTFont.heading3)
                    .foregroundColor(.ttTextSecondary)
            }
            
            Text("Capture logs, inspect network traffic, annotate screenshots,\nand monitor performance — all from your Mac.")
                .font(TTFont.bodyMedium)
                .foregroundColor(.ttTextTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Spacer()
        }
        .padding(.horizontal, TTSpacing.xxxxl)
    }
    
    // MARK: - Page 2: Features
    private var featuresPage: some View {
        VStack(spacing: TTSpacing.xxl) {
            Text("Everything You Need to Debug")
                .font(TTFont.displayMedium)
                .foregroundColor(.ttTextPrimary)
                .padding(.top, TTSpacing.xxxl)
            
            // Feature grid (2x3)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: TTSpacing.lg) {
                featureCard(icon: AppIcon.console, title: "Console", description: "Real-time logs with\nlevel filtering", color: .ttSuccess)
                featureCard(icon: AppIcon.network, title: "Network", description: "API inspector with\nJSON preview", color: .ttPrimary)
                featureCard(icon: AppIcon.device, title: "Device", description: "Remote screenshots\n& annotations", color: .ttWarning)
                featureCard(icon: AppIcon.performance, title: "Performance", description: "CPU, Memory &\nFPS charts", color: .ttError)
                featureCard(icon: AppIcon.feedback, title: "Feedback", description: "Bug reports with\nscreenshot export", color: .purple)
                featureCard(icon: "square.and.arrow.up.fill", title: "Export", description: "HAR, cURL &\nMarkdown export", color: .cyan)
            }
            .padding(.horizontal, TTSpacing.xxxl)
            
            Spacer()
        }
    }
    
    private func featureCard(icon: String, title: String, description: String, color: Color) -> some View {
        VStack(spacing: TTSpacing.inputPaddingH) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(TTFont.heading2)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextPrimary)
            
            Text(description)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TTSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.ttSurface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.ttBorder.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Page 3: Quick Start
    private var quickStartPage: some View {
        VStack(spacing: TTSpacing.xxl) {
            Text("Quick Start")
                .font(TTFont.displayMedium)
                .foregroundColor(.ttTextPrimary)
                .padding(.top, TTSpacing.xxxl)
            
            VStack(alignment: .leading, spacing: TTSpacing.xl) {
                quickStartStep(
                    number: 1,
                    title: "Add TTBaseUIKit to your iOS project",
                    subtitle: "Via Swift Package Manager or copy the DebugBridge files manually"
                )
                
                quickStartStep(
                    number: 2,
                    title: "Start the Debug Bridge",
                    subtitle: "Add TTDebugBridge.shared.start() in your AppDelegate"
                )
                
                quickStartStep(
                    number: 3,
                    title: "Run both apps on the same network",
                    subtitle: "DebugKit auto-discovers your iOS device via Bonjour"
                )
            }
            .padding(.horizontal, TTSpacing.sheetWidePadding)
            
            // Tip — high-contrast warning surface
            HStack(spacing: TTSpacing.inputPaddingH) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(TTBannerKind.warning.foreground)
                    .font(.ttIcon(TTIcon.xl))
                Text("Check the **Integration Guide** tab for detailed code snippets")
                    .font(TTFont.bodySmall)
                    .foregroundColor(TTBannerKind.warning.foreground)
            }
            .padding(.horizontal, TTSpacing.xl)
            .padding(.vertical, TTSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(TTBannerKind.warning.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(TTBannerKind.warning.border.opacity(0.55), lineWidth: 1)
                    )
            )
            
            Spacer()
        }
    }
    
    private func quickStartStep(number: Int, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: TTSpacing.lg) {
            // Number badge
            ZStack {
                Circle()
                    .fill(Color.ttPrimary)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(TTFont.codeLarge)
                    .foregroundColor(.ttTextOnAccent)
            }
            
            VStack(alignment: .leading, spacing: TTSpacing.xxs) {
                Text(title)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
                Text(subtitle)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
            }
        }
    }
}

#Preview {
    WelcomeSheet(isPresented: .constant(true))
        .preferredColorScheme(.dark)
}
