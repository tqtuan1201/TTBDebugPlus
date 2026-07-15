//
//  JSONConvertView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Format converter: JSON ↔ YAML, XML, CSV
//

import SwiftUI

struct JSONConvertView: View {
    let jsonString: String
    @State private var selectedFormat: ConvertFormat = .yaml
    @State private var convertResult: ConvertResult?
    @State private var isCopied: Bool = false
    @State private var hoveredFormat: ConvertFormat? = nil
    @State private var fileErrorMessage: String?

    private enum DefaultsKey {
        static let selectedFormat = "devTools.jsonConvert.selectedFormat"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            convertHeader
            
            Divider().background(Color.ttBorder.opacity(0.3))
            
            if jsonString.isEmpty {
                emptyState
            } else if let result = convertResult {
                if let error = result.error {
                    errorState(error)
                } else {
                    resultView(result.output)
                }
            } else {
                loadingState
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: selectedFormat) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.selectedFormat)
            convert()
        }
        .onChange(of: jsonString) { _, _ in
            convert()
        }
        .onAppear {
            restoreState()
            convert()
        }
        .alert("Save Failed", isPresented: Binding(
            get: { fileErrorMessage != nil },
            set: { if !$0 { fileErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { fileErrorMessage = nil }
        } message: {
            Text(fileErrorMessage ?? "")
        }
    }
    
    // MARK: - Header
    private var convertHeader: some View {
        HStack(spacing: TTSpacing.md) {
            // Icon with glow
            ZStack {
                Circle()
                    .fill(Color.ttPrimary.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.triangle.swap")
                    .font(.ttIcon(TTIcon.lg))
                    .foregroundColor(.ttPrimary)
            }
            
            Text("Convert to:")
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextSecondary)
            
            // Format picker — pill style
            HStack(spacing: TTSpacing.inlineGapSmall) {
                ForEach(ConvertFormat.allCases.filter { $0 != .json }) { format in
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedFormat = format
                        }
                    }) {
                        HStack(spacing: TTSpacing.tight) {
                            Image(systemName: format.icon)
                                .font(.ttIcon(TTIcon.sm))
                            Text(format.rawValue)
                                .font(TTFont.labelMedium)
                        }
                        .foregroundColor(selectedFormat == format ? .white : .ttTextTertiary)
                        .padding(.horizontal, TTSpacing.md)
                        .padding(.vertical, TTSpacing.xs)
                        .background(
                            Capsule()
                                .fill(selectedFormat == format ? Color.ttPrimary.opacity(0.5) : 
                                      (hoveredFormat == format ? Color.ttSurface.opacity(0.6) : Color.clear))
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredFormat = isHovered ? format : nil
                    }
                }
            }
            .padding(TTSpacing.inlineGapSmall)
            .background(
                Capsule()
                    .fill(Color.ttSurface.opacity(0.2))
            )
            
            Spacer()
            
            // Output size
            if let result = convertResult, result.isSuccess {
                Text(formatBytes(result.output.utf8.count))
                    .font(TTFont.badge)
                    .foregroundColor(.ttTextMuted)
                    .padding(.horizontal, TTSpacing.xs)
                    .padding(.vertical, TTSpacing.xxxs)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.ttSurface.opacity(0.3))
                    )
            }
            
            // Copy
            Button(action: copyResult) {
                HStack(spacing: TTSpacing.xxs) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.ttIcon(TTIcon.sm))
                    Text(isCopied ? "Copied!" : "Copy")
                        .font(TTFont.labelSmall)
                }
                .foregroundColor(isCopied ? .ttSuccess : .ttTextSecondary)
                .padding(.horizontal, TTSpacing.inputPaddingH)
                .padding(.vertical, TTSpacing.tight)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCopied ? Color.ttSuccess.opacity(0.08) : Color.ttSurface.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(convertResult?.isSuccess != true)
            
            // Save
            Button(action: saveResult) {
                HStack(spacing: TTSpacing.xxs) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.ttIcon(TTIcon.sm))
                    Text("Save")
                        .font(TTFont.labelSmall)
                }
                .foregroundColor(.ttTextSecondary)
                .padding(.horizontal, TTSpacing.inputPaddingH)
                .padding(.vertical, TTSpacing.tight)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.ttSurface.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(convertResult?.isSuccess != true)
        }
        .padding(.horizontal, TTSpacing.chromeInsetH)
        .padding(.vertical, TTSpacing.inputPaddingH)
        .background(Color.ttSurface.opacity(0.1))
    }
    
    // MARK: - Result
    private func resultView(_ output: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(output)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .textSelection(.enabled)
                .padding(TTSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            // Format badge
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: TTSpacing.xxs) {
                        Image(systemName: selectedFormat.icon)
                            .font(.ttIcon(TTIcon.xs))
                        Text(selectedFormat.rawValue)
                            .font(TTFont.badge)
                    }
                    .foregroundColor(.ttPrimary.opacity(0.6))
                    .padding(.horizontal, TTSpacing.sm)
                    .padding(.vertical, TTSpacing.inlineGapSmall)
                    .background(
                        Capsule()
                            .fill(Color.ttSurface.opacity(0.8))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                    .padding(TTSpacing.md)
                }
                Spacer()
            }
        )
    }
    
    // MARK: - States
    
    private var emptyState: some View {
        VStack(spacing: TTSpacing.chromeInsetH) {
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.5))
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.triangle.swap")
                    .font(TTFont.heading1)
                    .foregroundColor(.ttTextMuted)
            }
            Text("No JSON Data")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextSecondary)
            Text("Enter or paste JSON in the Editor tab first")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorState(_ error: String) -> some View {
        VStack(spacing: TTSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.ttWarning.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(TTFont.heading1)
                    .foregroundColor(.ttWarning)
            }
            Text("Conversion Error")
                .font(TTFont.heading3)
                .foregroundColor(.ttWarning)
            Text(error)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TTSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingState: some View {
        VStack(spacing: TTSpacing.inputPaddingH) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.ttPrimary)
            Text("Converting...")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func convert() {
        guard !jsonString.isEmpty else {
            convertResult = nil
            return
        }
        
        let input = jsonString
        let format = selectedFormat
        Task.detached(priority: .userInitiated) {
            let result: ConvertResult
            switch format {
            case .yaml: result = JSONConvertEngine.toYAML(input)
            case .xml: result = JSONConvertEngine.toXML(input)
            case .csv: result = JSONConvertEngine.toCSV(input)
            case .json: result = ConvertResult(output: input, error: nil)
            }
            
            await MainActor.run {
                convertResult = result
            }
        }
    }
    
    private func copyResult() {
        guard let output = convertResult?.output else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
    }
    
    private func saveResult() {
        guard let output = convertResult?.output else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "data.\(selectedFormat.fileExtension)"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try output.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    fileErrorMessage = "Could not save converted output: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func restoreState() {
        guard let rawFormat = UserDefaults.standard.string(forKey: DefaultsKey.selectedFormat),
              let format = ConvertFormat(rawValue: rawFormat),
              format != .json else { return }
        selectedFormat = format
    }
}
