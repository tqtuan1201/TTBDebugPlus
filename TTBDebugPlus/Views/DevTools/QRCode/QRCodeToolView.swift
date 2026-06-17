//
//  QRCodeToolView.swift
//  TTBDebugPlus
//
//  Created by Codex on 2026-05-27.
//  Professional QR code generator and decoder for Dev Tools
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QRCodeToolView: View {
    @AppStorage("devTools.qrCode.inputType") private var inputType: QRCodeInputType = .text
    @AppStorage("devTools.qrCode.errorCorrection") private var errorCorrection: QRCodeErrorCorrection = .medium
    @AppStorage("devTools.qrCode.foregroundColor") private var foregroundColor: QRCodeColorPreset = .black
    @AppStorage("devTools.qrCode.backgroundColor") private var backgroundColor: QRCodeColorPreset = .white
    
    @AppStorage("devTools.qrCode.textValue") private var textValue = "TTBDebugPlus"
    @AppStorage("devTools.qrCode.urlValue") private var urlValue = "https://"
    @AppStorage("devTools.qrCode.wifiSSID") private var wifiSSID = ""
    @AppStorage("devTools.qrCode.wifiPassword") private var wifiPassword = ""
    @AppStorage("devTools.qrCode.wifiEncryption") private var wifiEncryption: QRCodeWiFiEncryption = .wpa
    @AppStorage("devTools.qrCode.emailAddress") private var emailAddress = ""
    @AppStorage("devTools.qrCode.emailSubject") private var emailSubject = ""
    @AppStorage("devTools.qrCode.emailBody") private var emailBody = ""
    @AppStorage("devTools.qrCode.phoneNumber") private var phoneNumber = ""
    @AppStorage("devTools.qrCode.smsMessage") private var smsMessage = ""
    
    @State private var decodedImage: NSImage?
    @State private var decodedMessages: [String] = QRCodeToolView.restoreDecodedMessages()
    @State private var decodeError: String? = UserDefaults.standard.string(forKey: "devTools.qrCode.decodeError")
    @State private var copyState: CopyState?
    
    private var payload: String {
        QRCodeEngine.payload(
            type: inputType,
            text: textValue,
            url: urlValue,
            wifiSSID: wifiSSID,
            wifiPassword: wifiPassword,
            wifiEncryption: wifiEncryption,
            emailAddress: emailAddress,
            emailSubject: emailSubject,
            emailBody: emailBody,
            phoneNumber: phoneNumber,
            smsMessage: smsMessage
        )
    }
    
    private var qrImage: NSImage? {
        QRCodeEngine.generate(
            payload: payload,
            correction: errorCorrection,
            foreground: foregroundColor,
            background: backgroundColor
        )
    }
    
    var body: some View {
        HStack(spacing: 0) {
            generatorPanel
                .frame(width: 360)
            
            Divider().background(Color.ttBorder.opacity(0.3))
            
            previewPanel
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            
            Divider().background(Color.ttBorder.opacity(0.3))
            
            decoderPanel
                .frame(width: 320)
        }
        .background(Color.ttBackground)
        .frame(minWidth: 900, minHeight: 560)
    }
    
    // MARK: - Generator
    private var generatorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBlock(
                    icon: "qrcode",
                    title: "QR Code",
                    subtitle: "Create QR codes for common developer payloads."
                )
                
                sectionCard(title: "Content", icon: inputType.icon) {
                    inputTypeSelector
                    
                    Text(inputType.helperText)
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                    
                    inputFields
                }
                
                sectionCard(title: "Style", icon: "paintpalette") {
                    correctionPicker
                    colorPicker(title: "Foreground", selection: $foregroundColor)
                    colorPicker(title: "Background", selection: $backgroundColor)
                }
                
                sectionCard(title: "Payload Preview", icon: "doc.text.magnifyingglass") {
                    payloadPreview
                }
            }
            .padding(16)
        }
        .background(Color.ttSurface.opacity(0.08))
    }
    
    private var inputTypeSelector: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
            ForEach(QRCodeInputType.allCases) { type in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        inputType = type
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: type.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(type.rawValue)
                            .font(TTFont.labelSmall)
                            .lineLimit(1)
                    }
                    .foregroundColor(inputType == type ? .white : .ttTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: TTRadius.sm)
                            .fill(inputType == type ? Color.ttPrimary.opacity(0.55) : Color.ttSurface.opacity(0.42))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private var inputFields: some View {
        switch inputType {
        case .text:
            labeledTextEditor(title: "Text", text: $textValue, minHeight: 120)
        case .url:
            labeledTextField(title: "URL", placeholder: "https://example.com", text: $urlValue)
        case .wifi:
            labeledTextField(title: "Network Name", placeholder: "Office Wi-Fi", text: $wifiSSID)
            labeledTextField(title: "Password", placeholder: "Optional for open networks", text: $wifiPassword)
            Picker("Encryption", selection: $wifiEncryption) {
                ForEach(QRCodeWiFiEncryption.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .font(TTFont.bodySmall)
        case .email:
            labeledTextField(title: "Email", placeholder: "name@example.com", text: $emailAddress)
            labeledTextField(title: "Subject", placeholder: "Optional subject", text: $emailSubject)
            labeledTextEditor(title: "Body", text: $emailBody, minHeight: 80)
        case .phone:
            labeledTextField(title: "Phone", placeholder: "+1 555 0100", text: $phoneNumber)
        case .sms:
            labeledTextField(title: "Phone", placeholder: "+1 555 0100", text: $phoneNumber)
            labeledTextEditor(title: "Message", text: $smsMessage, minHeight: 80)
        }
    }
    
    private var correctionPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Error Correction")
                .font(TTFont.labelMedium)
                .foregroundColor(.ttTextSecondary)
            
            HStack(spacing: 6) {
                ForEach(QRCodeErrorCorrection.allCases) { level in
                    Button(action: { errorCorrection = level }) {
                        VStack(spacing: 2) {
                            Text(level.rawValue)
                                .font(TTFont.labelLarge)
                            Text(level.title)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(errorCorrection == level ? .white : .ttTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .fill(errorCorrection == level ? Color.ttPrimary.opacity(0.5) : Color.ttSurface.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(level.description)
                }
            }
        }
    }
    
    private func colorPicker(title: String, selection: Binding<QRCodeColorPreset>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(TTFont.labelMedium)
                .foregroundColor(.ttTextSecondary)
            
            HStack(spacing: 8) {
                ForEach(QRCodeColorPreset.allCases) { preset in
                    Button(action: { selection.wrappedValue = preset }) {
                        Circle()
                            .fill(preset.swiftUIColor)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(selection.wrappedValue == preset ? Color.ttPrimaryLight : Color.ttBorder.opacity(0.45), lineWidth: selection.wrappedValue == preset ? 2 : 1)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help(preset.rawValue)
                }
            }
        }
    }
    
    private var payloadPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(payload.isEmpty ? "No payload generated yet." : payload)
                .font(TTFont.codeSmall)
                .foregroundColor(payload.isEmpty ? .ttTextMuted : .ttTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(Color.ttBackground.opacity(0.56))
                )
            
            HStack(spacing: 8) {
                actionButton(title: "Paste", icon: "doc.on.clipboard", disabled: false) {
                    pasteTextFromClipboard()
                }
                actionButton(title: "Clear", icon: "xmark.circle", disabled: false) {
                    clearCurrentInput()
                }
            }
        }
    }
    
    // MARK: - Preview
    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generated Preview")
                        .font(TTFont.heading3)
                        .foregroundColor(.ttTextPrimary)
                    Text(payload.isEmpty ? "Enter content to generate a QR code." : "\(payload.count) characters")
                        .font(TTFont.bodySmall)
                        .foregroundColor(.ttTextTertiary)
                }
                
                Spacer()
                
                statusChip(icon: "shield", text: errorCorrection.title, color: .ttPrimary)
                statusChip(icon: "square.grid.3x3", text: "PNG", color: .ttSuccess)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.ttSurface.opacity(0.1))
            
            Divider().background(Color.ttBorder.opacity(0.25))
            
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                
                if let qrImage, !payload.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: TTRadius.md)
                            .fill(backgroundColor.swiftUIColor)
                            .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 12)
                        
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(22)
                    }
                    .frame(maxWidth: 360, maxHeight: 360)
                    .aspectRatio(1, contentMode: .fit)
                } else {
                    emptyPreview
                }
                
                HStack(spacing: 10) {
                    actionButton(title: copyState == .payload ? "Copied" : "Copy Payload", icon: copyState == .payload ? "checkmark.circle.fill" : "doc.on.doc", disabled: payload.isEmpty) {
                        copyPayload()
                    }
                    actionButton(title: copyState == .image ? "Copied" : "Copy Image", icon: copyState == .image ? "checkmark.circle.fill" : "photo.on.rectangle", disabled: qrImage == nil) {
                        copyImage()
                    }
                    actionButton(title: "Save PNG", icon: "square.and.arrow.down", disabled: qrImage == nil) {
                        savePNG()
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var emptyPreview: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.ttSurface.opacity(0.42))
                    .frame(width: 88, height: 88)
                Image(systemName: "qrcode")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(.ttTextMuted)
            }
            
            Text("No QR Code")
                .font(TTFont.heading3)
                .foregroundColor(.ttTextSecondary)
            
            Text("Fill in the content panel to create a scannable QR code.")
                .font(TTFont.bodySmall)
                .foregroundColor(.ttTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 340)
    }
    
    // MARK: - Decoder
    private var decoderPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBlock(
                    icon: AppIcon.qrCode,
                    title: "View QR",
                    subtitle: "Import or paste an image to decode QR content."
                )
                
                sectionCard(title: "Decode Image", icon: "photo") {
                    HStack(spacing: 8) {
                        actionButton(title: "Import", icon: "folder", disabled: false) {
                            importImage()
                        }
                        actionButton(title: "Paste", icon: "doc.on.clipboard", disabled: false) {
                            pasteImageFromClipboard()
                        }
                    }
                    
                    if let decodedImage {
                        Image(nsImage: decodedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: TTRadius.sm)
                                    .fill(Color.ttBackground.opacity(0.5))
                            )
                    } else {
                        Text("PNG, JPG, TIFF, or pasted image from clipboard.")
                            .font(TTFont.bodySmall)
                            .foregroundColor(.ttTextTertiary)
                    }
                }
                
                sectionCard(title: "Decoded Result", icon: "text.magnifyingglass") {
                    if let decodeError {
                        stateMessage(icon: "exclamationmark.triangle.fill", text: decodeError, color: .ttWarning)
                    } else if decodedMessages.isEmpty {
                        stateMessage(icon: AppIcon.qrCode, text: "No decoded content yet.", color: .ttTextMuted)
                    } else {
                        ForEach(Array(decodedMessages.enumerated()), id: \.offset) { _, value in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(value)
                                    .font(TTFont.codeSmall)
                                    .foregroundColor(.ttTextPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                actionButton(title: "Copy", icon: "doc.on.doc", disabled: false) {
                                    copyText(value, state: .decoded)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: TTRadius.sm)
                                    .fill(Color.ttBackground.opacity(0.52))
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.ttSurface.opacity(0.08))
    }
    
    // MARK: - Shared UI
    private func headerBlock(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: TTRadius.md)
                    .fill(Color.ttPrimary.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ttPrimaryLight)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TTFont.heading2)
                    .foregroundColor(.ttTextPrimary)
                Text(subtitle)
                    .font(TTFont.bodySmall)
                    .foregroundColor(.ttTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ttPrimary)
                Text(title)
                    .font(TTFont.labelLarge)
                    .foregroundColor(.ttTextPrimary)
            }
            
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TTRadius.md)
                .fill(Color.ttSurface.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: TTRadius.md)
                        .stroke(Color.ttBorder.opacity(0.28), lineWidth: 1)
                )
        )
    }
    
    private func labeledTextField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TTFont.labelMedium)
                .foregroundColor(.ttTextSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(Color.ttBackground.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .stroke(Color.ttBorder.opacity(0.3), lineWidth: 1)
                        )
                )
        }
    }
    
    private func labeledTextEditor(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TTFont.labelMedium)
                .foregroundColor(.ttTextSecondary)
            TextEditor(text: text)
                .font(TTFont.codeMedium)
                .foregroundColor(.ttTextPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: TTRadius.sm)
                        .fill(Color.ttBackground.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: TTRadius.sm)
                                .stroke(Color.ttBorder.opacity(0.3), lineWidth: 1)
                        )
                )
        }
    }
    
    private func actionButton(title: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(TTFont.labelSmall)
                    .lineLimit(1)
            }
            .foregroundColor(disabled ? .ttTextMuted : .ttTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: TTRadius.sm)
                    .fill(disabled ? Color.ttSurface.opacity(0.18) : Color.ttSurface.opacity(0.45))
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
    
    private func statusChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(TTFont.badge)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
    
    private func stateMessage(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(TTFont.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Actions
    private func pasteTextFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        switch inputType {
        case .text: textValue = value
        case .url: urlValue = value
        case .wifi: wifiSSID = value
        case .email: emailAddress = value
        case .phone, .sms: phoneNumber = value
        }
    }
    
    private func clearCurrentInput() {
        switch inputType {
        case .text: textValue = ""
        case .url: urlValue = ""
        case .wifi:
            wifiSSID = ""
            wifiPassword = ""
        case .email:
            emailAddress = ""
            emailSubject = ""
            emailBody = ""
        case .phone: phoneNumber = ""
        case .sms:
            phoneNumber = ""
            smsMessage = ""
        }
    }
    
    private func copyPayload() {
        copyText(payload, state: .payload)
    }
    
    private func copyText(_ text: String, state: CopyState) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyState(state)
    }
    
    private func copyImage() {
        guard let qrImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([qrImage])
        showCopyState(.image)
    }
    
    private func savePNG() {
        guard let qrImage, let data = QRCodeEngine.pngData(from: qrImage) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "qrcode.png"
        panel.allowedContentTypes = [.png]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                decodeError = "Could not save PNG: \(error.localizedDescription)"
            }
        }
    }
    
    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let image = NSImage(contentsOf: url) else {
                decodeError = "Could not open the selected image."
                decodedMessages = []
                decodedImage = nil
                saveDecodedState()
                return
            }
            decode(image)
        }
    }
    
    private func pasteImageFromClipboard() {
        let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        guard let image = images?.first else {
            decodeError = "Clipboard does not contain an image."
            decodedMessages = []
            decodedImage = nil
            saveDecodedState()
            return
        }
        decode(image)
    }
    
    private func decode(_ image: NSImage) {
        decodedImage = image
        switch QRCodeEngine.decode(from: image) {
        case .success(let values):
            decodedMessages = values
            decodeError = nil
        case .failure(let error):
            decodedMessages = []
            decodeError = error.localizedDescription
        }
        saveDecodedState()
    }
    
    private func showCopyState(_ state: CopyState) {
        copyState = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copyState == state {
                copyState = nil
            }
        }
    }

    private func saveDecodedState() {
        if let data = try? JSONEncoder().encode(decodedMessages),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "devTools.qrCode.decodedMessages")
        }

        if let decodeError {
            UserDefaults.standard.set(decodeError, forKey: "devTools.qrCode.decodeError")
        } else {
            UserDefaults.standard.removeObject(forKey: "devTools.qrCode.decodeError")
        }
    }

    private static func restoreDecodedMessages() -> [String] {
        guard let rawValue = UserDefaults.standard.string(forKey: "devTools.qrCode.decodedMessages"),
              let data = rawValue.data(using: .utf8),
              let messages = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return messages
    }
}

private enum CopyState {
    case payload
    case image
    case decoded
}

#Preview {
    QRCodeToolView()
        .frame(width: 1200, height: 760)
        .preferredColorScheme(.dark)
}
