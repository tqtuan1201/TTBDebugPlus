//
//  JWTDecodeView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Decode & inspect a JWT — live header/payload, registered-claim interpretation,
//  and inline offline security analysis.
//

import AppKit
import SwiftUI

struct JWTDecodeView: View {
    @Binding var token: String
    var onVerify: () -> Void = {}
    var onSendToCompare: (String) -> Void = { _ in }
    var onSaveToHistory: (DecodedJWT) -> Void = { _ in }

    /// Canonical jwt.io HS256 sample for quick exploration.
    private static let sampleToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

    private var trimmed: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var decoded: DecodedJWT? {
        guard !trimmed.isEmpty else { return nil }
        return try? JWTDecoder.decode(trimmed)
    }

    private var decodeError: String? {
        guard !trimmed.isEmpty else { return nil }
        do { _ = try JWTDecoder.decode(trimmed); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        HStack(spacing: 0) {
            inputPanel
                .frame(width: 380)

            Divider().background(Color.ttBorder.opacity(0.3))

            resultPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
    }

    // MARK: - Input Panel

    private var inputPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
                JWTSectionCard(title: "Encoded Token", icon: "key.horizontal") {
                    JWTMonoEditor(text: $token, placeholder: "Paste a JWT (header.payload.signature)…")
                        .frame(height: 150)

                    if !trimmed.isEmpty {
                        JWTColorizedToken(token: trimmed)
                    }

                    HStack(spacing: TTSpacing.sm) {
                        JWTActionButton(title: "Paste", icon: "doc.on.clipboard") { paste() }
                        JWTActionButton(title: "Clear", icon: "xmark.circle", disabled: token.isEmpty) { token = "" }
                    }
                    HStack(spacing: TTSpacing.sm) {
                        JWTActionButton(title: "Sample", icon: "sparkles") { token = Self.sampleToken }
                        JWTCopyButton(text: trimmed, label: "Copy")
                            .frame(maxWidth: .infinity)
                    }
                }

                if let decoded {
                    JWTSectionCard(title: "Summary", icon: "info.circle") {
                        summaryRow("Algorithm", decoded.rawAlgorithm ?? "—",
                                   color: decoded.algorithm == JWTAlgorithm.none ? .ttError : .ttTextPrimary)
                        summaryRow("Type", (decoded.header["typ"] as? String) ?? "—")
                        summaryRow("Claims", "\(decoded.claims.count)")
                        if decoded.isExpired {
                            summaryRow("Status", "Expired", color: .ttError)
                        } else if decoded.isNotYetValid {
                            summaryRow("Status", "Not yet valid", color: .ttWarning)
                        } else if decoded.expiresAt != nil {
                            summaryRow("Status", "Active", color: .ttSuccess)
                        }
                    }

                    JWTSectionCard(title: "Actions", icon: "wand.and.stars") {
                        JWTActionButton(title: "Verify Signature", icon: "checkmark.seal", prominent: true) { onVerify() }
                        HStack(spacing: TTSpacing.sm) {
                            JWTActionButton(title: "Compare", icon: "rectangle.on.rectangle") { onSendToCompare(trimmed) }
                            JWTActionButton(title: "Save", icon: "tray.and.arrow.down") { onSaveToHistory(decoded) }
                        }
                    }
                }
            }
            .padding(TTSpacing.lg)
        }
        .background(Color.ttSurface.opacity(0.08))
    }

    private func summaryRow(_ title: String, _ value: String, color: Color = .ttTextPrimary) -> some View {
        HStack {
            Text(title).font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
            Spacer()
            Text(value).font(TTFont.codeSmall).foregroundColor(color).lineLimit(1)
        }
    }

    // MARK: - Result Panel

    @ViewBuilder
    private var resultPanel: some View {
        if trimmed.isEmpty {
            JWTEmptyState(
                icon: "key.horizontal",
                title: "No Token",
                subtitle: "Paste an encoded JWT on the left to decode its header, payload, and claims — fully offline."
            )
        } else if let error = decodeError {
            JWTEmptyState(icon: "exclamationmark.triangle", title: "Could Not Decode", subtitle: error)
        } else if let decoded {
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
                    JWTSectionCard(
                        title: "Header",
                        icon: "number",
                        accessory: AnyView(JWTCopyButton(text: decoded.headerJSON))
                    ) {
                        JWTMonoDisplay(text: decoded.headerJSON)
                            .frame(minHeight: 80, maxHeight: 160)
                    }

                    JWTSectionCard(
                        title: "Payload",
                        icon: "doc.text",
                        accessory: AnyView(JWTCopyButton(text: decoded.payloadJSON))
                    ) {
                        JWTMonoDisplay(text: decoded.payloadJSON)
                            .frame(minHeight: 120, maxHeight: 260)
                    }

                    if !decoded.claims.isEmpty {
                        JWTSectionCard(title: "Claims", icon: "list.bullet.rectangle") {
                            VStack(spacing: 0) {
                                ForEach(decoded.claims) { JWTClaimRowView(claim: $0) }
                            }
                        }
                    }

                    securityCard(for: decoded)
                }
                .padding(TTSpacing.lg)
            }
        }
    }

    private func securityCard(for decoded: DecodedJWT) -> some View {
        let findings = JWTSecurityAnalyzer.analyze(decoded)
        let worst = findings.map(\.severity).max() ?? .info
        return JWTSectionCard(
            title: "Security Analysis",
            icon: "shield.lefthalf.filled",
            accessory: AnyView(
                Text("\(findings.count) finding\(findings.count == 1 ? "" : "s")")
                    .font(TTFont.badge)
                    .foregroundColor(worst.color)
                    .padding(.horizontal, TTSpacing.rowVertical).padding(.vertical, TTSpacing.inlineGapSmall)
                    .background(Capsule().fill(worst.color.opacity(0.14)))
            )
        ) {
            VStack(spacing: TTSpacing.sm) {
                ForEach(findings) { JWTFindingRowView(finding: $0) }
            }
        }
    }

    // MARK: - Actions

    private func paste() {
        if let clip = NSPasteboard.general.string(forType: .string) {
            token = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
