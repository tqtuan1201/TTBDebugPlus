//
//  JWTSecurityAnalyzer.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-06-16.
//  Static, offline security analysis of a decoded JWT — flags alg:none,
//  algorithm confusion risks, expiry/validity problems, and weak claims.
//

import Foundation

enum JWTSecurityAnalyzer {

    /// Inspect a decoded token and (optionally) the secret used for HMAC
    /// verification, returning findings sorted most-severe first.
    static func analyze(_ token: DecodedJWT, hmacSecret: String? = nil) -> [JWTSecurityFinding] {
        var findings: [JWTSecurityFinding] = []
        let now = Date()

        // MARK: Algorithm
        let rawAlg = token.rawAlgorithm?.lowercased()
        if rawAlg == "none" || (token.algorithm == JWTAlgorithm.none) {
            findings.append(.init(
                severity: .critical,
                title: "Unsecured token (alg: none)",
                detail: "The header declares `none`, meaning the token is not signed. A server that honors this can be trivially forged. Reject `alg: none` tokens."
            ))
        } else if token.algorithm == nil {
            findings.append(.init(
                severity: .medium,
                title: "Unrecognized algorithm",
                detail: "The `alg` header value \"\(token.rawAlgorithm ?? "?")\" is not a standard JWS algorithm this tool recognizes."
            ))
        }

        if token.signatureSegment.isEmpty && rawAlg != "none" {
            findings.append(.init(
                severity: .critical,
                title: "Missing signature",
                detail: "The token has no signature segment but declares a signing algorithm. It cannot be authenticated."
            ))
        }

        if let alg = token.algorithm, alg.family == .hmac {
            findings.append(.init(
                severity: .info,
                title: "Symmetric algorithm (\(alg.rawValue))",
                detail: "HMAC tokens are signed and verified with the same shared secret. Anyone who can verify can also forge — keep the secret server-side and ensure it is long and random."
            ))
        }

        if let alg = token.algorithm, alg.family == .rsa || alg.family == .ecdsa {
            findings.append(.init(
                severity: .low,
                title: "Confirm algorithm pinning",
                detail: "\(alg.rawValue) uses public-key verification. Ensure the verifier pins this algorithm; allowing the algorithm to be chosen from the header enables alg-confusion (e.g. RS256 → HS256) attacks."
            ))
        }

        // MARK: HMAC secret strength (only when a secret was provided)
        if let secret = hmacSecret, let alg = token.algorithm, alg.family == .hmac, !secret.isEmpty {
            if secret.utf8.count < 32 {
                findings.append(.init(
                    severity: .high,
                    title: "Weak HMAC secret",
                    detail: "The provided secret is \(secret.utf8.count) bytes. For \(alg.rawValue), use at least the hash output size (32/48/64 bytes) of high-entropy random data."
                ))
            }
            if isLikelyDictionaryWord(secret) {
                findings.append(.init(
                    severity: .high,
                    title: "Guessable HMAC secret",
                    detail: "The secret looks like a common/dictionary value. HMAC secrets must be unguessable random strings."
                ))
            }
        }

        // MARK: Expiry / validity
        if let exp = token.expiresAt {
            if exp < now {
                findings.append(.init(
                    severity: .high,
                    title: "Token expired",
                    detail: "`exp` is \(format(exp)), already in the past. The token should be rejected."
                ))
            } else if let iat = token.issuedAt, exp.timeIntervalSince(iat) > 86_400 {
                findings.append(.init(
                    severity: .low,
                    title: "Long-lived token",
                    detail: "The token is valid for \(durationString(exp.timeIntervalSince(iat))). Long lifetimes widen the window for stolen-token abuse; prefer short-lived access tokens with refresh."
                ))
            }
        } else {
            findings.append(.init(
                severity: .medium,
                title: "No expiration (exp)",
                detail: "The payload has no `exp` claim, so the token never expires on its own. Add an expiration to bound its lifetime."
            ))
        }

        if let nbf = token.notBefore, nbf > now {
            findings.append(.init(
                severity: .medium,
                title: "Not yet valid (nbf)",
                detail: "`nbf` is \(format(nbf)); the token is not valid until then."
            ))
        }

        if let iat = token.issuedAt, iat > now.addingTimeInterval(60) {
            findings.append(.init(
                severity: .low,
                title: "Issued in the future (iat)",
                detail: "`iat` is \(format(iat)), in the future. This often indicates clock skew or a tampered token."
            ))
        }

        // MARK: Claim hygiene
        if token.payload["iss"] == nil {
            findings.append(.init(
                severity: .low,
                title: "No issuer (iss)",
                detail: "Without an `iss` claim, the verifier cannot confirm which authority minted the token."
            ))
        }
        if token.payload["aud"] == nil {
            findings.append(.init(
                severity: .low,
                title: "No audience (aud)",
                detail: "Without an `aud` claim, a token minted for one service can be replayed against another."
            ))
        }

        // MARK: Header hygiene
        if let typ = token.header["typ"] as? String, typ.lowercased() != "jwt" {
            findings.append(.init(
                severity: .info,
                title: "Unusual `typ` header",
                detail: "Header `typ` is \"\(typ)\" rather than \"JWT\"."
            ))
        }
        if token.header["jku"] != nil || token.header["x5u"] != nil {
            findings.append(.init(
                severity: .medium,
                title: "Remote key reference in header",
                detail: "The header references a remote key (`jku`/`x5u`). If the verifier fetches keys from an attacker-controlled URL, signatures can be spoofed. Restrict to a trusted allowlist."
            ))
        }

        if findings.isEmpty {
            findings.append(.init(
                severity: .info,
                title: "No obvious issues found",
                detail: "Static checks passed. This does not verify the signature — use the Verify tab with the correct key."
            ))
        }

        return findings.sorted { $0.severity > $1.severity }
    }

    // MARK: - Helpers

    private static let commonWeakSecrets: Set<String> = [
        "secret", "password", "changeme", "your-256-bit-secret", "test", "key",
        "jwtsecret", "supersecret", "admin", "private", "secretkey", "mysecret"
    ]

    private static func isLikelyDictionaryWord(_ secret: String) -> Bool {
        commonWeakSecrets.contains(secret.lowercased())
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func durationString(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "\(Int(interval))s"
    }
}
