//
//  JWTCrypto.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Offline signature verification and signing for JWS tokens.
//  HMAC + ECDSA via CryptoKit; RSA PKCS#1 v1.5 via the Security framework.
//  No network access — all key material stays in memory.
//

import Foundation
import CryptoKit
import Security

enum JWTCrypto {

    // MARK: - Verify

    /// Verify the signature of a decoded token.
    /// - Parameters:
    ///   - decoded: the parsed token (provides signing input + signature segment).
    ///   - algorithm: algorithm to verify against (usually `decoded.algorithm`).
    ///   - key: shared secret (HMAC) or PEM public key (RSA/ECDSA).
    static func verify(decoded: DecodedJWT, algorithm: JWTAlgorithm, key: String) throws -> Bool {
        guard let signingInput = decoded.signingInput.data(using: .utf8) else {
            throw JWTError.malformed("signing input not UTF-8")
        }
        guard let signature = JWTDecoder.base64URLDecode(decoded.signatureSegment) else {
            throw JWTError.invalidBase64
        }

        switch algorithm.family {
        case .none:
            // Unsecured tokens are "valid" only when the signature is empty.
            return decoded.signatureSegment.isEmpty

        case .hmac:
            let expected = try hmacSignature(signingInput, algorithm: algorithm, secret: key)
            // Constant-time-ish comparison via Data equality on fixed-length MACs.
            return constantTimeEquals(expected, signature)

        case .ecdsa:
            return try verifyECDSA(signingInput: signingInput, signature: signature,
                                   algorithm: algorithm, pemPublicKey: key)

        case .rsa:
            return try verifyRSA(signingInput: signingInput, signature: signature,
                                 algorithm: algorithm, pemPublicKey: key)
        }
    }

    // MARK: - Sign

    /// Produce a compact JWT string from header/payload JSON and key material.
    /// - Parameters:
    ///   - headerJSON: raw header JSON (alg/typ set by caller).
    ///   - payloadJSON: raw payload JSON.
    ///   - algorithm: signing algorithm.
    ///   - key: shared secret (HMAC) or PEM private key (RSA/ECDSA). Ignored for `none`.
    static func sign(headerJSON: String, payloadJSON: String,
                     algorithm: JWTAlgorithm, key: String) throws -> String {
        let headerSegment = JWTDecoder.base64URLEncode(Data(compact(headerJSON).utf8))
        let payloadSegment = JWTDecoder.base64URLEncode(Data(compact(payloadJSON).utf8))
        let signingInputString = "\(headerSegment).\(payloadSegment)"
        guard let signingInput = signingInputString.data(using: .utf8) else {
            throw JWTError.signingFailed("signing input not UTF-8")
        }

        switch algorithm.family {
        case .none:
            return "\(signingInputString)."

        case .hmac:
            let mac = try hmacSignature(signingInput, algorithm: algorithm, secret: key)
            return "\(signingInputString).\(JWTDecoder.base64URLEncode(mac))"

        case .ecdsa:
            let sig = try signECDSA(signingInput: signingInput, algorithm: algorithm, pemPrivateKey: key)
            return "\(signingInputString).\(JWTDecoder.base64URLEncode(sig))"

        case .rsa:
            let sig = try signRSA(signingInput: signingInput, algorithm: algorithm, pemPrivateKey: key)
            return "\(signingInputString).\(JWTDecoder.base64URLEncode(sig))"
        }
    }

    // MARK: - HMAC

    private static func hmacSignature(_ data: Data, algorithm: JWTAlgorithm, secret: String) throws -> Data {
        guard !secret.isEmpty else { throw JWTError.invalidKey("secret is empty") }
        let keyData = Data(secret.utf8)
        let symmetricKey = SymmetricKey(data: keyData)
        switch algorithm {
        case .hs256:
            return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        case .hs384:
            return Data(HMAC<SHA384>.authenticationCode(for: data, using: symmetricKey))
        case .hs512:
            return Data(HMAC<SHA512>.authenticationCode(for: data, using: symmetricKey))
        default:
            throw JWTError.unsupportedAlgorithm(algorithm.rawValue)
        }
    }

    // MARK: - ECDSA (CryptoKit)

    private static func verifyECDSA(signingInput: Data, signature: Data,
                                    algorithm: JWTAlgorithm, pemPublicKey: String) throws -> Bool {
        switch algorithm {
        case .es256:
            let key = try P256.Signing.PublicKey(pemRepresentation: pemPublicKey)
            let sig = try P256.Signing.ECDSASignature(rawRepresentation: signature)
            return key.isValidSignature(sig, for: SHA256.hash(data: signingInput))
        case .es384:
            let key = try P384.Signing.PublicKey(pemRepresentation: pemPublicKey)
            let sig = try P384.Signing.ECDSASignature(rawRepresentation: signature)
            return key.isValidSignature(sig, for: SHA384.hash(data: signingInput))
        case .es512:
            let key = try P521.Signing.PublicKey(pemRepresentation: pemPublicKey)
            let sig = try P521.Signing.ECDSASignature(rawRepresentation: signature)
            return key.isValidSignature(sig, for: SHA512.hash(data: signingInput))
        default:
            throw JWTError.unsupportedAlgorithm(algorithm.rawValue)
        }
    }

    private static func signECDSA(signingInput: Data, algorithm: JWTAlgorithm,
                                  pemPrivateKey: String) throws -> Data {
        do {
            switch algorithm {
            case .es256:
                let key = try P256.Signing.PrivateKey(pemRepresentation: pemPrivateKey)
                return try key.signature(for: SHA256.hash(data: signingInput)).rawRepresentation
            case .es384:
                let key = try P384.Signing.PrivateKey(pemRepresentation: pemPrivateKey)
                return try key.signature(for: SHA384.hash(data: signingInput)).rawRepresentation
            case .es512:
                let key = try P521.Signing.PrivateKey(pemRepresentation: pemPrivateKey)
                return try key.signature(for: SHA512.hash(data: signingInput)).rawRepresentation
            default:
                throw JWTError.unsupportedAlgorithm(algorithm.rawValue)
            }
        } catch let error as JWTError {
            throw error
        } catch {
            throw JWTError.invalidKey("could not parse EC private key (\(error.localizedDescription))")
        }
    }

    // MARK: - RSA (Security framework)

    private static func verifyRSA(signingInput: Data, signature: Data,
                                  algorithm: JWTAlgorithm, pemPublicKey: String) throws -> Bool {
        let secKey = try RSAKeyImporter.publicKey(fromPEM: pemPublicKey)
        let secAlgorithm = rsaSecAlgorithm(algorithm)
        // Guard against a key that cannot perform this operation (wrong type/size).
        guard SecKeyIsAlgorithmSupported(secKey, .verify, secAlgorithm) else {
            throw JWTError.invalidKey("the RSA key does not support \(algorithm.rawValue)")
        }
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(secKey, secAlgorithm,
                                       signingInput as CFData, signature as CFData, &error)
        // The key is already validated at import, so a false result here means the
        // signature simply does not match — not a setup failure.
        return ok
    }

    private static func signRSA(signingInput: Data, algorithm: JWTAlgorithm,
                                pemPrivateKey: String) throws -> Data {
        let secKey = try RSAKeyImporter.privateKey(fromPEM: pemPrivateKey)
        let secAlgorithm = rsaSecAlgorithm(algorithm)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(secKey, secAlgorithm,
                                                    signingInput as CFData, &error) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown RSA signing error"
            throw JWTError.signingFailed(message)
        }
        return signature
    }

    private static func rsaSecAlgorithm(_ algorithm: JWTAlgorithm) -> SecKeyAlgorithm {
        switch algorithm {
        case .rs256: return .rsaSignatureMessagePKCS1v15SHA256
        case .rs384: return .rsaSignatureMessagePKCS1v15SHA384
        case .rs512: return .rsaSignatureMessagePKCS1v15SHA512
        default:     return .rsaSignatureMessagePKCS1v15SHA256
        }
    }

    // MARK: - Utilities

    /// Minify a JSON string so signing input matches the serialized form.
    private static func compact(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let compactData = try? JSONSerialization.data(withJSONObject: object,
                                                            options: [.withoutEscapingSlashes]),
              let result = String(data: compactData, encoding: .utf8) else {
            // Fall back to the trimmed original if it isn't valid JSON.
            return json.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }
}
