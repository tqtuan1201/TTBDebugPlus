//
//  PerformanceViewModel.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Tracks real-time performance metrics from connected iOS devices
//

import SwiftUI

// MARK: - Performance ViewModel
@Observable
final class PerformanceViewModel {
    
    // MARK: - State
    var cpuHistory: [PerformanceDataPoint] = []
    var memoryHistory: [PerformanceDataPoint] = []
    var networkSentHistory: [PerformanceDataPoint] = []
    var networkRecvHistory: [PerformanceDataPoint] = []
    
    var currentCPU: Double = 0
    var currentMemory: Double = 0
    var totalMemory: Double = 0
    var currentFPS: Double? = nil
    var diskUsed: Double? = nil
    
    // Alerts
    var cpuAlert: Bool { currentCPU > 80 }
    var memoryAlert: Bool { totalMemory > 0 && (currentMemory / totalMemory) > 0.9 }
    
    // API analytics
    var averageResponseTime: Double = 0
    var slowRequestCount: Int = 0
    var duplicateRequestCount: Int = 0
    var errorRate: Double = 0
    var slowAPIThreshold: Double = 1000 // ms
    
    private let maxDataPoints = 60 // 5 minutes at 5s intervals
    private var lastMetricsTimestamp: TimeInterval?
    private var lastAnalysisSignature: String?
    
    // MARK: - Sync from ConnectionManager
    func syncMetrics(from connectionManager: ConnectionManager) {
        guard let perf = connectionManager.selectedDevice?.latestPerformance else { return }
        guard lastMetricsTimestamp != perf.timestamp else { return }
        lastMetricsTimestamp = perf.timestamp
        
        let time = Date(timeIntervalSince1970: perf.timestamp / 1000)
        
        currentCPU = perf.cpuUsage
        currentMemory = perf.memoryUsedMB
        totalMemory = perf.memoryTotalMB
        currentFPS = perf.fps
        diskUsed = perf.diskUsedMB
        
        // Append to history
        appendDataPoint(to: &cpuHistory, value: perf.cpuUsage, time: time)
        appendDataPoint(to: &memoryHistory, value: perf.memoryUsedMB, time: time)
        
        if let sent = perf.networkBytesSent {
            appendDataPoint(to: &networkSentHistory, value: Double(sent) / 1024, time: time) // KB
        }
        if let recv = perf.networkBytesReceived {
            appendDataPoint(to: &networkRecvHistory, value: Double(recv) / 1024, time: time) // KB
        }
    }
    
    // MARK: - Analyze API logs
    func analyzeAPIs(from entries: [APILogPayload]) {
        guard !entries.isEmpty else {
            resetAPIAnalytics()
            return
        }
        let signature = "\(entries.count):\(entries.first?.id ?? ""):\(entries.last?.id ?? "")"
        guard signature != lastAnalysisSignature else { return }
        lastAnalysisSignature = signature
        
        var totalDuration: Double = 0
        var slowRequests = 0
        var errors = 0
        var seen: [String: TimeInterval] = [:]
        var dupes = 0

        for entry in entries {
            totalDuration += entry.durationMs
            if entry.durationMs > slowAPIThreshold { slowRequests += 1 }
            if entry.statusCode >= 400 { errors += 1 }

            let key = "\(entry.method):\(entry.url)"
            if let last = seen[key], abs(entry.timestamp - last) < 1000 {
                dupes += 1
            }
            seen[key] = entry.timestamp
        }

        averageResponseTime = totalDuration / Double(entries.count)
        slowRequestCount = slowRequests
        errorRate = Double(errors) / Double(entries.count) * 100
        duplicateRequestCount = dupes
    }

    func resetMetrics() {
        cpuHistory.removeAll()
        memoryHistory.removeAll()
        networkSentHistory.removeAll()
        networkRecvHistory.removeAll()
        currentCPU = 0
        currentMemory = 0
        totalMemory = 0
        currentFPS = nil
        diskUsed = nil
        lastMetricsTimestamp = nil
    }

    private func resetAPIAnalytics() {
        averageResponseTime = 0
        slowRequestCount = 0
        duplicateRequestCount = 0
        errorRate = 0
        lastAnalysisSignature = nil
    }
    
    
    // MARK: - Private
    private func appendDataPoint(to array: inout [PerformanceDataPoint], value: Double, time: Date) {
        array.append(PerformanceDataPoint(value: value, timestamp: time))
        if array.count > maxDataPoints {
            array.removeFirst(array.count - maxDataPoints)
        }
    }
}

// MARK: - Data Point
struct PerformanceDataPoint: Identifiable {
    let id = UUID()
    let value: Double
    let timestamp: Date
    
    var formattedTime: String {
        TTDateFormatter.timeShort.string(from: timestamp)
    }
}
