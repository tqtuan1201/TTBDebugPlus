//
//  JSONEditorModels.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Models for the JSON Editor feature
//

import SwiftUI



// MARK: - JSON Value Type (for tree badges)
enum JSONValueType {
    case object(keyCount: Int)
    case array(itemCount: Int)
    case string
    case number
    case boolean(Bool)
    case null
    
    var badge: String {
        switch self {
        case .object: return "{}"
        case .array: return "[]"
        case .string: return "Str"
        case .number: return "123"
        case .boolean(let v): return v ? "T" : "F"
        case .null: return "∅"
        }
    }
    
    var badgeColor: Color {
        switch self {
        case .object: return .ttJsonBrace
        case .array: return .ttJsonBrace
        case .string: return .ttJsonString
        case .number: return .ttJsonNumber
        case .boolean: return .ttJsonBool
        case .null: return .ttJsonNull
        }
    }
    
    var label: String {
        switch self {
        case .object(let count): return "Object (\(count) key\(count == 1 ? "" : "s"))"
        case .array(let count): return "Array (\(count) item\(count == 1 ? "" : "s"))"
        case .string: return "String"
        case .number: return "Number"
        case .boolean(let v): return "Bool (\(v))"
        case .null: return "Null"
        }
    }
}



// MARK: - JSON Sub-Tools (nested within JSON category)
enum JSONTool: String, CaseIterable, Identifiable {
    case editor = "JSON Editor"
    case query = "Query"
    case diff = "Diff"
    case convert = "Convert"
    case graph = "Graph"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .editor: return "curlybraces"
        case .query: return "magnifyingglass"
        case .diff: return "rectangle.on.rectangle"
        case .convert: return "arrow.triangle.swap"
        case .graph: return "point.3.connected.trianglepath.dotted"
        }
    }
    
    var description: String {
        switch self {
        case .editor: return "Dual-panel JSON editor"
        case .query: return "JSONPath queries"
        case .diff: return "Compare two JSONs"
        case .convert: return "JSON ↔ YAML/XML/CSV"
        case .graph: return "Visual graph view"
        }
    }
}

// MARK: - Dev Tools Category
enum DevTool: String, CaseIterable, Identifiable {
    case json = "JSON"
    case qrCode = "QR Code"
    case caseConverter = "Case Converter"
    case base64 = "Base64"
    case urlEncode = "URL Encode"
    case hashGenerator = "Hash"
    case timestamp = "Timestamp"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .json: return "curlybraces"
        case .qrCode: return "qrcode"
        case .caseConverter: return "textformat.abc"
        case .base64: return "textformat.abc"
        case .urlEncode: return "link"
        case .hashGenerator: return "number"
        case .timestamp: return "clock"
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .json, .qrCode, .caseConverter: return true
        default: return false
        }
    }
    
    var menuTitle: String {
        switch self {
        case .json: return "View JSON"
        case .qrCode: return "QR Code"
        case .caseConverter: return "Case Converter"
        default: return rawValue
        }
    }
    
    var menuDescription: String {
        switch self {
        case .json:
            return "Editor, query, diff, convert, and graph tools for JSON payloads."
        case .qrCode:
            return "Generate, preview, export, and decode QR codes."
        case .caseConverter:
            return "Convert text input between title, sentence, upper, lower, alternate, and toggle cases."
        case .base64:
            return "Encode and decode Base64 text."
        case .urlEncode:
            return "Encode and decode URL-safe strings."
        case .hashGenerator:
            return "Generate hashes for copied payloads."
        case .timestamp:
            return "Convert timestamps and inspect date formats."
        }
    }
    
    var statusText: String {
        isAvailable ? "Available" : "Coming Soon"
    }
}

// MARK: - Validation Error
struct JSONValidationError: Identifiable {
    let id = UUID()
    let line: Int
    let column: Int
    let message: String
    let severity: Severity
    
    enum Severity {
        case error, warning
        
        var color: Color {
            switch self {
            case .error: return .ttError
            case .warning: return .ttWarning
            }
        }
        
        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }
}

// MARK: - Editor Payload (from external views)
struct JSONEditorPayload: Equatable {
    let json: String
    let sourceLabel: String
    
    static func == (lhs: JSONEditorPayload, rhs: JSONEditorPayload) -> Bool {
        lhs.json == rhs.json && lhs.sourceLabel == rhs.sourceLabel
    }
}

// MARK: - Diff Result
enum DiffNodeType {
    case unchanged
    case added
    case removed
    case changed(old: String, new: String)
    
    var color: Color {
        switch self {
        case .unchanged: return .ttTextPrimary
        case .added: return .ttSuccess
        case .removed: return .ttError
        case .changed: return .ttWarning
        }
    }
    
    var icon: String {
        switch self {
        case .unchanged: return "equal"
        case .added: return "plus.circle"
        case .removed: return "minus.circle"
        case .changed: return "arrow.triangle.2.circlepath"
        }
    }
}

struct DiffNode: Identifiable {
    let id = UUID()
    let path: String
    let key: String
    let type: DiffNodeType
    let indent: Int
    let leftValue: String?
    let rightValue: String?
}

// MARK: - Convert Format
enum ConvertFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case yaml = "YAML"
    case xml = "XML"
    case csv = "CSV"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .json: return "curlybraces"
        case .yaml: return "doc.plaintext"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        case .csv: return "tablecells"
        }
    }
    
    var fileExtension: String { rawValue.lowercased() }
}
