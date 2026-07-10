//
//  JSONRepairEngine.swift
//  TTBDebugPlus / JSONTools
//
//  Pure Swift JSON validation + iterative auto-repair for common malformed payloads.
//  Pipeline: normalize → deep passes (loop until stable) → re-validate → optional pretty.
//

import Foundation

// MARK: - Models

enum JSONRepairKind: String, CaseIterable, Sendable {
    case stripBOM
    case stripComments
    case trailingComma
    case singleQuotes
    case unquotedKeys
    case pythonLiterals
    case missingComma
    case balanceBraces
    case escapeControlChars
    case wrapRoot
    case trimNoise
    case prettyPrint
}

struct JSONRepairFix: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: JSONRepairKind
    let description: String
    let count: Int

    init(kind: JSONRepairKind, description: String, count: Int = 1) {
        self.id = UUID()
        self.kind = kind
        self.description = description
        self.count = count
    }
}

struct JSONRepairResult: Equatable, Sendable {
    let original: String
    let repaired: String
    let fixes: [JSONRepairFix]
    let isValidAfterRepair: Bool
    let validationMessage: String?
    /// Human-readable reason when repair could not produce valid JSON.
    let failureReason: String?

    var didChange: Bool { original != repaired }
    var hasFixes: Bool { !fixes.isEmpty }
    var canSafelyApply: Bool { isValidAfterRepair && didChange }

    init(
        original: String,
        repaired: String,
        fixes: [JSONRepairFix],
        isValidAfterRepair: Bool,
        validationMessage: String?,
        failureReason: String? = nil
    ) {
        self.original = original
        self.repaired = repaired
        self.fixes = fixes
        self.isValidAfterRepair = isValidAfterRepair
        self.validationMessage = validationMessage
        self.failureReason = failureReason
    }
}

struct JSONParseIssue: Equatable, Sendable {
    let line: Int
    let column: Int
    let message: String
    let friendlyMessage: String
}

// MARK: - Validation

enum JSONValidator {
    /// Parse JSON; returns nil on success, issue on failure.
    /// Empty / whitespace-only is treated as "no content" (not an error).
    static func validate(_ text: String) -> JSONParseIssue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = text.data(using: .utf8) else {
            return JSONParseIssue(
                line: 1, column: 1,
                message: "Invalid UTF-8 encoding",
                friendlyMessage: "Text is not valid UTF-8. Re-paste as plain text."
            )
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return nil
        } catch let error as NSError {
            let desc = error.localizedDescription
            let (line, col) = position(in: text, errorDescription: desc)
            return JSONParseIssue(
                line: line,
                column: col,
                message: desc,
                friendlyMessage: friendlyMessage(from: desc, line: line, column: col)
            )
        }
    }

    static func isValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false } // empty is not "valid JSON" for apply gates
        return validate(text) == nil
    }

    /// Empty is OK for editor empty-state, but not a successful repair target.
    static func isValidOrEmpty(_ text: String) -> Bool {
        validate(text) == nil
    }

    static func friendlyMessage(from desc: String, line: Int, column: Int) -> String {
        let lower = desc.lowercased()
        if lower.contains("unexpected end") || lower.contains("eof") {
            return "Unexpected end of JSON at line \(line). A closing brace `}` or bracket `]` may be missing."
        }
        if lower.contains("trailing comma") || (lower.contains("comma") && lower.contains("}")) {
            return "Trailing comma near line \(line), column \(column). Remove the last comma before `}` or `]`."
        }
        if lower.contains("expected") && lower.contains("\"") {
            return "Expected a string key near line \(line), column \(column). Object keys must be double-quoted."
        }
        if lower.contains("invalid escape") {
            return "Invalid escape sequence near line \(line), column \(column). Use `\\\\`, `\\\"`, `\\n`, or `\\uXXXX`."
        }
        if lower.contains("number") {
            return "Invalid number near line \(line), column \(column). Check decimals, leading zeros, or incomplete values."
        }
        if lower.contains("character") || lower.contains("token") {
            return "Unexpected token near line \(line), column \(column). Check quotes, commas, and brackets."
        }
        return "Invalid JSON near line \(line), column \(column): \(desc)"
    }

    static func position(in json: String, errorDescription: String) -> (Int, Int) {
        let lines = json.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if let lineMatch = errorDescription.range(of: #"line\s+(\d+)"#, options: .regularExpression) {
            let lineStr = errorDescription[lineMatch].filter(\.isNumber)
            let line = Int(lineStr) ?? 1
            var col = 1
            if let colMatch = errorDescription.range(of: #"column\s+(\d+)"#, options: .regularExpression) {
                col = Int(errorDescription[colMatch].filter(\.isNumber)) ?? 1
            }
            return (max(1, line), max(1, col))
        }

        if let range = errorDescription.range(of: #"character\s+\(?(\d+)"#, options: .regularExpression) {
            let numStr = errorDescription[range].filter(\.isNumber)
            if let offset = Int(numStr), offset > 0 {
                var current = 0
                for (idx, line) in lines.enumerated() {
                    let lineLen = line.utf8.count + 1
                    if current + lineLen > offset {
                        return (idx + 1, max(1, offset - current + 1))
                    }
                    current += lineLen
                }
            }
        }

        return (1, 1)
    }
}

// MARK: - Pretty / Minify

enum JSONFormatter {
    static func prettyPrint(_ text: String, indentation: Int = 2) -> String? {
        guard JSONValidator.isValid(text),
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        let indent = max(1, min(indentation, 8))
        let base = detectIndentUnit(in: str)
        guard base > 0, base != indent else { return str }

        let unit = String(repeating: " ", count: indent)
        return str.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let s = String(line)
            let leading = s.prefix(while: { $0 == " " }).count
            let levels = leading / base
            return String(repeating: unit, count: levels) + s.dropFirst(leading)
        }.joined(separator: "\n")
    }

    private static func detectIndentUnit(in pretty: String) -> Int {
        for line in pretty.split(separator: "\n") {
            let leading = line.prefix(while: { $0 == " " }).count
            if leading > 0 { return leading }
        }
        return 2
    }

    static func minify(_ text: String) -> String? {
        guard JSONValidator.isValid(text),
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let compact = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: compact, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func countNodes(_ text: String) -> Int {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return 0
        }
        return countNodes(obj)
    }

    private static func countNodes(_ value: Any) -> Int {
        if let dict = value as? [String: Any] {
            return 1 + dict.values.reduce(0) { $0 + countNodes($1) }
        }
        if let arr = value as? [Any] {
            return 1 + arr.reduce(0) { $0 + countNodes($1) }
        }
        return 1
    }
}

// MARK: - Repair Engine

enum JSONRepairEngine {

    private static let maxIterations = 8

    /// Attempt to repair common JSON mistakes. Does not mutate input.
    /// Iterates passes until stable so order-dependent fixes (keys ↔ commas) converge.
    static func repair(_ input: String) -> JSONRepairResult {
        var text = input
        var fixes: [JSONRepairFix] = []

        // Empty input
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return JSONRepairResult(
                original: input,
                repaired: text,
                fixes: [],
                isValidAfterRepair: false,
                validationMessage: "Editor is empty — paste or open a JSON file first.",
                failureReason: "No content to repair."
            )
        }

        for _ in 0..<maxIterations {
            let before = text
            var roundFixes: [JSONRepairFix] = []

            // 1. BOM
            if text.hasPrefix("\u{FEFF}") {
                text.removeFirst()
                roundFixes.append(JSONRepairFix(kind: .stripBOM, description: "Removed UTF-8 BOM"))
            }

            // 2. Comments
            let (noComments, commentCount) = stripComments(text)
            if commentCount > 0 {
                text = noComments
                roundFixes.append(JSONRepairFix(
                    kind: .stripComments,
                    description: "Removed \(commentCount) JS-style comment(s)",
                    count: commentCount
                ))
            }

            // 3. Python / JS literals (before quotes so True isn't inside strings wrongly)
            let (litFixed, litCount) = replacePythonLiterals(text)
            if litCount > 0 {
                text = litFixed
                roundFixes.append(JSONRepairFix(
                    kind: .pythonLiterals,
                    description: "Replaced True/False/None/undefined (\(litCount))",
                    count: litCount
                ))
            }

            // 4. Single-quoted strings → double-quoted
            let (sqFixed, sqCount) = convertSingleQuotedStrings(text)
            if sqCount > 0 {
                text = sqFixed
                roundFixes.append(JSONRepairFix(
                    kind: .singleQuotes,
                    description: "Converted \(sqCount) single-quoted string(s)",
                    count: sqCount
                ))
            }

            // 5. Insert missing commas (before quoting keys so `1 b:` becomes `1, b:`)
            let (mcFixed, mcCount) = insertMissingCommas(text)
            if mcCount > 0 {
                text = mcFixed
                roundFixes.append(JSONRepairFix(
                    kind: .missingComma,
                    description: "Inserted \(mcCount) missing comma(s)",
                    count: mcCount
                ))
            }

            // 6. Quote unquoted keys
            let (keyFixed, keyCount) = quoteUnquotedKeys(text)
            if keyCount > 0 {
                text = keyFixed
                roundFixes.append(JSONRepairFix(
                    kind: .unquotedKeys,
                    description: "Quoted \(keyCount) unquoted object key(s)",
                    count: keyCount
                ))
            }

            // 7. Trailing commas
            let (tcFixed, tcCount) = removeTrailingCommas(text)
            if tcCount > 0 {
                text = tcFixed
                roundFixes.append(JSONRepairFix(
                    kind: .trailingComma,
                    description: "Removed \(tcCount) trailing comma(s)",
                    count: tcCount
                ))
            }

            // 8. Escape control chars in strings
            let (escFixed, escCount) = escapeControlCharactersInStrings(text)
            if escCount > 0 {
                text = escFixed
                roundFixes.append(JSONRepairFix(
                    kind: .escapeControlChars,
                    description: "Escaped \(escCount) control character(s) in strings",
                    count: escCount
                ))
            }

            // 9. Balance braces
            let (balFixed, balDesc) = balanceBrackets(text)
            if balFixed != text {
                text = balFixed
                roundFixes.append(JSONRepairFix(kind: .balanceBraces, description: balDesc))
            }

            // 10. Trim trailing noise
            if let trimmed = trimTrailingNoise(text), trimmed != text {
                text = trimmed
                roundFixes.append(JSONRepairFix(kind: .trimNoise, description: "Trimmed trailing non-JSON noise"))
            }

            // 11. Multi-root wrap
            if !JSONValidator.isValid(text), looksLikeMultipleRoots(text) {
                let wrapped = "[\(text)]"
                if JSONValidator.isValid(wrapped) {
                    text = wrapped
                    roundFixes.append(JSONRepairFix(kind: .wrapRoot, description: "Wrapped multiple root values in an array"))
                }
            }

            mergeFixes(&fixes, roundFixes)

            // Converged
            if text == before { break }
            // Valid after this round — still loop once more for trailing-comma normalize only if needed
            if JSONValidator.isValid(text) {
                let (tc2, n2) = removeTrailingCommas(text)
                if n2 > 0 {
                    text = tc2
                    mergeFixes(&fixes, [JSONRepairFix(
                        kind: .trailingComma,
                        description: "Removed \(n2) trailing comma(s)",
                        count: n2
                    )])
                }
                break
            }
        }

        let issue = JSONValidator.validate(text)
        let valid = issue == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        var failure: String?
        if !valid {
            if fixes.isEmpty {
                failure = issue?.friendlyMessage
                    ?? "No automatic fix pattern matched this JSON. Fix manually or simplify the input."
            } else {
                failure = "Applied \(fixes.count) fix step(s) but result is still invalid. "
                    + (issue?.friendlyMessage ?? "Please correct remaining syntax manually.")
            }
        }

        return JSONRepairResult(
            original: input,
            repaired: text,
            fixes: fixes,
            isValidAfterRepair: valid,
            validationMessage: issue?.friendlyMessage,
            failureReason: failure
        )
    }

    /// Repair then pretty-print **only when valid**.
    static func autoFormat(_ input: String, indentation: Int = 2) -> JSONRepairResult {
        let result = repair(input)
        guard result.isValidAfterRepair else { return result }

        guard let pretty = JSONFormatter.prettyPrint(result.repaired, indentation: indentation) else {
            return result
        }
        guard pretty != result.repaired else { return result }

        var fixes = result.fixes
        fixes.append(JSONRepairFix(kind: .prettyPrint, description: "Applied pretty-print formatting"))
        return JSONRepairResult(
            original: input,
            repaired: pretty,
            fixes: fixes,
            isValidAfterRepair: true,
            validationMessage: nil,
            failureReason: nil
        )
    }

    private static func mergeFixes(_ into: inout [JSONRepairFix], _ more: [JSONRepairFix]) {
        for f in more {
            if let idx = into.firstIndex(where: { $0.kind == f.kind }) {
                let old = into[idx]
                into[idx] = JSONRepairFix(
                    kind: f.kind,
                    description: f.description,
                    count: old.count + f.count
                )
            } else {
                into.append(f)
            }
        }
    }

    // MARK: - Passes

    private static func stripComments(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count)
        var count = 0
        var i = input.startIndex
        var inString = false
        var escape = false

        while i < input.endIndex {
            let c = input[i]
            if inString {
                out.append(c)
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                i = input.index(after: i)
                continue
            }

            if c == "\"" {
                inString = true
                out.append(c)
                i = input.index(after: i)
                continue
            }

            if c == "/", input.index(after: i) < input.endIndex, input[input.index(after: i)] == "/" {
                count += 1
                i = input.index(after: input.index(after: i))
                while i < input.endIndex, input[i] != "\n" {
                    i = input.index(after: i)
                }
                continue
            }

            if c == "/", input.index(after: i) < input.endIndex, input[input.index(after: i)] == "*" {
                count += 1
                i = input.index(after: input.index(after: i))
                while i < input.endIndex {
                    if input[i] == "*", input.index(after: i) < input.endIndex,
                       input[input.index(after: i)] == "/" {
                        i = input.index(after: input.index(after: i))
                        break
                    }
                    i = input.index(after: i)
                }
                continue
            }

            out.append(c)
            i = input.index(after: i)
        }
        return (out, count)
    }

    private static func replacePythonLiterals(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count)
        var count = 0
        var i = input.startIndex
        var inString = false
        var escape = false

        func match(_ word: String) -> Bool {
            var j = i
            for ch in word {
                guard j < input.endIndex, input[j] == ch else { return false }
                j = input.index(after: j)
            }
            if j < input.endIndex {
                let next = input[j]
                if next.isLetter || next.isNumber || next == "_" { return false }
            }
            if i > input.startIndex {
                let prev = input[input.index(before: i)]
                if prev.isLetter || prev.isNumber || prev == "_" { return false }
            }
            return true
        }

        let replacements: [(String, String)] = [
            ("True", "true"), ("False", "false"), ("None", "null"),
            ("undefined", "null"), ("NaN", "null"), ("Infinity", "null")
        ]

        while i < input.endIndex {
            let c = input[i]
            if inString {
                out.append(c)
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                i = input.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i = input.index(after: i)
                continue
            }

            var replaced = false
            for (from, to) in replacements {
                if match(from) {
                    out.append(contentsOf: to)
                    i = input.index(i, offsetBy: from.count)
                    count += 1
                    replaced = true
                    break
                }
            }
            if replaced { continue }

            out.append(c)
            i = input.index(after: i)
        }
        return (out, count)
    }

    private static func convertSingleQuotedStrings(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count)
        var count = 0
        var i = input.startIndex
        var inDouble = false
        var escape = false

        while i < input.endIndex {
            let c = input[i]
            if inDouble {
                out.append(c)
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inDouble = false }
                i = input.index(after: i)
                continue
            }

            if c == "\"" {
                inDouble = true
                out.append(c)
                i = input.index(after: i)
                continue
            }

            if c == "'" {
                count += 1
                out.append("\"")
                i = input.index(after: i)
                while i < input.endIndex {
                    let ch = input[i]
                    if ch == "\\" {
                        let next = input.index(after: i)
                        if next < input.endIndex, input[next] == "'" {
                            out.append("'")
                            i = input.index(after: next)
                            continue
                        }
                        out.append(ch)
                        if next < input.endIndex {
                            out.append(input[next])
                            i = input.index(after: next)
                        } else {
                            i = next
                        }
                        continue
                    }
                    if ch == "'" {
                        out.append("\"")
                        i = input.index(after: i)
                        break
                    }
                    if ch == "\"" {
                        out.append("\\\"")
                        i = input.index(after: i)
                        continue
                    }
                    out.append(ch)
                    i = input.index(after: i)
                }
                continue
            }

            out.append(c)
            i = input.index(after: i)
        }
        return (out, count)
    }

    /// Quote bare object keys: `{name:` / `, count:`
    private static func quoteUnquotedKeys(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count + 32)
        var count = 0
        var i = input.startIndex
        var inString = false
        var escape = false

        while i < input.endIndex {
            let c = input[i]
            if inString {
                out.append(c)
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                i = input.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i = input.index(after: i)
                continue
            }

            // After `{` or `,` try unquoted key
            if c == "{" || c == "," {
                out.append(c)
                i = input.index(after: i)
                let wsStart = i
                while i < input.endIndex, input[i].isWhitespace { i = input.index(after: i) }
                out.append(contentsOf: input[wsStart..<i])

                guard i < input.endIndex else { continue }
                if input[i] == "\"" { continue }

                if isIdentStart(input[i]) {
                    let keyStart = i
                    i = input.index(after: i)
                    while i < input.endIndex, isIdentBody(input[i]) {
                        i = input.index(after: i)
                    }
                    let key = String(input[keyStart..<i])
                    let afterKey = i
                    while i < input.endIndex, input[i].isWhitespace { i = input.index(after: i) }
                    if i < input.endIndex, input[i] == ":" {
                        out.append("\"")
                        out.append(contentsOf: key)
                        out.append("\"")
                        out.append(contentsOf: input[afterKey..<i])
                        count += 1
                        continue
                    } else {
                        out.append(contentsOf: input[keyStart..<afterKey])
                        i = afterKey
                        continue
                    }
                }
                continue
            }

            out.append(c)
            i = input.index(after: i)
        }
        return (out, count)
    }

    private static func isIdentStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || c == "$"
    }

    private static func isIdentBody(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }

    private static func removeTrailingCommas(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count)
        var count = 0
        var i = input.startIndex
        var inString = false
        var escape = false

        while i < input.endIndex {
            let c = input[i]
            if inString {
                out.append(c)
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                i = input.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i = input.index(after: i)
                continue
            }

            if c == "," {
                var j = input.index(after: i)
                while j < input.endIndex, input[j].isWhitespace { j = input.index(after: j) }
                if j < input.endIndex, input[j] == "}" || input[j] == "]" {
                    count += 1
                    i = input.index(after: i)
                    continue
                }
            }

            out.append(c)
            i = input.index(after: i)
        }
        return (out, count)
    }

    /// Insert commas between consecutive values, including before bare keys: `{a:1 b:2}` → `{a:1, b:2}`
    private static func insertMissingCommas(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count + 16)
        var count = 0
        var i = input.startIndex
        var inString = false
        var escape = false
        /// Last non-ws token class: open, colon, comma, value
        enum Tok { case open, colon, comma, value }
        var last: Tok?

        while i < input.endIndex {
            let c = input[i]

            if inString {
                out.append(c)
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" {
                    inString = false
                    last = .value
                }
                i = input.index(after: i)
                continue
            }

            if c.isWhitespace {
                out.append(c)
                i = input.index(after: i)
                continue
            }

            if c == "\"" {
                if last == .value {
                    out.append(",")
                    count += 1
                }
                inString = true
                out.append(c)
                last = nil // until close
                i = input.index(after: i)
                continue
            }

            if c == "{" || c == "[" {
                if last == .value {
                    out.append(",")
                    count += 1
                }
                out.append(c)
                last = .open
                i = input.index(after: i)
                continue
            }

            if c == "}" || c == "]" {
                out.append(c)
                last = .value
                i = input.index(after: i)
                continue
            }

            if c == ":" {
                out.append(c)
                last = .colon
                i = input.index(after: i)
                continue
            }

            if c == "," {
                out.append(c)
                last = .comma
                i = input.index(after: i)
                continue
            }

            // Number
            if c == "-" || c.isNumber {
                if last == .value {
                    out.append(",")
                    count += 1
                }
                // consume number
                out.append(c)
                i = input.index(after: i)
                while i < input.endIndex {
                    let ch = input[i]
                    if ch.isNumber || ch == "." || ch == "e" || ch == "E" || ch == "+" || ch == "-" {
                        out.append(ch)
                        i = input.index(after: i)
                    } else { break }
                }
                last = .value
                continue
            }

            // true / false / null
            if c == "t" || c == "f" || c == "n" {
                let lit: String
                switch c {
                case "t": lit = "true"
                case "f": lit = "false"
                default: lit = "null"
                }
                if matchesLiteral(input, from: i, lit) {
                    if last == .value {
                        out.append(",")
                        count += 1
                    }
                    out.append(contentsOf: lit)
                    i = input.index(i, offsetBy: lit.count)
                    last = .value
                    continue
                }
            }

            // Bare identifier — may be unquoted key. If last was value, insert comma.
            if isIdentStart(c) {
                if last == .value {
                    // Lookahead: if this is `ident` then `:`, it's a missing comma before next key
                    if looksLikeBareKey(input, from: i) {
                        out.append(",")
                        count += 1
                        last = .comma
                    } else {
                        // value-like token after value (rare) — still comma
                        out.append(",")
                        count += 1
                    }
                }
                // emit identifier
                out.append(c)
                i = input.index(after: i)
                while i < input.endIndex, isIdentBody(input[i]) {
                    out.append(input[i])
                    i = input.index(after: i)
                }
                // if followed by `:`, this was a key (after open/comma); otherwise treat as value fragment
                var j = i
                while j < input.endIndex, input[j].isWhitespace { j = input.index(after: j) }
                if j < input.endIndex, input[j] == ":" {
                    // key — last stays open/comma-ish until colon handled
                    last = .open // after key name, next is colon — use open-like to avoid comma before :
                } else {
                    last = .value
                }
                continue
            }

            out.append(c)
            i = input.index(after: i)
        }
        return (out, count)
    }

    private static func matchesLiteral(_ input: String, from i: String.Index, _ lit: String) -> Bool {
        var j = i
        for ch in lit {
            guard j < input.endIndex, input[j] == ch else { return false }
            j = input.index(after: j)
        }
        if j < input.endIndex {
            let n = input[j]
            if n.isLetter || n.isNumber || n == "_" { return false }
        }
        return true
    }

    private static func looksLikeBareKey(_ input: String, from i: String.Index) -> Bool {
        var j = i
        guard j < input.endIndex, isIdentStart(input[j]) else { return false }
        j = input.index(after: j)
        while j < input.endIndex, isIdentBody(input[j]) { j = input.index(after: j) }
        while j < input.endIndex, input[j].isWhitespace { j = input.index(after: j) }
        return j < input.endIndex && input[j] == ":"
    }

    private static func escapeControlCharactersInStrings(_ input: String) -> (String, Int) {
        var out = ""
        out.reserveCapacity(input.count)
        var count = 0
        var inString = false
        var escape = false

        for c in input {
            if inString {
                if escape {
                    out.append(c)
                    escape = false
                    continue
                }
                if c == "\\" {
                    out.append(c)
                    escape = true
                    continue
                }
                if c == "\"" {
                    out.append(c)
                    inString = false
                    continue
                }
                if c == "\n" { out.append("\\n"); count += 1; continue }
                if c == "\r" { out.append("\\r"); count += 1; continue }
                if let scalar = c.unicodeScalars.first, scalar.value < 0x20 {
                    out.append(contentsOf: String(format: "\\u%04x", scalar.value))
                    count += 1
                    continue
                }
                out.append(c)
                continue
            }
            if c == "\"" { inString = true }
            out.append(c)
        }
        return (out, count)
    }

    private static func balanceBrackets(_ input: String) -> (String, String) {
        var stack: [Character] = []
        var inString = false
        var escape = false
        for c in input {
            if inString {
                if escape { escape = false; continue }
                if c == "\\" { escape = true; continue }
                if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; continue }
            if c == "{" || c == "[" { stack.append(c) }
            else if c == "}" {
                if stack.last == "{" { stack.removeLast() }
            } else if c == "]" {
                if stack.last == "[" { stack.removeLast() }
            }
        }
        guard !stack.isEmpty else { return (input, "") }
        var suffix = ""
        while let open = stack.popLast() {
            suffix.append(open == "{" ? "}" : "]")
        }
        return (input + suffix, "Appended missing closer(s): \(suffix)")
    }

    private static func trimTrailingNoise(_ input: String) -> String? {
        guard let lastBrace = input.lastIndex(where: { $0 == "}" || $0 == "]" }) else { return nil }
        let prefix = String(input[...lastBrace])
        guard JSONValidator.isValid(prefix) else { return nil }
        let rest = input[input.index(after: lastBrace)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        if rest.hasPrefix(",") || rest.hasPrefix("{") || rest.hasPrefix("[") || rest.hasPrefix("\"") {
            return nil
        }
        return prefix
    }

    private static func looksLikeMultipleRoots(_ input: String) -> Bool {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("}{") || t.contains("][") || t.contains("}\n{")
    }
}
