//
//  DateFormatters.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-29.
//  Cached date formatters — avoids per-row allocation in hot rendering paths
//

import Foundation

// MARK: - Cached Date Formatters
enum TTDateFormatter {
    /// HH:mm:ss.SSS — used in console log rows, network timestamps
    static let timeWithMillis: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    /// yyyy-MM-dd HH:mm — used in session listings
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
    
    /// HH:mm:ss — short time format
    static let timeShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    /// yyyy-MM-dd HH:mm:ss — full datetime for exports
    static let dateTimeFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    
    /// ISO8601 — for file naming (cached)
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    /// Relative time ("3 minutes ago") — used in library timestamps (cached)
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Convenience for a relative string from a date to now.
    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
