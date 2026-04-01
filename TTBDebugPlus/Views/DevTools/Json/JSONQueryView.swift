//
//  JSONQueryView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  JSONPath query panel: input + live results with syntax highlighting
//

import SwiftUI

struct JSONQueryView: View {
    let jsonString: String
    @State private var queryPath: String = "$"
    @State private var result: QueryResult = QueryResult(matches: [], error: nil)
    @State private var isQuerying: Bool = false
    @State private var copiedMatchId: UUID? = nil
    
    // Common path suggestions
    private let suggestions = [
        ("$", "Root object"),
        ("$.*", "All top-level values"),
        ("$.data", "Access 'data' key"),
        ("$.data[0]", "First item in 'data' array"),
        ("$.data[*].id", "All 'id' values in 'data' array"),
        ("$..name", "All 'name' values (recursive)"),
        ("$..id", "All 'id' values (recursive)"),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Query input bar
            queryInputBar
            
            Divider().background(Color.ttBorder.opacity(0.3))
            
            // Results
            if jsonString.isEmpty {
                emptyJSONState
            } else if isQuerying {
                loadingState
            } else if let error = result.error {
                errorState(error)
            } else if result.isEmpty {
                noResultsState
            } else {
                resultsList
            }
        }
        .background(Color.ttBackground)
        .frame(minWidth: 400, minHeight: 300)
        .onChange(of: queryPath) { _, _ in
            executeQuery()
        }
        .onAppear {
            executeQuery()
        }
    }
    
    // MARK: - Query Input
    private var queryInputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // JSONPath icon with glow
                ZStack {
                    Circle()
                        .fill(Color.ttPrimary.opacity(0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.ttIcon(TTIcon.lg))
                        .foregroundColor(.ttPrimary)
                }
                
                // Input
                TextField("Enter JSONPath (e.g., $.data[0].name)", text: $queryPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundColor(.ttTextPrimary)
                    .frame(minWidth: 200)
                
                // Result count badge
                if !result.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ttIcon(TTIcon.xs))
                        Text("\(result.count) match\(result.count == 1 ? "" : "es")")
                            .font(TTFont.badge)
                    }
                    .foregroundColor(.ttSuccess)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.ttSuccess.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(Color.ttSuccess.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                }
                
                // Clear
                if queryPath != "$" {
                    Button(action: { queryPath = "$" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ttIcon(TTIcon.lg))
                            .foregroundColor(.ttTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ttSurface.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.ttPrimary.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Suggestions — wrapping
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Try:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.ttTextMuted)
                        .tracking(0.5)
                    
                    ForEach(suggestions, id: \.0) { path, desc in
                        Button(action: { queryPath = path }) {
                            Text(path)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(queryPath == path ? .white : .ttPrimaryLight)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(queryPath == path ? Color.ttPrimary.opacity(0.5) : Color.ttPrimary.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(desc)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.ttSurface.opacity(0.1))
    }
    
    // MARK: - Results
    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(result.matches.enumerated()), id: \.element.id) { index, match in
                    VStack(alignment: .leading, spacing: 6) {
                        // Path + index
                        HStack(spacing: 6) {
                            // Index badge
                            Text("#\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.ttPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.ttPrimary.opacity(0.08))
                                )
                            
                            Image(systemName: "arrow.right")
                                .font(.ttIcon(TTIcon.xxs))
                                .foregroundColor(.ttPrimary.opacity(0.5))
                            
                            Text(match.path)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.ttPrimaryLight)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            // Copy button
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(match.value, forType: .string)
                                copiedMatchId = match.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if copiedMatchId == match.id { copiedMatchId = nil }
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: copiedMatchId == match.id ? "checkmark" : "doc.on.doc")
                                        .font(.ttIcon(TTIcon.xs))
                                    if copiedMatchId == match.id {
                                        Text("Copied")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                }
                                .foregroundColor(copiedMatchId == match.id ? .ttSuccess : .ttTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Value
                        Text(match.value)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.ttJsonString)
                            .textSelection(.enabled)
                            .lineLimit(12)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.ttSurface.opacity(0.25))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.ttBorder.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(
                        Rectangle().fill(Color.ttBorder.opacity(0.08)).frame(height: 1),
                        alignment: .bottom
                    )
                }
            }
        }
    }
    
    // MARK: - States
    
    private var emptyJSONState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.5))
                    .frame(width: 56, height: 56)
                Image(systemName: "doc.text")
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
    
    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.ttPrimary)
            Text("Querying...")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorState(_ error: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.ttWarning.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.ttWarning)
            }
            Text("Query Error")
                .font(TTFont.heading3)
                .foregroundColor(.ttWarning)
            Text(error)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.5))
                    .frame(width: 56, height: 56)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.ttTextMuted)
            }
            Text("No Matches")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextSecondary)
            Text("Try a different JSONPath expression")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Execute
    private func executeQuery() {
        guard !jsonString.isEmpty, !queryPath.isEmpty else { return }
        isQuerying = true
        
        let input = jsonString
        let path = queryPath
        Task.detached(priority: .userInitiated) {
            let queryResult = JSONQueryEngine.query(input, path: path)
            await MainActor.run {
                result = queryResult
                isQuerying = false
            }
        }
    }
}
