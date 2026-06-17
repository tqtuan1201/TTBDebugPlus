//
//  JWTModels.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Value types for the JWT Debugger — algorithm, decoded token, claims,
//  verification result, and security findings. Pure Foundation; fully offline.
//

import Foundation
import SwiftUI

// MARK: - Algorithm

/// JWS signing algorithms supported by the debugger (HMAC, RSA PKCS#1 v1.5, ECDSA).
enum JWTAlgorithm: String, CaseIterable, Identifiable, Codable {
    case hs256 = "HS256"
    case hs384 = "HS384"
    case hs512 = "HS512"
    case rs256 = "RS256"
    case rs384 = "RS384"
    case rs512 = "RS512"
    case es256 = "ES256"
    case es384 = "ES384"
    case es512 = "ES512"
    case none  = "none"

    var id: String { rawValue }

    enum Family { case hmac, rsa, ecdsa, none }

    var family: Family {
        switch self {
        case .hs256, .hs384, .hs512: return .hmac
        case .rs256, .rs384, .rs512: return .rsa
        case .es256, .es384, .es512: return .ecdsa
        case .none: return .none
        }
    }

    /// HMAC algorithms use a shared secret; the rest use a key pair.
    var isSymmetric: Bool { family == .hmac }

    /// Whether verification/signing needs key material at all.
    var requiresKey: Bool { family != .none }

    /// Algorithms the debugger can produce a signature for (sign side).
    /// `none` is intentionally signable so users can craft `alg:none` test tokens.
    static var signable: [JWTAlgorithm] {
        allCases
    }

    var displayName: String {
        switch family {
        case .hmac:  return "\(rawValue) · HMAC-SHA"
        case .rsa:   return "\(rawValue) · RSA PKCS#1 v1.5"
        case .ecdsa: return "\(rawValue) · ECDSA"
        case .none:  return "none · unsecured"
        }
    }

    var keyPrompt: String {
        switch family {
        case .hmac:  return "Shared secret"
        case .rsa, .ecdsa: return "Public key (PEM)"
        case .none:  return "No key required"
        }
    }

    var signingKeyPrompt: String {
        switch family {
        case .hmac:  return "Shared secret"
        case .rsa, .ecdsa: return "Private key (PEM)"
        case .none:  return "No key required"
        }
    }
}

// MARK: - Decoded Token

/// A single claim rendered for display (registered or custom).
struct JWTClaimRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    /// Human description for registered claims (iss, exp, …); nil for custom.
    let description: String?
    /// Extra annotation such as a formatted date or "Expired 2h ago".
    var annotation: String?
    /// Highlights time-sensitive problems (expired / not-yet-valid).
    var severity: JWTSecuritySeverity?
}

/// Result of decoding a JWT string into its parts.
struct DecodedJWT {
    let raw: String
    /// Pretty-printed header JSON.
    let headerJSON: String
    /// Pretty-printed payload JSON.
    let payloadJSON: String
    /// The raw (base64url) signature segment, empty for unsecured tokens.
    let signatureSegment: String
    /// The "header.payload" string the signature is computed over.
    let signingInput: String

    let header: [String: Any]
    let payload: [String: Any]

    /// Algorithm declared in the header, if recognized.
    let algorithm: JWTAlgorithm?
    /// Raw `alg` header value as written (even if unrecognized).
    let rawAlgorithm: String?

    let claims: [JWTClaimRow]

    /// Expiry helpers derived from the payload.
    var expiresAt: Date?
    var notBefore: Date?
    var issuedAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    var isNotYetValid: Bool {
        guard let notBefore else { return false }
        return notBefore > Date()
    }
}

// MARK: - Verification

enum JWTSignatureStatus: Equatable {
    case valid
    case invalid
    case unverified          // no key provided yet
    case error(String)
}

struct JWTVerificationResult {
    let status: JWTSignatureStatus
    let algorithm: JWTAlgorithm
    let message: String

    var color: Color {
        switch status {
        case .valid:      return .ttSuccess
        case .invalid:    return .ttError
        case .unverified: return .ttTextTertiary
        case .error:      return .ttWarning
        }
    }

    var icon: String {
        switch status {
        case .valid:      return "checkmark.seal.fill"
        case .invalid:    return "xmark.seal.fill"
        case .unverified: return "questionmark.circle"
        case .error:      return "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch status {
        case .valid:      return "Signature Verified"
        case .invalid:    return "Signature Invalid"
        case .unverified: return "Not Verified"
        case .error:      return "Verification Error"
        }
    }
}

// MARK: - Security Analysis

enum JWTSecuritySeverity: Int, Comparable {
    case critical = 4
    case high = 3
    case medium = 2
    case low = 1
    case info = 0

    static func < (lhs: JWTSecuritySeverity, rhs: JWTSecuritySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .critical: return "CRITICAL"
        case .high:     return "HIGH"
        case .medium:   return "MEDIUM"
        case .low:      return "LOW"
        case .info:     return "INFO"
        }
    }

    var color: Color {
        switch self {
        case .critical: return .ttError
        case .high:     return .ttError
        case .medium:   return .ttWarning
        case .low:      return .ttWarning
        case .info:     return .ttInfo
        }
    }

    var icon: String {
        switch self {
        case .critical, .high: return "exclamationmark.octagon.fill"
        case .medium, .low:    return "exclamationmark.triangle.fill"
        case .info:            return "info.circle.fill"
        }
    }
}

struct JWTSecurityFinding: Identifiable {
    let id = UUID()
    let severity: JWTSecuritySeverity
    let title: String
    let detail: String
}

// MARK: - Tool Payload

/// Carries a token into the JWT Debugger from an external entry point
/// (Network "Decode JWT", menu-bar quick decode, etc.).
struct JWTToolPayload: Equatable {
    let token: String
    let sourceLabel: String
}

// MARK: - Errors

enum JWTError: LocalizedError {
    case malformed(String)
    case invalidBase64
    case invalidJSON
    case unsupportedAlgorithm(String)
    case invalidKey(String)
    case signingFailed(String)
    case jweNotSupported

    var errorDescription: String? {
        switch self {
        case .malformed(let why):          return "Malformed JWT: \(why)"
        case .invalidBase64:               return "A token segment is not valid base64url."
        case .invalidJSON:                 return "A token segment is not valid JSON."
        case .unsupportedAlgorithm(let a): return "Unsupported algorithm: \(a)"
        case .invalidKey(let why):         return "Invalid key: \(why)"
        case .signingFailed(let why):      return "Signing failed: \(why)"
        case .jweNotSupported:             return "This looks like a JWE (encrypted token), which is not supported."
        }
    }
}
