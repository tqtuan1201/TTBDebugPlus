//
//  IntegrationGuideView.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  iOS SDK setup guide with numbered steps and copyable code snippets
//

import SwiftUI

struct IntegrationGuideView: View {
    @Environment(ConnectionManager.self) var connectionManager
    @State private var expandedStep: Int? = 1
    @State private var copiedStep: Int? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                header
                
                // Connection status
                connectionStatusBanner
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                
                // Steps
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { step in
                        StepView(
                            step: step,
                            isExpanded: expandedStep == step.number,
                            isCopied: copiedStep == step.number,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedStep = expandedStep == step.number ? nil : step.number
                                }
                            },
                            onCopy: { copyCode(step) }
                        )
                    }
                }
                .padding(.horizontal, 32)
                
                // Troubleshooting
                troubleshootingSection
                    .padding(.horizontal, 32)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
            }
        }
        .background(Color.ttBackground)
    }
    
    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ttPrimary.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: AppIcon.devTools)
                        .font(.ttIcon(TTIcon.xxl))
                        .foregroundColor(.ttPrimary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("iOS SDK Integration")
                        .font(TTFont.displayMedium)
                        .foregroundColor(.ttTextPrimary)
                    Text("Set up your iOS app to send logs to TTBDebugPlus")
                        .font(TTFont.bodyMedium)
                        .foregroundColor(.ttTextSecondary)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Connection Status
    private var connectionStatusBanner: some View {
        let serverRunning = connectionManager.isServerRunning
        let hasDevices = !connectionManager.connectedDevices.isEmpty
        
        return HStack(spacing: 16) {
            statusItem(
                icon: AppIcon.connectionHealth,
                title: "Bonjour Server",
                isOk: serverRunning,
                okText: "Running on _ttbdebug._tcp",
                failText: "Not started — go to menu → Server → Start"
            )
            
            Divider().frame(height: 40)
            
            statusItem(
                icon: AppIcon.device,
                title: "iOS Device",
                isOk: hasDevices,
                okText: "\(connectionManager.connectedDevices.count) device(s) connected",
                failText: "No device found — ensure same Wi-Fi network"
            )
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((serverRunning && hasDevices)
                      ? TTBannerKind.success.background
                      : TTBannerKind.warning.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke((serverRunning && hasDevices)
                                ? TTBannerKind.success.border.opacity(0.55)
                                : TTBannerKind.warning.border.opacity(0.55),
                                lineWidth: 1)
                )
        )
    }
    
    private func statusItem(icon: String, title: String, isOk: Bool, okText: String, failText: String) -> some View {
        let kind: TTBannerKind = isOk ? .success : .warning
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(kind.background)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(kind.border.opacity(0.55), lineWidth: 1))
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.xxl))
                    .foregroundColor(kind.foreground)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(TTFont.labelLarge)
                        .foregroundColor(.ttTextPrimary)
                    Image(systemName: isOk ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.ttIcon(TTIcon.lg))
                        .foregroundColor(kind.foreground)
                }
                Text(isOk ? okText : failText)
                    .font(TTFont.labelSmall)
                    .foregroundColor(kind.foreground)
            }
        }
    }
    
    // MARK: - Steps Data
    // NOTE: These 6 steps mirror TTBDebugPlus/source/README.md's "iOS SDK Integration"
    // section (same content, shown in-app here). Keep both in sync when editing either one.
    private var steps: [IntegrationStep] {
        [
            IntegrationStep(
                number: 1,
                title: "Add TTBaseUIKit to Your Project",
                description: "Add the TTBaseUIKit package which includes the DebugBridge module. You can use Swift Package Manager or copy the files manually.",
                code: """
                // Swift Package Manager — add to Package.swift:
                dependencies: [
                    .package(
                        url: "https://github.com/tqtuan1201/TTBaseUIKit.git",
                        from: "2.3.0"
                    )
                ]
                
                // Or copy these files manually (all in TTBaseUIKit/Support/DebugBridge/):
                // • TTDebugBridge.swift        (required)
                // • DebugProtocol.swift         (required)
                // • ConnectionDiagnostics.swift (required)
                // • NetworkDiagnosticUtils.swift (required)
                // • LogInterceptor.swift        (optional — TTBPrint()/console hooking)
                // • DebugBridgeStatusView.swift + QRScannerView.swift (optional — pairing UI)
                """,
                language: "swift",
                note: "The DebugBridge files are in TTBaseUIKit/Support/DebugBridge/"
            ),
            IntegrationStep(
                number: 2,
                title: "⚠️ Configure Info.plist (Required)",
                description: "iOS 14+ requires local network access declarations in Info.plist. Missing this step causes a 'NoAuth -65555' error when NWBrowser attempts Bonjour scanning.",
                code: """
                <!-- Add to your iOS app's Info.plist -->
                
                <!-- Required: Describe why local network access is needed -->
                <key>NSLocalNetworkUsageDescription</key>
                <string>Required for connecting to TTBDebugPlus on macOS to stream debug logs.</string>
                
                <!-- Required: Declare Bonjour service type -->
                <key>NSBonjourServices</key>
                <array>
                    <string>_ttbdebug._tcp</string>
                </array>

                <!-- Only needed if you use the built-in QR pairing scanner -->
                <key>NSCameraUsageDescription</key>
                <string>Used to scan the TTBDebugPlus pairing QR code.</string>
                """,
                language: "xml",
                note: "⚠️ IMPORTANT: Without these 2 keys, iOS will block NWBrowser with a NoAuth error. After adding them, delete the app from the device and Build & Run again so iOS shows the permission prompt."
            ),
            IntegrationStep(
                number: 3,
                title: "Start the Debug Bridge",
                description: "Initialize the bridge in your AppDelegate or SceneDelegate. Wrap in #if DEBUG so it's excluded from production builds.",
                code: """
                import TTBaseUIKit

                // In AppDelegate.swift
                func application(
                    _ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
                ) -> Bool {
                    
                    #if DEBUG
                    TTDebugBridge.shared.start()
                    #endif
                    
                    return true
                }
                """,
                language: "swift",
                note: "The bridge auto-discovers the macOS app via Bonjour — no manual IP config needed!"
            ),
            IntegrationStep(
                number: 4,
                title: "Forward API Logs",
                description: "In your network layer (e.g. Alamofire responseHandler, URLSession completion), call sendAPILog to forward request/response data.",
                code: """
                // In your network response handler:
                TTDebugBridge.shared.sendAPILog(
                    method: request.httpMethod ?? "GET",
                    url: request.url?.absoluteString ?? "",
                    statusCode: response.statusCode,
                    requestHeaders: request.allHTTPHeaderFields ?? [:],
                    requestBody: String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "",
                    responseHeaders: response.allHeaderFields as? [String: String] ?? [:],
                    responseBody: String(data: responseData, encoding: .utf8) ?? "",
                    durationMs: elapsedTime * 1000,
                    sizeBytes: responseData.count
                )
                """,
                language: "swift",
                note: "You can also use LogInterceptor to auto-hook into LogViewHelper patterns."
            ),
            IntegrationStep(
                number: 5,
                title: "Forward Console Logs",
                description: "Send console log entries for viewing in the macOS Console tab. Supports log levels: debug, info, warning, error.",
                code: """
                // Manual log forwarding:
                TTDebugBridge.shared.sendConsoleLog(
                    level: "debug",       // debug | info | warning | error
                    subsystem: "Network", // your module name
                    message: "User profile loaded successfully",
                    sourceFile: #file,
                    sourceLine: #line
                )
                
                // Or use LogInterceptor to forward without changing every call site:
                LogInterceptor.shared.interceptConsoleLog(
                    message: "Something happened",
                    level: "warning",
                    subsystem: "Analytics"
                )
                """,
                language: "swift",
                note: "LogInterceptor doesn't auto-hook anything — call interceptConsoleLog/interceptAPILog from your existing log call sites, or replace print() with TTBPrint()."
            ),
            IntegrationStep(
                number: 6,
                title: "Run & Verify Connection",
                description: "Make sure both devices are on the same Wi-Fi network, then run your iOS app. The macOS app should detect it automatically within seconds.",
                code: """
                // Optional: Monitor connection state
                TTDebugBridge.shared.onStateChange = { state in
                    print("[Debug] Bridge state: \\(state.rawValue)")
                    // States: idle → browsing → connecting → connected
                }
                
                // Optional: Custom configuration
                var config = TTDebugBridge.Config()
                config.heartbeatInterval = 3.0  // seconds
                config.maxBufferedMessages = 500
                TTDebugBridge.shared.config = config
                """,
                language: "swift",
                note: "On first run on a physical device, iOS will show an 'Allow local network access' popup — tap Allow."
            ),
        ]
    }
    
    // MARK: - Troubleshooting

    /// Scoped to CODE/BUILD topics only (Phase 9) — connection-mechanics issues (NoAuth,
    /// device not appearing, permission denied, connection drops...) moved to the Tutorial
    /// Guide tab, which explains them with a beginner-friendly walkthrough instead of a raw
    /// error-log card. Keeping both here too would just be the duplication Phase 7 already
    /// spent effort removing elsewhere.
    private var troubleshootingSection: some View {
        CardView(title: "TROUBLESHOOTING (CODE & BUILD)") {
            VStack(alignment: .leading, spacing: 20) {
                TTBanner(
                    kind: .info,
                    message: "Having trouble actually connecting (device not appearing, permission errors, etc.)? See the Tutorial Guide tab — this section only covers code/build topics."
                )

                Divider().background(Color.ttBorder.opacity(0.2))

                // Production safety
                troubleItem(
                    errorLog: "How to exclude from production builds?",
                    icon: "lock.shield.fill",
                    iconColor: .ttSuccess,
                    title: "Ensure it doesn't ship in release builds",
                    explanation: "The bridge is a no-op when start() hasn't been called, but best practice is to wrap everything in #if DEBUG so the compiler completely strips it from the binary.",
                    solution: "Wrap all TTDebugBridge calls in:\n#if DEBUG\n    TTDebugBridge.shared.start()\n#endif\n\nVerify by: Build for Release → Search for TTDebugBridge in binary → should not exist."
                )
            }
        }
    }
    
    private func troubleItem(errorLog: String, icon: String, iconColor: Color, title: String, explanation: String, solution: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Error log preview — high-contrast error surface
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.ttIcon(TTIcon.sm))
                    .foregroundColor(TTBannerKind.error.foreground)
                Text(errorLog)
                    .font(TTFont.codeMedium)
                    .foregroundColor(TTBannerKind.error.foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(TTBannerKind.error.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(TTBannerKind.error.border.opacity(0.55), lineWidth: 1)
                    )
            )
            
            // Title
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.xl))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
            }
            
            // Explanation
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(.ttPrimary)
                    .padding(.top, 2)
                Text(explanation)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
            }
            .padding(.leading, 4)
            
            // Solution
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ttIcon(TTIcon.md))
                    .foregroundColor(TTBannerKind.success.foreground)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solution:")
                        .font(TTFont.labelSmall)
                        .foregroundColor(TTBannerKind.success.foreground)
                    Text(solution)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TTBannerKind.success.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(TTBannerKind.success.border.opacity(0.55), lineWidth: 1)
                    )
            )
            .padding(.leading, 4)
        }
    }
    
    // MARK: - Copy Code
    private func copyCode(_ step: IntegrationStep) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(step.code, forType: .string)
        copiedStep = step.number
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedStep == step.number { copiedStep = nil }
        }
    }
}

// MARK: - Step View
struct StepView: View {
    let step: IntegrationStep
    let isExpanded: Bool
    let isCopied: Bool
    var onToggle: () -> Void
    var onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step header
            Button(action: onToggle) {
                HStack(spacing: 14) {
                    // Step number + connector line
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(isExpanded ? Color.ttPrimary : Color.ttSurface)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(isExpanded ? Color.clear : Color.ttBorder, lineWidth: 1)
                                )
                            Text("\(step.number)")
                                .font(TTFont.codeLarge)
                                .foregroundColor(isExpanded ? .white : .ttTextSecondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(TTFont.heading3)
                            .foregroundColor(.ttTextPrimary)
                        Text(step.description)
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextTertiary)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.ttIcon(TTIcon.lg))
                        .foregroundColor(.ttTextTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 14)
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Code block
                    VStack(alignment: .leading, spacing: 0) {
                        // Code header
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(Color.ttError.opacity(0.8)).frame(width: 8, height: 8)
                                Circle().fill(Color.ttWarning.opacity(0.8)).frame(width: 8, height: 8)
                                Circle().fill(Color.ttSuccess.opacity(0.8)).frame(width: 8, height: 8)
                            }
                            
                            Spacer()
                            
                            Text(step.language.uppercased())
                                .font(TTFont.badge)
                                .foregroundColor(.ttTextTertiary)
                            
                            Button(action: onCopy) {
                                HStack(spacing: 4) {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                        .font(.ttIcon(TTIcon.md))
                                    Text(isCopied ? "Copied!" : "Copy")
                                        .font(TTFont.labelSmall)
                                }
                                .foregroundColor(isCopied ? .ttSuccess : .ttTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)))
                        
                        // Code content
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(step.code)
                                .font(TTFont.codeMedium)
                                .foregroundColor(.ttTextPrimary)
                                .textSelection(.enabled)
                                .padding(14)
                        }
                        .background(Color(nsColor: NSColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1.0)))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.ttBorder.opacity(0.3), lineWidth: 1)
                    )
                    
                    // Note callout
                    if let note = step.note {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.ttIcon(TTIcon.lg))
                                .foregroundColor(.ttWarning)
                            Text(note)
                                .font(TTFont.bodySmall)
                                .foregroundColor(.ttTextSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.ttWarning.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.ttWarning.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                }
                .padding(.leading, 46) // Align with step title
                .padding(.bottom, 14)
            }
            
            // Divider
            if step.number < 6 {
                Divider()
                    .background(Color.ttBorder.opacity(0.3))
                    .padding(.leading, 46)
            }
        }
    }
}

// MARK: - Model
struct IntegrationStep: Identifiable {
    let number: Int
    let title: String
    let description: String
    let code: String
    let language: String
    let note: String?
    
    var id: Int { number }
}

#Preview {
    IntegrationGuideView()
        .environment(ConnectionManager())
        .frame(width: 800, height: 900)
        .preferredColorScheme(.dark)
}
