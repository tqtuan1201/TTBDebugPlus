//
//  LocalhostPortScanner.swift
//  TTBDebugPlus
//
//  Discovers TCP LISTEN endpoints via `lsof`. Pure parsing is unit-testable.
//

import Foundation

enum LocalhostPortScanner {
    struct ScanResult: Sendable {
        var endpoints: [ListeningEndpoint]
        /// Technical stderr / process error (may be empty).
        var rawError: String?
        /// Copy shown in UI (sanitized, high-signal).
        var userFacingError: String?
        /// True when no endpoints could be listed.
        var isHardFailure: Bool
    }

    /// Parse `lsof -nP +c 0 -iTCP -sTCP:LISTEN` style output.
    static func parseLsofOutput(
        _ output: String,
        protectedPIDs: Set<Int32> = [],
        protectedPorts: Set<Int> = []
    ) -> [ListeningEndpoint] {
        var results: [ListeningEndpoint] = []
        var seen = Set<String>()

        let lines = output.split(whereSeparator: \.isNewline)
        for (index, line) in lines.enumerated() {
            if index == 0 && line.lowercased().hasPrefix("command") {
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Columns: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // NAME examples: *:3000 (LISTEN), 127.0.0.1:5173 (LISTEN), [::1]:8080 (LISTEN)
            // With +c 0, COMMAND may contain spaces encoded as \x20.
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 9 else { continue }

            let processName = decodeLsofCommandName(parts[0])
            guard let pid = Int32(parts[1]) else { continue }

            // NAME is last field(s); re-join from index 8 for safety.
            let nameField = parts[8...]
                .joined(separator: " ")
            guard nameField.contains("(LISTEN)") || nameField.uppercased().contains("LISTEN") else {
                continue
            }

            guard let (address, port) = parseAddressPort(from: nameField) else { continue }

            let id = "\(pid):\(port):\(address)"
            guard !seen.contains(id) else { continue }
            seen.insert(id)

            let classification = LocalhostProcessClassifier.classify(
                processName: processName,
                pid: pid,
                port: port,
                protectedPIDs: protectedPIDs,
                protectedPorts: protectedPorts
            )

            results.append(
                ListeningEndpoint(
                    id: id,
                    address: address,
                    addresses: [address],
                    port: port,
                    pid: pid,
                    processName: processName,
                    classification: classification
                )
            )
        }

        return dedupeEndpoints(
            results.sorted { lhs, rhs in
                if lhs.port != rhs.port { return lhs.port < rhs.port }
                return lhs.pid < rhs.pid
            }
        )
    }

    /// Merge IPv4/IPv6 (and multi-bind) rows for the same pid+port into one endpoint.
    static func dedupeEndpoints(_ endpoints: [ListeningEndpoint]) -> [ListeningEndpoint] {
        var order: [String] = []
        var buckets: [String: ListeningEndpoint] = [:]

        for endpoint in endpoints {
            let key = "\(endpoint.pid):\(endpoint.port)"
            if var existing = buckets[key] {
                for addr in endpoint.addresses where !existing.addresses.contains(addr) {
                    existing.addresses.append(addr)
                }
                // Prefer a concrete loopback / non-wildcard as primary display address.
                existing.address = preferredPrimaryAddress(
                    current: existing.address,
                    candidate: endpoint.address,
                    all: existing.addresses
                )
                // Prefer longer/full process names if a later row is richer (shouldn't differ).
                if endpoint.processName.count > existing.processName.count {
                    existing.processName = endpoint.processName
                }
                // Prefer stricter classification (ttbdebug > system > docker > user > unknown).
                existing.classification = stricterClass(existing.classification, endpoint.classification)
                buckets[key] = existing
            } else {
                var copy = endpoint
                copy.id = key
                if copy.addresses.isEmpty {
                    copy.addresses = [copy.address]
                }
                buckets[key] = copy
                order.append(key)
            }
        }

        return order.compactMap { buckets[$0] }.sorted { lhs, rhs in
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.pid < rhs.pid
        }
    }

    private static func preferredPrimaryAddress(
        current: String,
        candidate: String,
        all: [String]
    ) -> String {
        let rank: (String) -> Int = { addr in
            if addr == "127.0.0.1" { return 0 }
            if addr == "[::1]" || addr == "::1" { return 1 }
            if addr == "*" || addr == "0.0.0.0" || addr == "::" { return 3 }
            return 2
        }
        let best = all.min(by: { rank($0) < rank($1) }) ?? current
        let candidateRank = rank(candidate)
        let currentRank = rank(current)
        if candidateRank < currentRank { return candidate }
        return rank(best) < currentRank ? best : current
    }

    private static func stricterClass(_ a: ProcessClass, _ b: ProcessClass) -> ProcessClass {
        func rank(_ c: ProcessClass) -> Int {
            switch c {
            case .ttbdebug: return 0
            case .system: return 1
            case .docker: return 2
            case .user: return 3
            case .unknown: return 4
            }
        }
        return rank(a) <= rank(b) ? a : b
    }

    /// Decode lsof COMMAND escapes such as `\x20` (space) into real characters.
    static func decodeLsofCommandName(_ raw: String) -> String {
        var result = ""
        result.reserveCapacity(raw.count)
        var index = raw.startIndex
        while index < raw.endIndex {
            if raw[index] == "\\" {
                let afterSlash = raw.index(after: index)
                if afterSlash < raw.endIndex, raw[afterSlash] == "x" {
                    let hexStart = raw.index(after: afterSlash)
                    if let hexEnd = raw.index(hexStart, offsetBy: 2, limitedBy: raw.endIndex),
                       hexEnd == raw.index(hexStart, offsetBy: 2) {
                        let hex = raw[hexStart..<hexEnd]
                        if let value = UInt8(hex, radix: 16),
                           let scalar = UnicodeScalar(UInt32(value)) {
                            result.append(Character(scalar))
                            index = hexEnd
                            continue
                        }
                    }
                }
            }
            result.append(raw[index])
            index = raw.index(after: index)
        }
        return result
    }

    /// Extract host + port from lsof NAME column.
    static func parseAddressPort(from nameField: String) -> (String, Int)? {
        // Strip " (LISTEN)" suffix variants.
        var field = nameField
        if let range = field.range(of: " (LISTEN)", options: .caseInsensitive) {
            field = String(field[..<range.lowerBound])
        } else if let range = field.range(of: "(LISTEN)", options: .caseInsensitive) {
            field = String(field[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // IPv6: [::1]:5173 or *:443
        if field.hasPrefix("["), let close = field.firstIndex(of: "]") {
            let addr = String(field[field.startIndex...close])
            let after = field[field.index(after: close)...]
            guard after.hasPrefix(":"), let port = Int(after.dropFirst()) else { return nil }
            return (addr, port)
        }

        // host:port — take last colon as port separator (IPv4 / *)
        guard let colon = field.lastIndex(of: ":") else { return nil }
        let address = String(field[..<colon])
        let portString = String(field[field.index(after: colon)...])
        // Drop trailing junk if any
        let digits = portString.prefix { $0.isNumber }
        guard let port = Int(digits), port > 0, port <= 65_535 else { return nil }
        return (address.isEmpty ? "*" : address, port)
    }

    /// Run lsof on a background queue and return endpoints.
    static func scan(
        protectedPIDs: Set<Int32>,
        protectedPorts: Set<Int>
    ) async -> ScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = runLsof(
                    protectedPIDs: protectedPIDs,
                    protectedPorts: protectedPorts
                )
                continuation.resume(returning: result)
            }
        }
    }

    private static func runLsof(
        protectedPIDs: Set<Int32>,
        protectedPorts: Set<Int>
    ) -> ScanResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +c 0: full COMMAND names (avoids "ControlCe" truncation → misclassification).
        process.arguments = ["-nP", "+c", "0", "-iTCP", "-sTCP:LISTEN"]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let msg = "Failed to run lsof: \(error.localizedDescription)"
            return ScanResult(
                endpoints: [],
                rawError: msg,
                userFacingError: msg,
                isHardFailure: true
            )
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let endpoints = parseLsofOutput(
            output,
            protectedPIDs: protectedPIDs,
            protectedPorts: protectedPorts
        )

        // Sandbox often emits "can't get PID byte count: Operation not permitted"
        // even when some rows are returned — never treat that alone as total failure
        // if we parsed listeners.
        if !endpoints.isEmpty {
            return ScanResult(
                endpoints: endpoints,
                rawError: errText.isEmpty ? nil : errText,
                userFacingError: nil,
                isHardFailure: false
            )
        }

        if process.terminationStatus != 0 || !errText.isEmpty {
            return ScanResult(
                endpoints: [],
                rawError: errText.isEmpty ? "lsof status \(process.terminationStatus)" : errText,
                userFacingError: sanitizeLsofError(errText, status: process.terminationStatus),
                isHardFailure: true
            )
        }

        return ScanResult(
            endpoints: [],
            rawError: nil,
            userFacingError: nil,
            isHardFailure: false
        )
    }

    /// Map raw lsof noise into readable, actionable copy.
    /// Note: App Sandbox is OFF for DMG builds; residual EPERM usually means
    /// TCC/privacy, SIP-protected processes, or missing Full Disk Access edge cases.
    static func sanitizeLsofError(_ errText: String, status: Int32) -> String {
        let lower = errText.lowercased()
        if lower.contains("operation not permitted") || lower.contains("pid byte count") {
            return "Port discovery was blocked by macOS (permission denied). Quit and relaunch the app after a clean rebuild without App Sandbox. If it persists, try Terminal: lsof -nP +c 0 -iTCP -sTCP:LISTEN"
        }
        if errText.isEmpty {
            return "Port discovery failed (lsof exit \(status)). Ensure /usr/sbin/lsof is available and the app was rebuilt without App Sandbox."
        }
        return errText
    }

    /// First endpoint listening on the given port (any address).
    static func occupant(
        of port: Int,
        in endpoints: [ListeningEndpoint]
    ) -> ListeningEndpoint? {
        endpoints.first { $0.port == port }
    }
}
