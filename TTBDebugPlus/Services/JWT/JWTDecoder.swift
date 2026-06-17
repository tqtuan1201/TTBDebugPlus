//
//  JWTDecoder.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Pure, offline JWT decoding: base64url <-> data, segment splitting, header /
//  payload parsing, and registered-claim interpretation. No network, no keys.
//

import Foundation

enum JWTDecoder {

    // MARK: - Base64URL

    /// Decode a base64url string (RFC 7515 §2) into raw bytes.
    static func base64URLDecode(_ input: String) -> Data? {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore padding.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    /// Encode raw bytes as an unpadded base64url string.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Decode

    /// Decode a compact-serialized JWT string into its structured form.
    static func decode(_ token: String) throws -> DecodedJWT {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JWTError.malformed("empty token") }

        let segments = trimmed.components(separatedBy: ".")

        // 5 segments = JWE (encrypted). We surface a clear message instead of failing cryptically.
        if segments.count == 5 {
            throw JWTError.jweNotSupported
        }
        guard segments.count == 2 || segments.count == 3 else {
            throw JWTError.malformed("expected 3 segments separated by '.', found \(segments.count)")
        }

        let headerSegment = segments[0]
        let payloadSegment = segments[1]
        let signatureSegment = segments.count == 3 ? segments[2] : ""

        guard let headerData = base64URLDecode(headerSegment),
              let payloadData = base64URLDecode(payloadSegment) else {
            throw JWTError.invalidBase64
        }

        let header = try parseJSONObject(headerData)
        let payload = try parseJSONObject(payloadData)

        let rawAlg = header["alg"] as? String
        let algorithm = rawAlg.flatMap { JWTAlgorithm(rawValue: $0) }

        let expiresAt = dateClaim(payload["exp"])
        let notBefore = dateClaim(payload["nbf"])
        let issuedAt = dateClaim(payload["iat"])

        let claims = buildClaims(payload)

        return DecodedJWT(
            raw: trimmed,
            headerJSON: prettyJSON(headerData),
            payloadJSON: prettyJSON(payloadData),
            signatureSegment: signatureSegment,
            signingInput: "\(headerSegment).\(payloadSegment)",
            header: header,
            payload: payload,
            algorithm: algorithm,
            rawAlgorithm: rawAlg,
            claims: claims,
            expiresAt: expiresAt,
            notBefore: notBefore,
            issuedAt: issuedAt
        )
    }

    /// Lightweight check for whether a string plausibly *is* a JWT
    /// (used by clipboard auto-detect and the Network "Decode JWT" action).
    static func looksLikeJWT(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = trimmed.components(separatedBy: ".")
        guard segments.count == 3 else { return false }
        guard segments.allSatisfy({ !$0.isEmpty }) else { return false }
        // Header must decode to a JSON object with a "typ"/"alg" hint.
        guard let headerData = base64URLDecode(segments[0]),
              let obj = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return false
        }
        return obj["alg"] != nil || obj["typ"] != nil
    }

    /// Extract a bearer JWT from an `Authorization` header value, if present.
    static func extractBearerToken(from authorizationValue: String) -> String? {
        let value = authorizationValue.trimmingCharacters(in: .whitespaces)
        let prefix = "bearer "
        let candidate: String
        if value.lowercased().hasPrefix(prefix) {
            candidate = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        } else {
            candidate = value
        }
        return looksLikeJWT(candidate) ? candidate : nil
    }

    // MARK: - Helpers

    private static func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw JWTError.invalidJSON
        }
        return dict
    }

    private static func prettyJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return string
    }

    /// Interpret a numeric date claim (seconds since epoch).
    private static func dateClaim(_ value: Any?) -> Date? {
        if let seconds = value as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = value as? Int {
            return Date(timeIntervalSince1970: Double(seconds))
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    /// Registered claim descriptions (RFC 7519 §4.1).
    private static let registeredClaims: [String: String] = [
        "iss": "Issuer",
        "sub": "Subject",
        "aud": "Audience",
        "exp": "Expiration Time",
        "nbf": "Not Before",
        "iat": "Issued At",
        "jti": "JWT ID"
    ]

    private static func buildClaims(_ payload: [String: Any]) -> [JWTClaimRow] {
        let now = Date()
        // Registered claims first (in canonical order), then custom claims sorted by key.
        let registeredOrder = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"]
        var rows: [JWTClaimRow] = []

        func makeRow(_ key: String) -> JWTClaimRow? {
            guard let raw = payload[key] else { return nil }
            var annotation: String?
            var severity: JWTSecuritySeverity?

            if let date = dateClaim(raw) {
                annotation = Self.dateFormatter.string(from: date)
                switch key {
                case "exp":
                    if date < now {
                        annotation = "\(Self.dateFormatter.string(from: date)) — expired \(relative(date, to: now))"
                        severity = .high
                    } else {
                        annotation = "\(Self.dateFormatter.string(from: date)) — expires \(relative(date, to: now))"
                    }
                case "nbf":
                    if date > now {
                        annotation = "\(Self.dateFormatter.string(from: date)) — not valid until \(relative(date, to: now))"
                        severity = .medium
                    }
                case "iat":
                    annotation = "\(Self.dateFormatter.string(from: date)) — issued \(relative(date, to: now))"
                default:
                    break
                }
            }

            return JWTClaimRow(
                key: key,
                value: stringify(raw),
                description: registeredClaims[key],
                annotation: annotation,
                severity: severity
            )
        }

        for key in registeredOrder {
            if let row = makeRow(key) { rows.append(row) }
        }

        let customKeys = payload.keys.filter { !registeredOrder.contains($0) }.sorted()
        for key in customKeys {
            if let row = makeRow(key) { rows.append(row) }
        }

        return rows
    }

    /// Render a claim value as a compact, readable string.
    private static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            // Distinguish bool-backed NSNumber already handled above; format ints without decimals.
            if number === kCFBooleanTrue || number === kCFBooleanFalse {
                return number.boolValue ? "true" : "false"
            }
            if number.doubleValue == number.doubleValue.rounded() && abs(number.doubleValue) < 1e15 {
                return String(number.int64Value)
            }
            return number.stringValue
        case is NSNull:
            return "null"
        default:
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return "\(value)"
        }
    }

    private static func relative(_ date: Date, to reference: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
