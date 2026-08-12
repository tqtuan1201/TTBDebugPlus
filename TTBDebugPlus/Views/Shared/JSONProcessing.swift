//
//  JSONProcessing.swift
//  DebugKit
//
//  Created by TuanTruong on 2026-03-29.
//  cURL/Postman export generation from API log payloads
//

import Foundation

// MARK: - cURL Generator
enum CURLGenerator {
    /// Generate a cURL command from an API log payload
    static func generate(from log: APILogPayload) -> String {
        var parts: [String] = ["curl"]
        
        // Method
        if log.method.uppercased() != "GET" {
            parts.append("-X \(log.method.uppercased())")
        }
        
        // URL
        parts.append("'\(log.url)'")
        
        // Headers
        for (key, value) in log.requestHeaders {
            parts.append("-H '\(key): \(value)'")
        }
        
        // Body
        if !log.requestBody.isEmpty {
            let escaped = log.requestBody.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escaped)'")
        }
        
        return parts.joined(separator: " \\\n  ")
    }
    
    /// Generate Postman collection JSON from API logs
    static func generatePostmanCollection(from logs: [APILogPayload], name: String = "DebugKit Export") -> String {
        var items: [[String: Any]] = []
        
        for log in logs {
            var headers: [[String: String]] = []
            for (key, value) in log.requestHeaders {
                headers.append(["key": key, "value": value, "type": "text"])
            }
            
            let urlComponents = URLComponents(string: log.url)
            var queryParams: [[String: String]] = []
            for item in urlComponents?.queryItems ?? [] {
                queryParams.append(["key": item.name, "value": item.value ?? ""])
            }
            
            var request: [String: Any] = [
                "method": log.method.uppercased(),
                "header": headers,
                "url": [
                    "raw": log.url,
                    "protocol": urlComponents?.scheme ?? "https",
                    "host": (urlComponents?.host ?? "").components(separatedBy: "."),
                    "path": (urlComponents?.path ?? "").components(separatedBy: "/").filter { !$0.isEmpty },
                    "query": queryParams
                ] as [String: Any]
            ]
            
            if !log.requestBody.isEmpty {
                request["body"] = [
                    "mode": "raw",
                    "raw": log.requestBody,
                    "options": ["raw": ["language": "json"]]
                ] as [String: Any]
            }
            
            let urlPath = urlComponents?.path ?? log.url
            items.append([
                "name": "\(log.method.uppercased()) \(urlPath)",
                "request": request,
                "response": []
            ] as [String: Any])
        }
        
        let collection: [String: Any] = [
            "info": [
                "_postman_id": UUID().uuidString,
                "name": name,
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
                "description": "Exported from DebugKit"
            ] as [String: Any],
            "item": items
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: collection, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
