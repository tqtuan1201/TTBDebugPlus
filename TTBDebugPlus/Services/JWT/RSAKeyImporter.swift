//
//  RSAKeyImporter.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Imports RSA keys from PEM into `SecKey`. `SecKeyCreateWithData` only accepts
//  PKCS#1 (RSAPublicKey / RSAPrivateKey) DER, so SPKI public keys and PKCS#8
//  private keys are unwrapped to PKCS#1 with a minimal ASN.1 DER reader.
//  All parsing is local and offline.
//

import Foundation
import Security

enum RSAKeyImporter {

    // MARK: - Public API

    static func publicKey(fromPEM pem: String) throws -> SecKey {
        let parsed = try parsePEM(pem)
        let pkcs1: Data
        switch parsed.kind {
        case .pkcs1Public:
            pkcs1 = parsed.der
        case .spkiPublic:
            pkcs1 = try DER.stripSPKI(parsed.der)
        default:
            throw JWTError.invalidKey("the PEM is not an RSA public key")
        }
        return try makeSecKey(pkcs1, isPublic: true)
    }

    static func privateKey(fromPEM pem: String) throws -> SecKey {
        let parsed = try parsePEM(pem)
        let pkcs1: Data
        switch parsed.kind {
        case .pkcs1Private:
            pkcs1 = parsed.der
        case .pkcs8Private:
            pkcs1 = try DER.stripPKCS8(parsed.der)
        default:
            throw JWTError.invalidKey("the PEM is not an RSA private key")
        }
        return try makeSecKey(pkcs1, isPublic: false)
    }

    // MARK: - PEM

    private enum KeyKind {
        case spkiPublic       // -----BEGIN PUBLIC KEY-----
        case pkcs1Public      // -----BEGIN RSA PUBLIC KEY-----
        case pkcs8Private     // -----BEGIN PRIVATE KEY-----
        case pkcs1Private     // -----BEGIN RSA PRIVATE KEY-----
    }

    private static func parsePEM(_ pem: String) throws -> (der: Data, kind: KeyKind) {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("-----BEGIN") else {
            throw JWTError.invalidKey("expected a PEM block (-----BEGIN ...-----)")
        }

        let kind: KeyKind
        if trimmed.contains("BEGIN RSA PUBLIC KEY") {
            kind = .pkcs1Public
        } else if trimmed.contains("BEGIN PUBLIC KEY") {
            kind = .spkiPublic
        } else if trimmed.contains("BEGIN RSA PRIVATE KEY") {
            kind = .pkcs1Private
        } else if trimmed.contains("BEGIN PRIVATE KEY") {
            kind = .pkcs8Private
        } else if trimmed.contains("ENCRYPTED PRIVATE KEY") {
            throw JWTError.invalidKey("encrypted private keys are not supported — decrypt it first")
        } else {
            throw JWTError.invalidKey("unrecognized PEM key type")
        }

        let base64 = trimmed
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let der = Data(base64Encoded: base64) else {
            throw JWTError.invalidKey("PEM body is not valid base64")
        }
        return (der, kind)
    }

    // MARK: - SecKey

    private static func makeSecKey(_ pkcs1DER: Data, isPublic: Bool) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: isPublic ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1DER as CFData, attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "could not import RSA key"
            throw JWTError.invalidKey(message)
        }
        return key
    }
}

// MARK: - Minimal ASN.1 DER Reader

private enum DER {

    /// One Tag-Length-Value triple located within a byte buffer.
    private struct TLV {
        let tag: UInt8
        let contentStart: Int
        let contentLength: Int
        let next: Int
    }

    private static func readTLV(_ bytes: [UInt8], at index: Int) throws -> TLV {
        var i = index
        guard i < bytes.count else { throw JWTError.invalidKey("DER truncated (tag)") }
        let tag = bytes[i]; i += 1

        guard i < bytes.count else { throw JWTError.invalidKey("DER truncated (length)") }
        var length = Int(bytes[i]); i += 1
        if length & 0x80 != 0 {
            let byteCount = length & 0x7F
            guard byteCount > 0, byteCount <= 4 else { throw JWTError.invalidKey("DER length unsupported") }
            length = 0
            for _ in 0..<byteCount {
                guard i < bytes.count else { throw JWTError.invalidKey("DER truncated (long length)") }
                length = (length << 8) | Int(bytes[i]); i += 1
            }
        }

        let contentStart = i
        let next = i + length
        guard next <= bytes.count else { throw JWTError.invalidKey("DER length exceeds buffer") }
        return TLV(tag: tag, contentStart: contentStart, contentLength: length, next: next)
    }

    /// SubjectPublicKeyInfo → PKCS#1 RSAPublicKey.
    /// SEQUENCE { AlgorithmIdentifier SEQUENCE, BIT STRING { RSAPublicKey } }
    static func stripSPKI(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        let outer = try readTLV(bytes, at: 0)
        guard outer.tag == 0x30 else { throw JWTError.invalidKey("SPKI: expected SEQUENCE") }

        // AlgorithmIdentifier — skip it.
        let algId = try readTLV(bytes, at: outer.contentStart)
        guard algId.tag == 0x30 else { throw JWTError.invalidKey("SPKI: expected AlgorithmIdentifier") }

        // BIT STRING holding the RSAPublicKey.
        let bitString = try readTLV(bytes, at: algId.next)
        guard bitString.tag == 0x03 else { throw JWTError.invalidKey("SPKI: expected BIT STRING") }
        guard bitString.contentLength >= 1, bytes[bitString.contentStart] == 0x00 else {
            throw JWTError.invalidKey("SPKI: unexpected BIT STRING padding")
        }
        // Drop the leading "unused bits" byte (0x00).
        let start = bitString.contentStart + 1
        let end = bitString.contentStart + bitString.contentLength
        return Data(bytes[start..<end])
    }

    /// PKCS#8 PrivateKeyInfo → PKCS#1 RSAPrivateKey.
    /// SEQUENCE { INTEGER version, AlgorithmIdentifier SEQUENCE, OCTET STRING { RSAPrivateKey } }
    static func stripPKCS8(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        let outer = try readTLV(bytes, at: 0)
        guard outer.tag == 0x30 else { throw JWTError.invalidKey("PKCS#8: expected SEQUENCE") }

        // version INTEGER — skip.
        let version = try readTLV(bytes, at: outer.contentStart)
        guard version.tag == 0x02 else { throw JWTError.invalidKey("PKCS#8: expected version INTEGER") }

        // AlgorithmIdentifier — skip.
        let algId = try readTLV(bytes, at: version.next)
        guard algId.tag == 0x30 else { throw JWTError.invalidKey("PKCS#8: expected AlgorithmIdentifier") }

        // OCTET STRING holding the RSAPrivateKey.
        let octet = try readTLV(bytes, at: algId.next)
        guard octet.tag == 0x04 else { throw JWTError.invalidKey("PKCS#8: expected OCTET STRING") }
        let start = octet.contentStart
        let end = octet.contentStart + octet.contentLength
        return Data(bytes[start..<end])
    }
}
