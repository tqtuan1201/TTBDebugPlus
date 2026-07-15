//
//  BugReportComposerView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-28.
//  Structured bug report form — Marker.io inspired, with Markdown export
//

import SwiftUI

struct BugReportComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionManager.self) var connectionManager
    
    @State private var report: BugReport
    @State private var showCopiedToast = false
    @State private var showSavedToast = false
    
    let screenshots: [NSImage]
    var onSave: ((BugReport) -> Void)?
    
    init(screenshots: [NSImage] = [], deviceInfo: DeviceInfoSnapshot = .empty, onSave: ((BugReport) -> Void)? = nil) {
        self.screenshots = screenshots
        self.onSave = onSave
        _report = State(initialValue: BugReport(deviceInfo: deviceInfo))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider().background(Color.ttBorder)
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: TTSpacing.xl) {
                    titleSection
                    severityAndTagsSection
                    screenshotsSection
                    reproStepsSection
                    expectedActualSection
                    notesSection
                    environmentSection
                }
                .padding(TTSpacing.xxl)
            }
            
            Divider().background(Color.ttBorder)
            
            // Footer actions
            footer
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 600, idealHeight: 800)
        .background(Color.ttBackground)
        .onAppear {
            populateDeviceInfo()
        }
        .overlay(alignment: .top) {
            if showCopiedToast {
                toastView(text: "Markdown copied to clipboard!", icon: "doc.on.clipboard")
            }
            if showSavedToast {
                toastView(text: "Report saved!", icon: "checkmark.circle")
            }
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            Image(systemName: AppIcon.app)
                .font(.ttIcon(TTIcon.xxl))
                .foregroundColor(.ttError)
            Text("BUG REPORT")
                .font(TTFont.sidebarHeader)
                .foregroundColor(.ttTextPrimary)
                .tracking(1.2)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(TTFont.labelMedium)
                    .foregroundColor(.ttTextTertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, TTSpacing.xxl)
        .padding(.vertical, TTSpacing.lg)
        .background(Color.ttSurface.opacity(0.5))
    }
    
    // MARK: - Title
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            sectionLabel("Title")
            TextField("Brief description of the issue", text: $report.title)
                .textFieldStyle(.roundedBorder)
                .font(TTFont.heading3)
                .foregroundColor(.ttTextPrimary)
        }
    }
    
    // MARK: - Severity & Tags
    private var severityAndTagsSection: some View {
        HStack(alignment: .top, spacing: TTSpacing.xxl) {
            // Severity
            VStack(alignment: .leading, spacing: TTSpacing.xs) {
                sectionLabel("Severity")
                HStack(spacing: TTSpacing.xs) {
                    ForEach(Severity.allCases, id: \.self) { severity in
                        Button(action: { report.severity = severity }) {
                            HStack(spacing: TTSpacing.xxs) {
                                Text(severity.emoji)
                                    .font(.ttIcon(TTIcon.lg))
                                Text(severity.rawValue)
                                    .font(TTFont.labelSmall)
                            }
                            .padding(.horizontal, TTSpacing.inputPaddingH)
                            .padding(.vertical, TTSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(report.severity == severity ? Color.ttPrimary.opacity(0.15) : Color.ttSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(report.severity == severity ? Color.ttPrimary : Color.ttBorder.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .foregroundColor(report.severity == severity ? .ttPrimary : .ttTextSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Tags
            VStack(alignment: .leading, spacing: TTSpacing.xs) {
                sectionLabel("Tags")
                FlowLayout(spacing: TTSpacing.xs) {
                    ForEach(ReportTag.allCases, id: \.self) { tag in
                        Button(action: {
                            if report.tags.contains(tag) {
                                report.tags.remove(tag)
                            } else {
                                report.tags.insert(tag)
                            }
                        }) {
                            HStack(spacing: TTSpacing.xxs) {
                                Text(tag.icon)
                                    .font(.ttIcon(TTIcon.md))
                                Text(tag.label)
                                    .font(TTFont.labelSmall)
                            }
                            .padding(.horizontal, TTSpacing.sm)
                            .padding(.vertical, TTSpacing.tight)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(report.tags.contains(tag) ? Color.ttPrimary.opacity(0.15) : Color.ttSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(report.tags.contains(tag) ? Color.ttPrimary : Color.ttBorder.opacity(0.5), lineWidth: 1)
                                    )
                            )
                            .foregroundColor(report.tags.contains(tag) ? .ttPrimary : .ttTextTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Screenshots
    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            sectionLabel("Screenshots (\(screenshots.count))")
            
            if screenshots.isEmpty {
                Text("No screenshots attached")
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextTertiary)
                    .padding(.vertical, TTSpacing.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TTSpacing.sm) {
                        ForEach(0..<screenshots.count, id: \.self) { i in
                            Image(nsImage: screenshots[i])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.ttBorder, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Reproduction Steps
    private var reproStepsSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            sectionLabel("Reproduction Steps")
            
            ForEach(report.reproSteps.indices, id: \.self) { i in
                HStack(spacing: TTSpacing.sm) {
                    // Step number
                    Text("\(i + 1).")
                        .font(TTFont.codeMedium)
                        .foregroundColor(.ttPrimary)
                        .frame(width: 24, alignment: .trailing)
                    
                    TextField("Step \(i + 1)", text: $report.reproSteps[i])
                        .textFieldStyle(.roundedBorder)
                        .font(TTFont.bodyMedium)
                        .foregroundColor(.ttTextPrimary)
                    
                    // Remove button
                    if report.reproSteps.count > 1 {
                        Button(action: {
                            report.reproSteps.remove(at: i)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.ttIcon(TTIcon.xl))
                                .foregroundColor(.ttTextTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button(action: {
                report.reproSteps.append("")
            }) {
                HStack(spacing: TTSpacing.xxs) {
                    Image(systemName: "plus.circle")
                    Text("Add Step")
                }
                .font(TTFont.labelSmall)
            }
            .buttonStyle(.ttGhost)
        }
    }
    
    // MARK: - Expected / Actual
    private var expectedActualSection: some View {
        HStack(alignment: .top, spacing: TTSpacing.lg) {
            VStack(alignment: .leading, spacing: TTSpacing.xs) {
                sectionLabel("Expected Result")
                TextEditor(text: $report.expectedResult)
                    .font(TTFont.bodyMedium)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(TTSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.ttSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                            )
                    )
            }
            
            VStack(alignment: .leading, spacing: TTSpacing.xs) {
                sectionLabel("Actual Result")
                TextEditor(text: $report.actualResult)
                    .font(TTFont.bodyMedium)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(TTSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.ttSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                            )
                    )
            }
        }
    }
    
    // MARK: - Notes
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            sectionLabel("Additional Notes")
            TextEditor(text: $report.notes)
                .font(TTFont.bodyMedium)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(TTSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.ttSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.ttBorder.opacity(0.5), lineWidth: 1)
                        )
                )
        }
    }
    
    // MARK: - Environment
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: TTSpacing.xs) {
            sectionLabel("Environment (auto-filled)")
            
            VStack(spacing: TTSpacing.xxs) {
                envRow("Device", report.deviceInfo.deviceName)
                envRow("OS", report.deviceInfo.osVersion)
                envRow("App", "\(report.deviceInfo.appName) v\(report.deviceInfo.appVersion)")
                envRow("Screen", report.deviceInfo.screenResolution)
                envRow("SDK", report.deviceInfo.sdkVersion)
                if report.deviceInfo.isSimulator {
                    envRow("Type", "Simulator")
                }
            }
            .padding(TTSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ttSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.ttBorder.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    private func envRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("•")
                .foregroundColor(.ttTextTertiary)
            Text(label)
                .font(TTFont.labelSmall)
                .foregroundColor(.ttTextTertiary)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextSecondary)
            Spacer()
        }
    }
    
    // MARK: - Footer
    private var footer: some View {
        HStack(spacing: TTSpacing.sm) {
            // Copy as… (Markdown / Slack / Jira)
            Menu {
                Button(action: { copyText(.markdown) }) { Label("Copy as Markdown", systemImage: "doc.plaintext") }
                Button(action: { copyText(.slack) }) { Label("Copy for Slack", systemImage: "bubble.left.and.bubble.right") }
                Button(action: { copyText(.jira) }) { Label("Copy for Jira", systemImage: "ladybug") }
            } label: {
                HStack(spacing: TTSpacing.xs) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Copy as…")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Copy formatted report to clipboard (Markdown, Slack, or Jira)")
            
            // Save Report
            Button(action: saveReport) {
                HStack(spacing: TTSpacing.xs) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Report")
                }
            }
            .buttonStyle(.ttSecondary)
            .help("Save report to app storage")
            
            Spacer()
            
            // Share
            Button(action: shareReport) {
                HStack(spacing: TTSpacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
            }
            .buttonStyle(.ttPrimary)
            .disabled(report.title.isEmpty)
        }
        .padding(.horizontal, TTSpacing.xxl)
        .padding(.vertical, TTSpacing.md)
        .background(Color.ttSurface.opacity(0.5))
    }
    
    // MARK: - Helpers
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(TTFont.sidebarHeader)
            .foregroundColor(.ttTextTertiary)
            .tracking(0.8)
    }
    
    private func toastView(text: String, icon: String) -> some View {
        HStack(spacing: TTSpacing.xs) {
            Image(systemName: icon)
                .foregroundColor(.ttSuccess)
            Text(text)
                .font(TTFont.labelMedium)
                .foregroundColor(.ttTextPrimary)
        }
        .padding(.horizontal, TTSpacing.lg)
        .padding(.vertical, TTSpacing.inputPaddingH)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ttSurface)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .padding(.top, TTSpacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Actions
    private func populateDeviceInfo() {
        guard let device = connectionManager.selectedDevice else { return }
        report.deviceInfo = DeviceInfoSnapshot(
            deviceName: device.displayName,
            osVersion: device.osVersionString,
            appName: device.appNameString,
            appVersion: device.deviceInfo?.appVersion ?? "—",
            sdkVersion: device.deviceInfo?.sdkVersion ?? "—",
            screenResolution: {
                if let info = device.deviceInfo {
                    return "\(Int(info.screenWidth))×\(Int(info.screenHeight))pt"
                }
                return "—"
            }(),
            isSimulator: device.isSimulator
        )
    }
    
    private func copyText(_ format: MetadataFormat) {
        let text: String
        switch format {
        case .slack: text = report.toSlack()
        case .jira:  text = report.toJira()
        default:     text = report.toMarkdown()
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopiedToast = false }
        }
    }
    
    private func saveReport() {
        // Save screenshots
        var fileNames: [String] = []
        for (i, img) in screenshots.enumerated() {
            let fileName = "\(report.id.uuidString)_\(i).png"
            if let name = BugReportStorage.shared.saveScreenshot(img, fileName: fileName) {
                fileNames.append(name)
            }
        }
        report.screenshotFileNames = fileNames
        report.updatedAt = Date()
        BugReportStorage.shared.saveReport(report)
        
        onSave?(report)
        
        withAnimation { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedToast = false }
        }
    }
    
    private func shareReport() {
        let md = report.toMarkdown()
        let picker = NSSharingServicePicker(items: [md])
        if let contentView = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}

#Preview {
    BugReportComposerView()
        .environment(ConnectionManager())
        .frame(width: 700, height: 800)
        .preferredColorScheme(.dark)
}
