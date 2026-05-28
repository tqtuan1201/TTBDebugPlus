//
//  CaseConverterToolView.swift
//  TTBDebugPlus
//
//  Created by Codex on 2026-05-27.
//  Case converter for text input payloads
//

import AppKit
import SwiftUI

struct CaseConverterToolView: View {
    @State private var inputText = ""
    @State private var selectedMode: CaseConversionMode = .lower
    @State private var isCopied = false
    
    private var outputText: String {
        CaseConverterEngine.convert(inputText, mode: selectedMode)
    }
    
    private var inputWords: Int {
        CaseConverterEngine.wordCount(inputText)
    }
    
    private var inputCharacters: Int {
        CaseConverterEngine.characterCount(inputText)
    }
    
    private var outputCharacters: Int {
        CaseConverterEngine.characterCount(outputText)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            controlsPanel
                .frame(width: 340)
            
            Divider().background(Color.ttBorder.opacity(0.3))
            
            editorPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
        .frame(minWidth: 860, minHeight: 540)
    }
    
    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBlock
                
                sectionCard(title: "Conversion", icon: selectedMode.icon) {
                    modeGrid
                    
                    Text(selectedMode.description)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                sectionCard(title: "Text Stats", icon: "number") {
                    statRow(title: "Words", value: "\(inputWords)")
                    statRow(title: "Characters", value: "\(inputCharacters)")
                    statRow(title: "Output Characters", value: "\(outputCharacters)")
                }
                
                sectionCard(title: "Actions", icon: "wand.and.stars") {
                    HStack(spacing: 8) {
                        actionButton(title: "Paste", icon: "doc.on.clipboard", disabled: false) {
                            pasteFromClipboard()
                        }
                        
                        actionButton(title: "Clear", icon: "xmark.circle", disabled: inputText.isEmpty) {
                            inputText = ""
                        }
                    }
                    
                    HStack(spacing: 8) {
                        actionButton(title: isCopied ? "Copied" : "Copy", icon: isCopied ? "checkmark.circle.fill" : "doc.on.doc", disabled: outputText.isEmpty) {
                            copyOutput()
                        }
                        
                        actionButton(title: "Apply", icon: "arrow.left.to.line", disabled: outputText.isEmpty) {
                            inputText = outputText
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.ttSurface.opacity(0.08))
    }
    
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(Color.ttPrimary.opacity(0.16))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "textformat.abc")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.ttPrimaryLight)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text("Case Converter")
                    .font(TTFont.heading2)
                    .foregroundColor(.ttTextPrimary)
                
                Text("Convert text between title, sentence, uppercase, lowercase, alternate, and toggle cases.")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var modeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
            ForEach(CaseConversionMode.allCases) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedMode = mode
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.ttIcon(TTIcon.md))
                        Text(mode.rawValue)
                            .font(TTFont.labelSmall)
                            .lineLimit(1)
                    }
                    .foregroundColor(selectedMode == mode ? .white : .ttTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: TTRadius.sm)
                            .fill(selectedMode == mode ? Color.ttPrimary.opacity(0.55) : Color.ttSurface.opacity(0.42))
                    )
                }
                .buttonStyle(.plain)
                .help(mode.description)
            }
        }
    }
    
    private var editorPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(selectedMode.rawValue, systemImage: selectedMode.icon)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
                
                Spacer()
                
                Text("\(inputWords) words")
                    .font(TTFont.badge)
                    .foregroundColor(.ttTextMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: TTRadius.xs)
                            .fill(Color.ttSurface.opacity(0.35))
                    )
                
                Button(action: copyOutput) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(TTFont.labelSmall)
                        .foregroundColor(isCopied ? .ttSuccess : .ttTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .fill(isCopied ? Color.ttSuccess.opacity(0.1) : Color.ttSurface.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(outputText.isEmpty)
                .help("Copy converted text")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.ttSurface.opacity(0.1))
            
            Divider().background(Color.ttBorder.opacity(0.3))
            
            HStack(spacing: 0) {
                textInputPane
                
                Divider().background(Color.ttBorder.opacity(0.25))
                
                textOutputPane
            }
        }
    }
    
    private var textInputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHeader(title: "Input", icon: "square.and.pencil", count: inputCharacters)
            
            TextEditor(text: $inputText)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(10)
                .overlay(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Paste or type text to convert...")
                            .font(TTFont.codeMedium)
                            .foregroundColor(.ttTextMuted)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .fill(Color.ttBackground.opacity(0.58))
                        .overlay(
                            RoundedRectangle(cornerRadius: TTRadius.md)
                                .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                        )
                )
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var textOutputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            paneHeader(title: "Output", icon: "text.alignleft", count: outputCharacters)
            
            ScrollView {
                Text(outputText.isEmpty ? "Converted text will appear here." : outputText)
                    .font(TTFont.codeMedium)
                    .foregroundColor(outputText.isEmpty ? .ttTextMuted : .ttTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(Color.ttBackground.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: TTRadius.md)
                            .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                    )
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextSecondary)
            
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(Color.ttSurface.opacity(0.36))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                )
        )
    }
    
    private func paneHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(TTFont.labelLarge)
                .foregroundColor(.ttTextSecondary)
            
            Spacer()
            
            Text("\(count) chars")
                .font(TTFont.badge)
                .foregroundColor(.ttTextMuted)
        }
    }
    
    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextSecondary)
            
            Spacer()
            
            Text(value)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextPrimary)
        }
    }
    
    private func actionButton(
        title: String,
        icon: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(TTFont.labelSmall)
                .foregroundColor(disabled ? .ttTextMuted : .ttTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(disabled ? Color.ttSurface.opacity(0.18) : Color.ttSurface.opacity(0.42))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
    
    private func pasteFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else { return }
        inputText = clipboardText
    }
    
    private func copyOutput() {
        guard !outputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }
}

#Preview {
    CaseConverterToolView()
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.dark)
}
