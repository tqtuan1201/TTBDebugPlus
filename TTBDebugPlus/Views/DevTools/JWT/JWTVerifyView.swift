//
//  JWTVerifyView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Verify a JWT signature offline with a shared secret (HMAC) or PEM public key
//  (RSA / ECDSA), plus secret-aware security analysis.
//

import AppKit
import SwiftUI

struct JWTVerifyView: View {
    @Binding var token: String

    @State private var algorithm: JWTAlgorithm = .hs256
    @State private var keyMaterial: String = ""
    @State private var result: JWTVerificationResult?

    private var trimmed: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var decoded: DecodedJWT? {
        guard !trimmed.isEmpty else { return nil }
        return try? JWTDecoder.decode(trimmed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
                JWTSectionCard(
                    title: "Encoded Token",
                    icon: "key.horizontal",
                    accessory: AnyView(JWTCopyButton(text: trimmed))
                ) {
                    JWTMonoEditor(text: $token, placeholder: "Paste the JWT to verify…")
                        .frame(height: 110)
                    HStack(spacing: TTSpacing.sm) {
                        JWTActionButton(title: "Paste", icon: "doc.on.clipboard") { paste() }
                        JWTActionButton(title: "Clear", icon: "xmark.circle", disabled: token.isEmpty) {
                            token = ""; result = nil
                        }
                    }
                }

                JWTSectionCard(title: "Signing Key", icon: "lock") {
                    HStack(spacing: TTSpacing.inputPaddingH) {
                        Text("Algorithm").font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
                        Picker("", selection: $algorithm) {
                            ForEach(JWTAlgorithm.allCases.filter { $0 != .none }) { alg in
                                Text(alg.rawValue).tag(alg)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 140)
                        Spacer()
                        if let detected = decoded?.algorithm, detected != algorithm, detected != .none {
                            Button("Use detected: \(detected.rawValue)") { algorithm = detected }
                                .font(TTFont.labelSmall)
                                .buttonStyle(.plain)
                                .foregroundColor(.ttPrimary)
                        }
                    }

                    Text(algorithm.keyPrompt)
                        .font(TTFont.labelMedium)
                        .foregroundColor(.ttTextTertiary)

                    JWTMonoEditor(
                        text: $keyMaterial,
                        placeholder: algorithm.isSymmetric
                            ? "Shared secret…"
                            : "-----BEGIN PUBLIC KEY-----\n…\n-----END PUBLIC KEY-----"
                    )
                    .frame(height: algorithm.isSymmetric ? 60 : 130)

                    JWTActionButton(title: "Verify Signature", icon: "checkmark.seal",
                                    prominent: true, disabled: trimmed.isEmpty) { verify() }
                }

                if let result {
                    resultBanner(result)
                }

                if let decoded {
                    securityCard(for: decoded)
                }
            }
            .padding(TTSpacing.lg)
        }
        .background(Color.ttBackground)
        .onAppear(perform: syncAlgorithm)
        .onChange(of: token) { _, _ in
            result = nil
            syncAlgorithm()
        }
    }

    // MARK: - Result

    private func resultBanner(_ result: JWTVerificationResult) -> some View {
        HStack(spacing: TTSpacing.md) {
            Image(systemName: result.icon)
                .font(TTFont.heading2)
                .foregroundColor(result.color)
            VStack(alignment: .leading, spacing: TTSpacing.inlineGapSmall) {
                Text(result.title).font(TTFont.heading3).foregroundColor(result.color)
                Text(result.message).font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(TTSpacing.chromeInsetH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(result.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(result.color.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func securityCard(for decoded: DecodedJWT) -> some View {
        let findings = JWTSecurityAnalyzer.analyze(decoded, hmacSecret: algorithm.isSymmetric ? keyMaterial : nil)
        return JWTSectionCard(title: "Security Analysis", icon: "shield.lefthalf.filled") {
            VStack(spacing: TTSpacing.sm) {
                ForEach(findings) { JWTFindingRowView(finding: $0) }
            }
        }
    }

    // MARK: - Actions

    private func syncAlgorithm() {
        if let detected = decoded?.algorithm, detected != .none {
            algorithm = detected
        }
    }

    private func verify() {
        guard let decoded else {
            result = JWTVerificationResult(status: .error("Token could not be decoded."),
                                           algorithm: algorithm, message: "Check that the token is well-formed.")
            return
        }
        guard !keyMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = JWTVerificationResult(status: .unverified, algorithm: algorithm,
                                           message: "Provide a \(algorithm.isSymmetric ? "secret" : "public key") to verify.")
            return
        }
        do {
            let ok = try JWTCrypto.verify(decoded: decoded, algorithm: algorithm, key: keyMaterial)
            if ok {
                result = JWTVerificationResult(
                    status: .valid, algorithm: algorithm,
                    message: "The signature matches using \(algorithm.displayName). The token is authentic for this key.")
            } else {
                result = JWTVerificationResult(
                    status: .invalid, algorithm: algorithm,
                    message: "The signature does not match this key/secret for \(algorithm.rawValue). The token may be forged, altered, or the wrong key was used.")
            }
        } catch {
            result = JWTVerificationResult(status: .error(error.localizedDescription),
                                           algorithm: algorithm, message: error.localizedDescription)
        }
    }

    private func paste() {
        if let clip = NSPasteboard.general.string(forType: .string) {
            token = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
