//
//  JWTToolView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Container for the JWT Debugger dev tool: routes Decode / Verify / Generate /
//  Compare / History sub-tools, shares the working token across them, auto-detects
//  a JWT on the clipboard, and persists saved tokens via the SwiftData vault.
//

import AppKit
import SwiftUI

// MARK: - Sub-tool

enum JWTSubTool: String, CaseIterable, Identifiable {
    case decode = "Decode"
    case verify = "Verify"
    case generate = "Generate"
    case compare = "Compare"
    case history = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .decode:   return "doc.text.magnifyingglass"
        case .verify:   return "checkmark.seal"
        case .generate: return "hammer"
        case .compare:  return "rectangle.on.rectangle"
        case .history:  return "clock.arrow.circlepath"
        }
    }

    var help: String {
        switch self {
        case .decode:   return "Decode and inspect a token"
        case .verify:   return "Verify a signature with a key or secret"
        case .generate: return "Build and sign a new token"
        case .compare:  return "Diff two tokens claim-by-claim"
        case .history:  return "Saved tokens, search & favorites"
        }
    }
}

struct JWTToolView: View {
    @Environment(AppState.self) private var appState
    @Environment(TokenStore.self) private var tokenStore

    @State private var selectedTab: JWTSubTool = .decode
    @State private var workingToken = ""
    @State private var compareToken = ""

    @State private var clipboardCandidate: String?

    private enum DefaultsKey {
        static let selectedTab = "devTools.jwt.selectedTab"
    }

    var body: some View {
        VStack(spacing: 0) {
            subToolHeader

            if let clipboardCandidate {
                clipboardBanner(clipboardCandidate)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            restoreState()
            loadPayloadIfNeeded()
            detectClipboard()
        }
        .onChange(of: selectedTab) { _, new in
            UserDefaults.standard.set(new.rawValue, forKey: DefaultsKey.selectedTab)
        }
        .onChange(of: appState.jwtToolPayload) { _, _ in loadPayloadIfNeeded() }
        .alert("Token Vault Error", isPresented: Binding(
            get: { tokenStore.lastError != nil },
            set: { if !$0 { tokenStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { tokenStore.lastError = nil }
        } message: {
            Text(tokenStore.lastError ?? "")
        }
    }

    // MARK: - Sub-tool Header

    private var subToolHeader: some View {
        HStack(spacing: TTSpacing.inlineGapSmall) {
            ForEach(JWTSubTool.allCases) { tool in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { selectedTab = tool }
                } label: {
                    HStack(spacing: TTSpacing.tight) {
                        Image(systemName: tool.icon).font(.ttIcon(TTIcon.sm))
                        Text(tool.rawValue).font(TTFont.labelMedium)
                    }
                    .foregroundColor(selectedTab == tool ? .white : .ttTextTertiary)
                    .padding(.horizontal, TTSpacing.md).padding(.vertical, TTSpacing.xs)
                    .background(
                        Capsule().fill(selectedTab == tool ? Color.ttPrimary.opacity(0.45) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(tool.help)
            }
            Spacer()
        }
        .padding(.horizontal, TTSpacing.md).padding(.vertical, TTSpacing.xs)
        .background(Color.ttSurface.opacity(0.08))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.12)).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .decode:
            JWTDecodeView(
                token: $workingToken,
                onVerify: { withAnimation { selectedTab = .verify } },
                onSendToCompare: { token in
                    compareToken = token
                    withAnimation { selectedTab = .compare }
                },
                onSaveToHistory: saveToHistory
            )
        case .verify:
            JWTVerifyView(token: $workingToken)
        case .generate:
            JWTGenerateView(onSendToDecoder: { token in
                workingToken = token
                withAnimation { selectedTab = .decode }
            })
        case .compare:
            JWTCompareView(tokenA: $compareToken)
        case .history:
            JWTHistoryView(onLoad: { token in
                workingToken = token
                withAnimation { selectedTab = .decode }
            })
        }
    }

    // MARK: - Clipboard Banner

    private func clipboardBanner(_ candidate: String) -> some View {
        HStack(spacing: TTSpacing.inputPaddingH) {
            Image(systemName: "doc.on.clipboard")
                .font(TTFont.bodyMedium).foregroundColor(.ttPrimary)
            Text("A JWT is on your clipboard.")
                .font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
            Spacer()
            Button("Decode it") {
                workingToken = candidate
                selectedTab = .decode
                clipboardCandidate = nil
            }
            .font(TTFont.labelSmall).buttonStyle(.plain).foregroundColor(.ttPrimary)
            Button {
                clipboardCandidate = nil
            } label: {
                Image(systemName: "xmark").font(TTFont.bodySmall).foregroundColor(.ttTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TTSpacing.chromeInsetH).padding(.vertical, TTSpacing.sm)
        .background(Color.ttPrimary.opacity(0.08))
        .overlay(Rectangle().fill(Color.ttBorder.opacity(0.12)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - State / Payload

    private func restoreState() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.selectedTab),
           let tab = JWTSubTool(rawValue: raw) {
            selectedTab = tab
        }
    }

    private func loadPayloadIfNeeded() {
        guard let payload = appState.jwtToolPayload else { return }
        workingToken = payload.token
        selectedTab = .decode
        clipboardCandidate = nil
        appState.jwtToolPayload = nil
    }

    private func detectClipboard() {
        guard workingToken.isEmpty,
              let clip = NSPasteboard.general.string(forType: .string),
              JWTDecoder.looksLikeJWT(clip) else { return }
        clipboardCandidate = clip.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Save to History

    private func saveToHistory(_ decoded: DecodedJWT) {
        tokenStore.perform { repo in
            try repo.upsertHistory(
                name: deriveName(decoded),
                token: decoded.raw,
                algorithm: decoded.rawAlgorithm ?? "",
                sourceLabel: "Decoded",
                expiresAt: decoded.expiresAt,
                searchableExtra: searchableExtra(decoded)
            )
        }
        tokenStore.refreshStats()
    }

    private func deriveName(_ decoded: DecodedJWT) -> String {
        if let sub = decoded.payload["sub"] as? String, !sub.isEmpty { return "sub: \(sub)" }
        if let iss = decoded.payload["iss"] as? String, !iss.isEmpty { return "iss: \(iss)" }
        if let name = decoded.payload["name"] as? String, !name.isEmpty { return name }
        return "\(decoded.rawAlgorithm ?? "JWT") token"
    }

    private func searchableExtra(_ decoded: DecodedJWT) -> String {
        [decoded.payload["sub"], decoded.payload["iss"], decoded.payload["aud"], decoded.payload["name"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
    }
}
