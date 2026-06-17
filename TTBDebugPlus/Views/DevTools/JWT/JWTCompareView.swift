//
//  JWTCompareView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Side-by-side comparison of two JWTs — header algorithm and claim-level diff.
//

import AppKit
import SwiftUI

struct JWTCompareView: View {
    @Binding var tokenA: String
    @State private var tokenB: String = ""

    private enum ClaimStatus {
        case same, changed, onlyA, onlyB
        var color: Color {
            switch self {
            case .same:    return .ttTextSecondary
            case .changed: return .ttWarning
            case .onlyA:   return .ttError
            case .onlyB:   return .ttSuccess
            }
        }
        var label: String {
            switch self {
            case .same: return "="
            case .changed: return "≠"
            case .onlyA: return "−"
            case .onlyB: return "+"
            }
        }
    }

    private struct DiffRow: Identifiable {
        let id = UUID()
        let key: String
        let valueA: String?
        let valueB: String?
        let status: ClaimStatus
    }

    private func decode(_ token: String) -> DecodedJWT? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? JWTDecoder.decode(trimmed)
    }

    private func claimMap(_ decoded: DecodedJWT?) -> [String: String] {
        guard let decoded else { return [:] }
        return Dictionary(decoded.claims.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    private var diffRows: [DiffRow] {
        let a = claimMap(decode(tokenA))
        let b = claimMap(decode(tokenB))
        let keys = Set(a.keys).union(b.keys).sorted()
        return keys.map { key in
            let va = a[key], vb = b[key]
            let status: ClaimStatus
            switch (va, vb) {
            case let (.some(x), .some(y)): status = (x == y) ? .same : .changed
            case (.some, .none):           status = .onlyA
            case (.none, .some):           status = .onlyB
            case (.none, .none):           status = .same
            }
            return DiffRow(key: key, valueA: va, valueB: vb, status: status)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            Divider().background(Color.ttBorder.opacity(0.3))
            comparison
        }
        .background(Color.ttBackground)
    }

    // MARK: - Inputs

    private var inputRow: some View {
        HStack(spacing: 0) {
            tokenInput(title: "Token A", binding: $tokenA, tint: .ttError)
            Divider().background(Color.ttBorder.opacity(0.25))
            tokenInput(title: "Token B", binding: $tokenB, tint: .ttSuccess)
        }
        .frame(height: 150)
    }

    private func tokenInput(title: String, binding: Binding<String>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "key.horizontal")
                    .font(TTFont.labelLarge).foregroundColor(tint)
                Spacer()
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        binding.wrappedValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(TTFont.labelSmall).foregroundColor(.ttTextSecondary)
                }
                .buttonStyle(.plain)
                Button { binding.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 12)).foregroundColor(.ttTextTertiary)
                }
                .buttonStyle(.plain)
                .disabled(binding.wrappedValue.isEmpty)
            }
            JWTMonoEditor(text: binding, placeholder: "Paste \(title)…")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Comparison

    @ViewBuilder
    private var comparison: some View {
        let a = decode(tokenA)
        let b = decode(tokenB)
        if a == nil && b == nil {
            JWTEmptyState(icon: "rectangle.on.rectangle", title: "Nothing to Compare",
                          subtitle: "Paste two JWTs above to see a claim-by-claim diff.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    JWTSectionCard(title: "Header", icon: "number") {
                        diffLine(key: "alg",
                                 valueA: a?.rawAlgorithm, valueB: b?.rawAlgorithm,
                                 status: status(a?.rawAlgorithm, b?.rawAlgorithm))
                        diffLine(key: "typ",
                                 valueA: a?.header["typ"] as? String, valueB: b?.header["typ"] as? String,
                                 status: status(a?.header["typ"] as? String, b?.header["typ"] as? String))
                    }

                    JWTSectionCard(
                        title: "Claims",
                        icon: "list.bullet.rectangle",
                        accessory: AnyView(legend)
                    ) {
                        if diffRows.isEmpty {
                            Text("No claims to compare.")
                                .font(TTFont.bodySmall).foregroundColor(.ttTextTertiary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(diffRows) { row in
                                    diffLine(key: row.key, valueA: row.valueA, valueB: row.valueB, status: row.status)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendChip("changed", .ttWarning)
            legendChip("only A", .ttError)
            legendChip("only B", .ttSuccess)
        }
    }

    private func legendChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(TTFont.badge).foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func status(_ a: String?, _ b: String?) -> ClaimStatus {
        switch (a, b) {
        case let (.some(x), .some(y)): return x == y ? .same : .changed
        case (.some, .none): return .onlyA
        case (.none, .some): return .onlyB
        default: return .same
        }
    }

    private func diffLine(key: String, valueA: String?, valueB: String?, status: ClaimStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(status.label)
                .font(TTFont.codeSmall).foregroundColor(status.color)
                .frame(width: 14)
            Text(key)
                .font(TTFont.codeSmall).foregroundColor(.ttJsonKey)
                .frame(width: 90, alignment: .leading)
            Text(valueA ?? "—")
                .font(TTFont.codeSmall)
                .foregroundColor(valueA == nil ? .ttTextMuted : .ttTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Text(valueB ?? "—")
                .font(TTFont.codeSmall)
                .foregroundColor(valueB == nil ? .ttTextMuted : (status == .changed ? .ttWarning : .ttTextPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.1)).frame(height: 1),
            alignment: .bottom
        )
    }
}
