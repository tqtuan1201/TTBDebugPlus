//
//  QRCodeEngine.swift
//  TTBDebugPlus
//
//  Created by Codex on 2026-05-27.
//  QR code generation, export, and decoding helpers for Dev Tools
//

import AppKit
import CoreImage
import SwiftUI
import Vision

enum QRCodeInputType: String, CaseIterable, Identifiable {
    case text = "Text"
    case url = "URL"
    case wifi = "Wi-Fi"
    case email = "Email"
    case phone = "Phone"
    case sms = "SMS"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .wifi: return "wifi"
        case .email: return "envelope"
        case .phone: return "phone"
        case .sms: return "message"
        }
    }
    
    var helperText: String {
        switch self {
        case .text: return "Any text, token, payload, or note."
        case .url: return "A web link. Missing schemes are normalized to https://."
        case .wifi: return "Network name, password, and encryption."
        case .email: return "Email address with optional subject and body."
        case .phone: return "Phone number for tel: links."
        case .sms: return "Phone number plus optional SMS body."
        }
    }
}

enum QRCodeErrorCorrection: String, CaseIterable, Identifiable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .quartile: return "Quartile"
        case .high: return "High"
        }
    }
    
    var description: String {
        switch self {
        case .low: return "Smallest code"
        case .medium: return "Balanced"
        case .quartile: return "More resilient"
        case .high: return "Maximum recovery"
        }
    }
}

enum QRCodeWiFiEncryption: String, CaseIterable, Identifiable {
    case wpa = "WPA/WPA2"
    case wep = "WEP"
    case none = "No Password"
    
    var id: String { rawValue }
    
    var qrValue: String {
        switch self {
        case .wpa: return "WPA"
        case .wep: return "WEP"
        case .none: return "nopass"
        }
    }
}

enum QRCodeColorPreset: String, CaseIterable, Identifiable {
    case black = "Black"
    case white = "White"
    case blue = "Blue"
    case green = "Green"
    case orange = "Orange"
    case purple = "Purple"
    
    var id: String { rawValue }
    
    var swiftUIColor: Color {
        switch self {
        case .black: return Color(hex: "#020617")
        case .white: return Color(hex: "#FFFFFF")
        case .blue: return .ttPrimary
        case .green: return .ttSuccess
        case .orange: return .ttWarning
        case .purple: return Color(hex: "#A855F7")
        }
    }
    
    var ciColor: CIColor {
        switch self {
        case .black: return CIColor(red: 0.008, green: 0.024, blue: 0.09, alpha: 1.0)
        case .white: return CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        case .blue: return CIColor(red: 0.231, green: 0.51, blue: 0.965, alpha: 1.0)
        case .green: return CIColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)
        case .orange: return CIColor(red: 0.961, green: 0.62, blue: 0.043, alpha: 1.0)
        case .purple: return CIColor(red: 0.659, green: 0.333, blue: 0.969, alpha: 1.0)
        }
    }
}

enum QRCodeEngine {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    
    static func payload(
        type: QRCodeInputType,
        text: String,
        url: String,
        wifiSSID: String,
        wifiPassword: String,
        wifiEncryption: QRCodeWiFiEncryption,
        emailAddress: String,
        emailSubject: String,
        emailBody: String,
        phoneNumber: String,
        smsMessage: String
    ) -> String {
        switch type {
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .url:
            return normalizedURL(url)
        case .wifi:
            return wifiPayload(ssid: wifiSSID, password: wifiPassword, encryption: wifiEncryption)
        case .email:
            return emailPayload(address: emailAddress, subject: emailSubject, body: emailBody)
        case .phone:
            let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedPhone.isEmpty ? "" : "tel:\(trimmedPhone)"
        case .sms:
            return smsPayload(phone: phoneNumber, message: smsMessage)
        }
    }
    
    static func generate(
        payload: String,
        correction: QRCodeErrorCorrection,
        foreground: QRCodeColorPreset,
        background: QRCodeColorPreset,
        size: CGFloat = 900
    ) -> NSImage? {
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue(correction.rawValue, forKey: "inputCorrectionLevel")
        
        guard let qrImage = qrFilter.outputImage,
              let colorFilter = CIFilter(name: "CIFalseColor") else { return nil }
        
        colorFilter.setValue(qrImage, forKey: kCIInputImageKey)
        colorFilter.setValue(foreground.ciColor, forKey: "inputColor0")
        colorFilter.setValue(background.ciColor, forKey: "inputColor1")
        
        guard let coloredImage = colorFilter.outputImage else { return nil }
        let scale = size / max(coloredImage.extent.width, coloredImage.extent.height)
        let scaledImage = coloredImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
    
    static func pngData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImageForQRCode else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
    
    static func decode(from image: NSImage) -> Result<[String], Error> {
        guard let cgImage = image.cgImageForQRCode else {
            return .failure(QRCodeEngineError.invalidImage)
        }
        
        var decodedValues: [String] = []
        let request = VNDetectBarcodesRequest { request, _ in
            let observations = request.results as? [VNBarcodeObservation] ?? []
            decodedValues = observations
                .filter { $0.symbology == .qr }
                .compactMap(\.payloadStringValue)
        }
        request.symbologies = [.qr]
        
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return decodedValues.isEmpty ? .failure(QRCodeEngineError.noQRCodeFound) : .success(decodedValues)
        } catch {
            return .failure(error)
        }
    }
    
    private static func normalizedURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("://") { return trimmed }
        return "https://\(trimmed)"
    }
    
    private static func wifiPayload(ssid: String, password: String, encryption: QRCodeWiFiEncryption) -> String {
        let escapedSSID = escapeWiFiValue(ssid.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !escapedSSID.isEmpty else { return "" }
        let escapedPassword = escapeWiFiValue(password)
        if encryption == .none {
            return "WIFI:T:nopass;S:\(escapedSSID);;"
        }
        return "WIFI:T:\(encryption.qrValue);S:\(escapedSSID);P:\(escapedPassword);;"
    }
    
    private static func emailPayload(address: String, subject: String, body: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return "" }
        
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = trimmedAddress
        
        var queryItems: [URLQueryItem] = []
        if !subject.isEmpty { queryItems.append(URLQueryItem(name: "subject", value: subject)) }
        if !body.isEmpty { queryItems.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.string ?? "mailto:\(address)"
    }
    
    private static func smsPayload(phone: String, message: String) -> String {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty else { return "" }
        guard !message.isEmpty,
              let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "sms:\(trimmedPhone)"
        }
        return "sms:\(trimmedPhone)&body=\(encodedMessage)"
    }
    
    private static func escapeWiFiValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum QRCodeEngineError: LocalizedError {
    case invalidImage
    case noQRCodeFound
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be read."
        case .noQRCodeFound:
            return "No QR code was found in the image."
        }
    }
}

private extension NSImage {
    var cgImageForQRCode: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
