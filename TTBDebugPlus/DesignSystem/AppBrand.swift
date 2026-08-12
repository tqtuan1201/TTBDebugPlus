//
//  AppBrand.swift
//  TTBDebugPlus
//
//  Canonical product name + professional tagline used in chrome, sidebar, and menus.
//

import Foundation

enum AppBrand {
    static let name = "DebugKit"

    /// Short professional tagline (window subtitle / sidebar).
    static let tagline = "Explore. Diagnose. Debug."

    /// One-line value proposition for empty states / welcome.
    static let valueProposition =
        "Inspect console logs, network traffic, and device sessions from your Mac — over the local network."

    /// Compact version line, e.g. "v1.0.0"
    static var versionLabel: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "v\(v)"
    }
}
