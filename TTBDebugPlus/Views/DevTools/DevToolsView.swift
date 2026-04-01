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
    @State private var selectedTool: DevTool = .json
    @State private var viewModel = JSONEditorViewModel()
    @State private var selectedJsonTool: JSONTool = .editor
    @State private var hoveredJsonTool: JSONTool? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: Tool category selector
            toolHeader
            
            // Sub-tool header (for JSON category)
            if selectedTool == .json {
                jsonSubToolHeader
            }
            
            // Content — fills all remaining space
            switch selectedTool {
            case .json:
                jsonContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                comingSoonView(selectedTool)
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadPayloadIfNeeded()
        }
        .onChange(of: appState.jsonEditorPayload) { _, _ in
            loadPayloadIfNeeded()
        }
    }
    
    // MARK: - Tool Header (Category Tabs)
    private var toolHeader: some View {
        HStack(spacing: 0) {
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
                            (selectedTool == tool ? .ttPrimary : .ttTextSecondary)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            Rectangle()
                                .fill(selectedTool == tool ? Color.ttPrimary : Color.clear)
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
}

#Preview {
    DevToolsView()
        .environment(AppState())
        .frame(width: 1100, height: 700)
        .preferredColorScheme(.dark)
}
