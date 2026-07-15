//
//  JWTGenerateView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Build and sign a JWT offline from editable header/payload JSON, using a
//  shared secret (HMAC), PEM private key (RSA/ECDSA), or `none` (unsecured).
//

import AppKit
import SwiftUI

struct JWTGenerateView: View {
    /// Push the generated token into the shared decoder/verifier.
    var onSendToDecoder: (String) -> Void = { _ in }

    @State private var headerText = "{\n  \"alg\": \"HS256\",\n  \"typ\": \"JWT\"\n}"
    @State private var payloadText = "{\n  \"sub\": \"1234567890\",\n  \"name\": \"John Doe\"\n}"
    @State private var algorithm: JWTAlgorithm = .hs256
    @State private var keyMaterial = "your-256-bit-secret"
    @State private var output = ""
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            editorPanel
                .frame(width: 460)

            Divider().background(Color.ttBorder.opacity(0.3))

            outputPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
                JWTSectionCard(title: "Header", icon: "number") {
                    JWTMonoEditor(text: $headerText, placeholder: "{ \"alg\": …, \"typ\": \"JWT\" }")
                        .frame(height: 90)
                    Text("`alg` is set automatically to match the selected algorithm on sign.")
                        .font(TTFont.bodySmall).foregroundColor(.ttTextTertiary)
                }

                JWTSectionCard(
                    title: "Payload",
                    icon: "doc.text",
                    accessory: AnyView(
                        HStack(spacing: TTSpacing.xs) {
                            miniButton("iat", "clock") { insertClaim("iat", Int(Date().timeIntervalSince1970)) }
                            miniButton("exp +1h", "clock.badge") {
                                insertClaim("exp", Int(Date().addingTimeInterval(3600).timeIntervalSince1970))
                            }
                        }
                    )
                ) {
                    JWTMonoEditor(text: $payloadText, placeholder: "{ \"sub\": … }")
                        .frame(height: 150)
                }

                JWTSectionCard(title: "Signing Key", icon: "lock") {
                    HStack(spacing: TTSpacing.inputPaddingH) {
                        Text("Algorithm").font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
                        Picker("", selection: $algorithm) {
                            ForEach(JWTAlgorithm.signable) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 140)
                        Spacer()
                    }

                    if algorithm != .none {
                        Text(algorithm.signingKeyPrompt)
                            .font(TTFont.labelMedium).foregroundColor(.ttTextTertiary)
                        JWTMonoEditor(
                            text: $keyMaterial,
                            placeholder: algorithm.isSymmetric
                                ? "Shared secret…"
                                : "-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----"
                        )
                        .frame(height: algorithm.isSymmetric ? 60 : 130)
                    } else {
                        Text("`alg: none` produces an unsecured token with no signature — for testing only.")
                            .font(TTFont.bodySmall).foregroundColor(.ttWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    JWTActionButton(title: "Generate Token", icon: "hammer", prominent: true) { generate() }
                }
            }
            .padding(TTSpacing.lg)
        }
        .background(Color.ttSurface.opacity(0.08))
    }

    // MARK: - Output Panel

    @ViewBuilder
    private var outputPanel: some View {
        if let errorMessage {
            JWTEmptyState(icon: "exclamationmark.triangle", title: "Generation Failed", subtitle: errorMessage)
        } else if output.isEmpty {
            JWTEmptyState(icon: "hammer", title: "No Token Yet",
                          subtitle: "Fill in the header and payload, choose an algorithm and key, then Generate.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.chromeInsetH) {
                    JWTSectionCard(
                        title: "Generated Token",
                        icon: "key.horizontal",
                        accessory: AnyView(JWTCopyButton(text: output))
                    ) {
                        JWTColorizedToken(token: output)
                        HStack(spacing: TTSpacing.sm) {
                            JWTActionButton(title: "Open in Decoder", icon: "arrow.up.forward.app", prominent: true) {
                                onSendToDecoder(output)
                            }
                        }
                    }
                    JWTSectionCard(title: "Length", icon: "ruler") {
                        HStack {
                            Text("Characters").font(TTFont.bodySmall).foregroundColor(.ttTextSecondary)
                            Spacer()
                            Text("\(output.count)").font(TTFont.codeSmall).foregroundColor(.ttTextPrimary)
                        }
                    }
                }
                .padding(TTSpacing.lg)
            }
        }
    }

    // MARK: - Helpers

    private func miniButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttPrimary)
        }
        .buttonStyle(.plain)
        .help("Insert \(title) claim")
    }

    private func generate() {
        do {
            let header = try injectingAlg(into: headerText, algorithm: algorithm)
            output = try JWTCrypto.sign(headerJSON: header, payloadJSON: payloadText,
                                        algorithm: algorithm, key: keyMaterial)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            output = ""
        }
    }

    /// Overwrite the header's `alg` to match the selected algorithm so the token
    /// is internally consistent; default `typ` to JWT when absent.
    private func injectingAlg(into headerJSON: String, algorithm: JWTAlgorithm) throws -> String {
        guard let data = headerJSON.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw JWTError.malformed("header is not a JSON object")
        }
        object["alg"] = algorithm.rawValue
        if object["typ"] == nil { object["typ"] = "JWT" }
        let updated = try JSONSerialization.data(withJSONObject: object,
                                                 options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(data: updated, encoding: .utf8) ?? headerJSON
    }

    private func insertClaim(_ key: String, _ value: Int) {
        guard let data = payloadText.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        object[key] = value
        if let updated = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: updated, encoding: .utf8) {
            payloadText = string
        }
    }
}
