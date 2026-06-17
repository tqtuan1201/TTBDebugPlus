//
//  NetworkDetailPane.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Detail pane for network request inspection — headers, view, preview, response, cookies
//  Uses WKWebView-backed JSON viewers for JSON display
//

import SwiftUI

// MARK: - Network Detail Pane
struct NetworkDetailPaneView: View {
    let request: NetworkRequestEntry
    @Binding var selectedTab: NetworkDetailTab
    var onClose: () -> Void = {}
    var onOpenInEditor: ((String, String) -> Void)? = nil
    var onSaveAsTemplate: ((String, String) -> Void)? = nil
    var onDecodeJWT: ((String, String) -> Void)? = nil
    @State private var copiedHeaderKey: String? = nil
    @State private var responseHeadersExpanded: Bool = true
    
    /// Available tabs (hide cookies if none)
    private var availableTabs: [NetworkDetailTab] {
        if request.hasCookies {
            return NetworkDetailTab.allCases
        } else {
            return NetworkDetailTab.allCases.filter { $0 != .cookies }
        }
    }

    /// A JWT extracted from an `Authorization` request header, if present.
    private var bearerJWT: String? {
        guard let entry = request.requestHeaders.first(where: { $0.key.lowercased() == "authorization" }) else {
            return nil
        }
        return JWTDecoder.extractBearerToken(from: entry.value)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            requestSummaryHeader
            
            // Tab picker
            tabPickerBar
            
            // Tab content — fills remaining space
            // Each tab manages its own scrolling internally
            switch selectedTab {
            case .headers:
                ScrollView {
                    headersContent
                        .padding(16)
                }
            case .view:
                viewContent
            case .preview:
                previewContent
            case .response:
                responseContent
            case .cookies:
                ScrollView {
                    cookiesContent
                        .padding(16)
                }
            }
        }
        .background(Color.ttBackground)
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.3)).frame(width: 1),
            alignment: .leading
        )
    }
    
    // MARK: - Summary Header
    private var requestSummaryHeader: some View {
        VStack(spacing: 8) {
            // Row 1: Method + Status + URL
            HStack(spacing: 8) {
                HTTPMethodBadge(method: request.method)
                StatusCodeBadge(code: request.statusCode)
                
                Text(request.urlPath)
                    .font(TTFont.codeMedium)
                    .foregroundColor(.ttTextPrimary)
                    .lineLimit(1)
                    .help(request.url)
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(TTFont.labelMedium)
                        .foregroundColor(.ttTextTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.ttSurface.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            
            // Row 2: Meta info pills
            HStack(spacing: 12) {
                metaInfoPill(icon: "clock", text: request.formattedTime, color: request.durationMs > 1000 ? .ttWarning : .ttTextTertiary)
                metaInfoPill(icon: "arrow.down.circle", text: request.formattedSize, color: .ttTextTertiary)
                metaInfoPill(icon: "desktopcomputer", text: request.sourceDeviceName, color: Color.forDevice(request.sourceDeviceId))
                
                Spacer()
                
                Text(request.formattedTimestamp)
                    .font(TTFont.codeSmall)
                    .foregroundColor(.ttTextMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.forStatusCode(request.statusCode).opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func metaInfoPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.ttIcon(TTIcon.xs))
                .foregroundColor(color)
            Text(text)
                .font(TTFont.codeSmall)
                .foregroundColor(color)
        }
    }
    
    // MARK: - Tab Picker
    private var tabPickerBar: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { tab in
                Button(action: { withAnimation(.easeInOut(duration: 0.12)) { selectedTab = tab } }) {
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                            .font(TTFont.tabLabel)
                        if tab == .cookies && request.hasCookies {
                            Text("\(request.parsedCookies.count)")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.ttPrimary.opacity(0.6)))
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .ttPrimary : .ttTextTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay(
                    Rectangle()
                        .fill(selectedTab == tab ? Color.ttPrimary : Color.clear)
                        .frame(height: 2),
                    alignment: .bottom
                )
            }
            
            Spacer()
        }
        .background(Color.ttSurface.opacity(0.15))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.2)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Headers Tab
    private var headersContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General Information Card
            sectionCard(title: "GENERAL INFORMATION", icon: "info.circle") {
                VStack(alignment: .leading, spacing: 0) {
                    infoRow(label: "Request URL", value: request.url, isURL: true)
                    infoRow(label: "Request Method", value: request.method, valueColor: Color.forHTTPMethod(request.method), isBold: true)
                    
                    // Status Code (custom row)
                    HStack(alignment: .top, spacing: 0) {
                        Text("Status Code")
                            .font(TTFont.codeSmall)
                            .foregroundColor(.ttTextTertiary)
                            .frame(width: 130, alignment: .leading)
                        HStack(spacing: 6) {
                            Circle().fill(Color.forStatusCode(request.statusCode)).frame(width: 7, height: 7)
                            Text("\(request.statusCode)")
                                .font(TTFont.codeMedium.bold())
                                .foregroundColor(Color.forStatusCode(request.statusCode))
                            Text(HTTPURLResponse.localizedString(forStatusCode: request.statusCode))
                                .font(TTFont.codeSmall)
                                .foregroundColor(.ttTextTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.ttSurface.opacity(0.15))
                    
                    infoRow(label: "Remote Address", value: request.remoteAddress)
                    infoRow(label: "Duration", value: request.formattedTime, valueColor: request.durationMs > 1000 ? .ttWarning : .ttTextSecondary)
                    infoRow(label: "Size", value: request.formattedSize)
                    infoRow(label: "Device", value: request.sourceDeviceName, valueColor: Color.forDevice(request.sourceDeviceId))
                    infoRow(label: "Timestamp", value: request.formattedTimestamp)
                }
            }
            
            // Bearer-token JWT decode action (when an Authorization header carries a JWT)
            if let bearerJWT, let onDecodeJWT {
                sectionCard(title: "JWT", icon: AppIcon.jwt) {
                    HStack(spacing: 10) {
                        Image(systemName: AppIcon.jwt)
                            .font(.ttIcon(TTIcon.md))
                            .foregroundColor(.ttPrimaryLight)
                        Text("This request carries a bearer token.")
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextSecondary)
                        Spacer()
                        Button {
                            onDecodeJWT(bearerJWT, "Network — \(request.method) \(request.urlPath)")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.forward.app").font(.ttIcon(TTIcon.sm))
                                Text("Decode JWT").font(TTFont.labelSmall)
                            }
                            .foregroundColor(.ttPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Open this token in the JWT Debugger")
                    }
                }
            }

            // Request Headers Card
            if !request.requestHeaders.isEmpty {
                sectionCard(title: "REQUEST HEADERS", icon: "arrow.up.doc", count: request.requestHeaders.count) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(request.requestHeaders.keys.sorted()), id: \.self) { key in
                            headerRow(key: key, value: request.requestHeaders[key] ?? "")
                        }
                    }
                }
            }
            
            // Payload Card
            if !request.requestBody.isEmpty {
                sectionCard(title: "PAYLOAD", icon: "doc.text") {
                    VStack(spacing: 0) {
                        saveTemplateBar(json: request.requestBody,
                                        source: "Request Body — \(request.method) \(request.urlPath)")
                        OnlineJsonViewerView(
                            jsonString: request.requestBody,
                            showToolbar: true,
                            initialMode: "tree",
                            onOpenInEditor: { json in
                                onOpenInEditor?(json, "Request Body — \(request.method) \(request.urlPath)")
                            }
                        )
                        .frame(minHeight: 150, idealHeight: 250)
                    }
                }
            }
        }
    }

    // MARK: - Save as Template Bar
    /// Compact trailing action to save the displayed JSON to the Template Library.
    @ViewBuilder
    private func saveTemplateBar(json: String, source: String) -> some View {
        if let onSaveAsTemplate {
            HStack(spacing: 0) {
                Spacer()
                Button(action: { onSaveAsTemplate(json, source) }) {
                    HStack(spacing: 3) {
                        Image(systemName: AppIcon.saveTemplate)
                            .font(.ttIcon(TTIcon.sm))
                        Text("Save as Template")
                            .font(TTFont.labelSmall)
                    }
                    .foregroundColor(.ttPrimary)
                }
                .buttonStyle(.ttGhost)
                .help("Save this JSON to the Template Library")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - View Tab (single-pane response body)
    private var viewContent: some View {
        Group {
            if !request.responseBody.isEmpty {
                JSONWebViewComponent(
                    jsonString: request.responseBody,
                    isEditable: false,
                    showToolbar: true,
                    initialMode: .preview,
                    onOpenInEditor: { json in
                        onOpenInEditor?(json, "Response View — \(request.method) \(request.urlPath)")
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Response Body",
                    subtitle: "This request returned no response body"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Preview Tab (fills available space)
    private var previewContent: some View {
        Group {
            if !request.responseBody.isEmpty {
                OnlineJsonViewerView(
                    jsonString: request.responseBody,
                    showToolbar: true,
                    initialMode: "code",
                    onOpenInEditor: { json in
                        onOpenInEditor?(json, "Response Preview — \(request.method) \(request.urlPath)")
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "eye.slash",
                    title: "No Preview",
                    subtitle: "This response has no previewable content"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Response Tab (fills available space for body)
    private var responseContent: some View {
        VStack(spacing: 0) {
            // Response Headers — collapsible section at top
            if !request.responseHeaders.isEmpty {
                VStack(spacing: 0) {
                    // Collapsible header toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            responseHeadersExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: responseHeadersExpanded ? "chevron.down" : "chevron.right")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextTertiary)
                            Image(systemName: "arrow.down.doc")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttPrimary)
                            Text("RESPONSE HEADERS")
                                .font(TTFont.labelSmall)
                                .foregroundColor(.ttTextSecondary)
                                .tracking(0.8)
                            Text("\(request.responseHeaders.count)")
                                .font(.ttIcon(TTIcon.xs))
                                .foregroundColor(.ttTextTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.ttSurface.opacity(0.6)))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.ttSurface.opacity(0.2))
                    
                    if responseHeadersExpanded {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(request.responseHeaders.keys.sorted()), id: \.self) { key in
                                    headerRow(key: key, value: request.responseHeaders[key] ?? "")
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.ttBorder.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            
            // Response Body — fills remaining space
            if !request.responseBody.isEmpty {
                VStack(spacing: 0) {
                    saveTemplateBar(json: request.responseBody,
                                    source: "Response Body — \(request.method) \(request.urlPath)")
                    OnlineJsonViewerView(
                        jsonString: request.responseBody,
                        showToolbar: true,
                        initialMode: "code",
                        onOpenInEditor: { json in
                            onOpenInEditor?(json, "Response Body — \(request.method) \(request.urlPath)")
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No Response Body",
                    subtitle: "This request returned no response body"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Cookies Tab
    private var cookiesContent: some View {
        Group {
            if request.parsedCookies.isEmpty {
                EmptyStateView(
                    icon: "circle.dotted",
                    title: "No Cookies",
                    subtitle: "No cookies were sent or received with this request"
                )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(request.parsedCookies) { cookie in
                        sectionCard(title: cookie.name, icon: "circle.fill") {
                            VStack(alignment: .leading, spacing: 10) {
                                // Value
                                HStack(alignment: .top, spacing: 0) {
                                    Text("Value")
                                        .font(TTFont.codeSmall)
                                        .foregroundColor(.ttTextTertiary)
                                        .frame(width: 80, alignment: .leading)
                                    Text(cookie.value)
                                        .font(TTFont.codeMedium)
                                        .foregroundColor(.ttJsonString)
                                        .lineLimit(3)
                                        .textSelection(.enabled)
                                }
                                
                                // Attributes
                                HStack(spacing: 8) {
                                    if let domain = cookie.domain {
                                        cookieAttr(label: "Domain", value: domain)
                                    }
                                    if let path = cookie.path {
                                        cookieAttr(label: "Path", value: path)
                                    }
                                    if cookie.isSecure {
                                        cookieFlag(label: "Secure", color: .ttSuccess)
                                    }
                                    if cookie.isHttpOnly {
                                        cookieFlag(label: "HttpOnly", color: .ttWarning)
                                    }
                                    if let sameSite = cookie.sameSite {
                                        cookieAttr(label: "SameSite", value: sameSite)
                                    }
                                }
                                
                                if let expires = cookie.expires {
                                    HStack(spacing: 0) {
                                        Text("Expires")
                                            .font(TTFont.codeSmall)
                                            .foregroundColor(.ttTextTertiary)
                                            .frame(width: 80, alignment: .leading)
                                        Text(expires)
                                            .font(TTFont.codeSmall)
                                            .foregroundColor(.ttTextSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Section Card Component
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.ttIcon(TTIcon.xs))
                    .foregroundColor(.ttPrimary)
                Text(title)
                    .font(TTFont.labelSmall)
                    .foregroundColor(.ttTextSecondary)
                    .tracking(0.8)
                
                if let count = count {
                    Text("\(count)")
                        .font(.ttIcon(TTIcon.xs))
                        .foregroundColor(.ttTextTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.ttSurface.opacity(0.6))
                        )
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.ttSurface.opacity(0.2))
            
            // Content
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ttBorder.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Info Row (for General Information)
    private func infoRow(
        label: String,
        value: String,
        valueColor: Color = .ttTextSecondary,
        isURL: Bool = false,
        isBold: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
                .frame(width: 130, alignment: .leading)
            
            Text(value)
                .font(isBold ? .system(size: 12, weight: .semibold, design: .monospaced) : TTFont.codeMedium)
                .foregroundColor(valueColor)
                .lineLimit(isURL ? 2 : 1)
                .textSelection(.enabled)
            
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
    
    // MARK: - Header Row (for Request/Response Headers)
    private func headerRow(key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(key)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttJsonKey)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
            
            Text(value)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            
            Spacer(minLength: 4)
            
            // Copy button
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copiedHeaderKey = key
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if copiedHeaderKey == key { copiedHeaderKey = nil }
                }
            }) {
                Image(systemName: copiedHeaderKey == key ? "checkmark" : "doc.on.doc")
                    .font(.ttIcon(TTIcon.xs))
                    .foregroundColor(copiedHeaderKey == key ? .ttSuccess : .ttTextMuted)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(Color.ttSurface.opacity(0.08))
        .overlay(
            Rectangle().fill(Color.ttBorder.opacity(0.08)).frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Cookie Helpers
    private func cookieAttr(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextTertiary)
            Text(value)
                .font(TTFont.codeSmall)
                .foregroundColor(.ttTextSecondary)
        }
    }
    
    private func cookieFlag(label: String, color: Color) -> some View {
        Text(label)
            .font(.ttIcon(TTIcon.xs))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }
}
