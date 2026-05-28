//
//  DevToolsView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Container for Dev Tools — JSON category with sub-tools, extensible for future tools
//

import SwiftUI

struct DevToolsView: View {
    @Environment(AppState.self) var appState
    @State private var selectedTool: DevTool? = nil
    @State private var viewModel = JSONEditorViewModel()
    @State private var selectedJsonTool: JSONTool = .editor
    @State private var hoveredJsonTool: JSONTool? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if let selectedTool {
                toolDetailHeader(selectedTool)
                
                // Sub-tool header (for JSON category)
                if selectedTool == .json {
                    jsonSubToolHeader
                }
                
                // Content — fills all remaining space
                switch selectedTool {
                case .json:
                    jsonContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .qrCode:
                    QRCodeToolView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .caseConverter:
                    CaseConverterToolView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    comingSoonView(selectedTool)
                }
            } else {
                devToolsMenu
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadPayloadIfNeeded()
            openRequestedToolIfNeeded()
        }
        .onChange(of: appState.jsonEditorPayload) { _, _ in
            loadPayloadIfNeeded()
        }
        .onChange(of: appState.devToolsMenuRequestID) { _, _ in
            selectedTool = nil
            selectedJsonTool = .editor
        }
        .onChange(of: appState.devToolsToolRequestID) { _, _ in
            openRequestedToolIfNeeded()
        }
        .alert("File Operation Failed", isPresented: Binding(
            get: { viewModel.fileErrorMessage != nil },
            set: { if !$0 { viewModel.fileErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.fileErrorMessage = nil }
        } message: {
            Text(viewModel.fileErrorMessage ?? "")
        }
    }
    
    // MARK: - Dev Tools Menu
    private var devToolsMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dev Tools")
                    .font(TTFont.heading1)
                    .foregroundColor(.ttTextPrimary)
                
                Text("Select a utility to inspect, transform, or debug development payloads.")
                    .font(TTFont.bodyMedium)
                    .foregroundColor(.ttTextSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)
            
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(DevTool.allCases) { tool in
                        devToolCard(tool)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func devToolCard(_ tool: DevTool) -> some View {
        Button(action: {
            guard tool.isAvailable else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedTool = tool
                if tool == .json {
                    selectedJsonTool = .editor
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: TTRadius.md)
                            .fill(tool.isAvailable ? Color.ttPrimary.opacity(0.18) : Color.ttSurfaceLight.opacity(0.35))
                            .frame(width: 42, height: 42)
                        
                        Image(systemName: tool.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(tool.isAvailable ? .ttPrimaryLight : .ttTextMuted)
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tool.menuTitle)
                            .font(TTFont.heading3)
                            .foregroundColor(tool.isAvailable ? .ttTextPrimary : .ttTextMuted)
                            .lineLimit(1)
                        
                        Text(tool.statusText)
                            .font(TTFont.badge)
                            .foregroundColor(tool.isAvailable ? .ttSuccess : .ttWarning)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill((tool.isAvailable ? Color.ttSuccess : Color.ttWarning).opacity(0.12))
                            )
                    }
                    
                    Spacer(minLength: 0)
                }
                
                Text(tool.menuDescription)
                    .font(TTFont.bodySmall)
                    .foregroundColor(tool.isAvailable ? .ttTextSecondary : .ttTextTertiary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                if tool == .json {
                    HStack(spacing: 5) {
                        ForEach(JSONTool.allCases) { jsonTool in
                            Image(systemName: jsonTool.icon)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.ttTextTertiary)
                            .help(jsonTool.rawValue)
                        }
                    }
                } else if tool == .qrCode {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Image(systemName: "doc.on.clipboard")
                        Image(systemName: AppIcon.qrCode)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.ttTextTertiary)
                } else if tool == .caseConverter {
                    HStack(spacing: 5) {
                        Image(systemName: "textformat.size")
                        Image(systemName: "a.square")
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.ttTextTertiary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(Color.ttSurface.opacity(tool.isAvailable ? 0.48 : 0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: TTRadius.md)
                            .stroke(tool.isAvailable ? Color.ttBorder.opacity(0.35) : Color.ttBorder.opacity(0.16), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: TTRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(!tool.isAvailable)
        .help(tool.isAvailable ? "Open \(tool.menuTitle)" : "\(tool.menuTitle) — Coming Soon")
    }
    
    // MARK: - Tool Header (Category Tabs)
    private func toolDetailHeader(_ currentTool: DevTool) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.16)) {
                    selectedTool = nil
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dev Tools")
                        .font(TTFont.tabLabel)
                }
                .foregroundColor(.ttTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .help("Back to Dev Tools menu")
            
            Rectangle()
                .fill(Color.ttBorder.opacity(0.25))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)
            
            HStack(spacing: 2) {
                ForEach(DevTool.allCases) { tool in
                    Button(action: {
                        if tool.isAvailable {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTool = tool
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tool.icon)
                                .font(.ttIcon(TTIcon.md))
                            Text(tool.rawValue)
                                .font(TTFont.tabLabel)
                        }
                        .foregroundColor(
                            !tool.isAvailable ? .ttTextMuted :
                            (currentTool == tool ? .ttPrimary : .ttTextSecondary)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            Rectangle()
                                .fill(currentTool == tool ? Color.ttPrimary : Color.clear)
                                .frame(height: 2),
                            alignment: .bottom
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!tool.isAvailable)
                    .help(tool.isAvailable ? tool.rawValue : "\(tool.rawValue) — Coming Soon")
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.ttSurface.opacity(0.2))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - JSON Sub-Tool Header
    private var jsonSubToolHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(JSONTool.allCases) { tool in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            selectedJsonTool = tool
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: tool.icon)
                                .font(.ttIcon(TTIcon.sm))
                            Text(tool.rawValue)
                                .font(TTFont.labelMedium)
                        }
                        .foregroundColor(
                            selectedJsonTool == tool ? .white :
                            (hoveredJsonTool == tool ? .ttTextSecondary : .ttTextTertiary)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    selectedJsonTool == tool ? Color.ttPrimary.opacity(0.4) :
                                    (hoveredJsonTool == tool ? Color.ttSurface.opacity(0.4) : Color.clear)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        hoveredJsonTool = isHovered ? tool : nil
                    }
                    .help(tool.description)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .frame(minHeight: 32)
        .background(Color.ttSurface.opacity(0.08))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.12)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - JSON Content (routed by JSONTool)
    @ViewBuilder
    private var jsonContent: some View {
        switch selectedJsonTool {
        case .editor:
            OnlineJsonEditorView(viewModel: viewModel)
        case .query:
            JSONQueryView(jsonString: viewModel.rawJSON)
        case .diff:
            JSONDiffView(initialLeft: viewModel.rawJSON)
        case .convert:
            JSONConvertView(jsonString: viewModel.rawJSON)
        case .graph:
            JSONGraphView(jsonString: viewModel.rawJSON)
        }
    }
    
    // MARK: - Coming Soon
    private func comingSoonView(_ tool: DevTool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.5))
                    .frame(width: 80, height: 80)
                Image(systemName: tool.icon)
                    .font(.system(size: 32))
                    .foregroundColor(.ttTextMuted)
            }
            
            Text(tool.rawValue)
                .font(TTFont.heading2)
                .foregroundColor(.ttTextPrimary)
            
            Text("Coming Soon")
                .font(TTFont.bodyMedium)
                .foregroundColor(.ttTextTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.ttSurface.opacity(0.5))
                        .overlay(
                            Capsule()
                                .stroke(Color.ttBorder.opacity(0.2), lineWidth: 0.5)
                        )
                )
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Payload Loading
    private func loadPayloadIfNeeded() {
        if let payload = appState.jsonEditorPayload {
            viewModel.loadJSON(payload.json, source: payload.sourceLabel)
            selectedTool = .json
            selectedJsonTool = .editor
            appState.jsonEditorPayload = nil
        }
    }
    
    private func openRequestedToolIfNeeded() {
        guard let tool = appState.requestedDevTool else { return }
        selectedTool = tool.isAvailable ? tool : nil
        if tool == .json {
            selectedJsonTool = .editor
        }
        appState.requestedDevTool = nil
    }
}

#Preview {
    DevToolsView()
        .environment(AppState())
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.dark)
}
