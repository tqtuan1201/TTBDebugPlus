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
        .onChange(of: selectedFormat) { _, _ in
            convert()
        }
        .onChange(of: jsonString) { _, _ in
            convert()
        }
        .onAppear {
            convert()
        }
    }
    
    // MARK: - Header
    private var convertHeader: some View {
        HStack(spacing: 12) {
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
            HStack(spacing: 3) {
                ForEach(ConvertFormat.allCases.filter { $0 != .json }) { format in
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedFormat = format
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: format.icon)
                                .font(.ttIcon(TTIcon.sm))
                            Text(format.rawValue)
                                .font(TTFont.labelMedium)
                        }
                        .foregroundColor(selectedFormat == format ? .white : .ttTextTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
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
            .padding(3)
            .background(
                Capsule()
                    .fill(Color.ttSurface.opacity(0.2))
            )
            
            Spacer()
            
            // Output size
            if let result = convertResult, result.isSuccess {
                Text(formatBytes(result.output.utf8.count))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.ttTextMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.ttSurface.opacity(0.3))
                    )
            }
            
            // Copy
            Button(action: copyResult) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.ttIcon(TTIcon.sm))
                    Text(isCopied ? "Copied!" : "Copy")
                        .font(TTFont.labelSmall)
                }
                .foregroundColor(isCopied ? .ttSuccess : .ttTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCopied ? Color.ttSuccess.opacity(0.08) : Color.ttSurface.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(convertResult?.isSuccess != true)
            
            // Save
            Button(action: saveResult) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.ttIcon(TTIcon.sm))
                    Text("Save")
                        .font(TTFont.labelSmall)
                }
                .foregroundColor(.ttTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.ttSurface.opacity(0.3))
                )
            }
            .buttonStyle(.plain)
            .disabled(convertResult?.isSuccess != true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.ttSurface.opacity(0.1))
    }
    
    // MARK: - Result
    private func resultView(_ output: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(output)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.ttTextPrimary)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            // Format badge
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: selectedFormat.icon)
                            .font(.ttIcon(TTIcon.xs))
                        Text(selectedFormat.rawValue)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.ttPrimary.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.ttSurface.opacity(0.8))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                    .padding(12)
                }
                Spacer()
            }
        )
    }
    
    // MARK: - States
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.5))
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 24))
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ttWarning.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.ttWarning)
            }
            Text("Conversion Error")
                .font(TTFont.heading3)
                .foregroundColor(.ttWarning)
            Text(error)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingState: some View {
        VStack(spacing: 10) {
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
                try? output.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
