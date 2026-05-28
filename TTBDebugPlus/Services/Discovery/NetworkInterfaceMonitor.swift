//
//  NetworkInterfaceMonitor.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-09.
//  Monitors active network interfaces via NWPathMonitor and publishes changes.
//  Fixed: POSIX-based immediate scan avoids empty-first-call NWPathMonitor bug.
//

import Foundation
import Network

// MARK: - Interface Kind

enum InterfaceKind: String, CaseIterable {
    case wifi      = "WiFi"
    case ethernet  = "Ethernet"
    case vpn       = "VPN"
    case other     = "Other"

    var icon: String {
        switch self {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn:      return "lock.shield"
        case .other:    return "network"
        }
    }

    var badgeColor: String {
        switch self {
        case .wifi:     return "#22C55E"
        case .ethernet: return "#3B82F6"
        case .vpn:      return "#A855F7"
        case .other:    return "#64748B"
        }
    }
}

// MARK: - Network Interface Model

struct NetworkInterface: Identifiable, Equatable {
    let id: String            // interface name e.g. "en0"
    let name: String
    let kind: InterfaceKind
    let ipAddress: String?
    let nwInterface: NWInterface? // Optional — nil for POSIX-only entries

    static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        lhs.name == rhs.name && lhs.ipAddress == rhs.ipAddress && lhs.kind == rhs.kind
    }

    // MARK: Init from NWInterface (used by NWPathMonitor)
    init(nwInterface: NWInterface) {
        self.nwInterface = nwInterface
        self.name        = nwInterface.name
        self.id          = nwInterface.name
        self.ipAddress   = NetworkInterface.resolveIP(for: nwInterface.name)

        switch nwInterface.type {
        case .wifi:         self.kind = .wifi
        case .wiredEthernet:self.kind = .ethernet
        case .other:        self.kind = nwInterface.name.hasPrefix("utun") ? .vpn : .other
        default:            self.kind = .other
        }
    }

    // MARK: Init from POSIX name (used for immediate scan at startup)
    init(posixName: String) {
        self.nwInterface = nil
        self.name        = posixName
        self.id          = posixName
        self.ipAddress   = NetworkInterface.resolveIP(for: posixName)

        // Classify by macOS interface naming conventions:
        // - utun*, ipsec*, tun* → VPN / tunnel
        // - bridge*, bond* → virtual/ethernet aggregate
        // - en* → could be Wi-Fi OR Ethernet; we label as .wifi for common
        //         MacBook setup; NWPathMonitor will correct this when it fires.
        // - llw*, awdl* → Apple Wireless Direct Link — skip (filtered upstream)
        if posixName.hasPrefix("utun") || posixName.hasPrefix("ipsec") || posixName.hasPrefix("tun") {
            self.kind = .vpn
        } else if posixName.hasPrefix("bridge") || posixName.hasPrefix("bond") || posixName.hasPrefix("eth") {
            self.kind = .ethernet
        } else if posixName.hasPrefix("en") {
            // en0 on MacBook = Wi-Fi, en0 on Mac Studio/iMac = Ethernet.
            // NWPathMonitor will correct this; mark as .wifi initially.
            self.kind = .wifi
        } else {
            self.kind = .other
        }
    }

    // MARK: Resolve IPv4 via POSIX getifaddrs
    static func resolveIP(for interfaceName: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == interfaceName,
                  ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr,
                        socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                        &buf, socklen_t(buf.count),
                        nil, 0, NI_NUMERICHOST)
            return String(cString: buf)
        }
        return nil
    }

    // MARK: Immediate POSIX scan (no NWInterface, purely from getifaddrs)
    static func posixScanAll() -> [NetworkInterface] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        // Skip loopback + Apple-internal wireless (AWDL/LLW)
        // VPN tunnels (utun*) are included — users may want to toggle them
        let excludePrefixes = ["lo", "awdl", "llw"]

        var seen  = Set<String>()
        var result: [NetworkInterface] = []

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)

            guard !excludePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard seen.insert(name).inserted else { continue }

            // Resolve IP first so we can check for link-local
            guard let ip = NetworkInterface.resolveIP(for: name) else { continue }

            // Skip link-local (169.254.x.x) — APIPA/self-assigned, not routable
            // These cause spurious Bonjour advertisements that confuse iOS mDNS
            guard !ip.hasPrefix("169.254.") else {
                print("[TTBDebug] 🔕 Skipping link-local interface \(name) (\(ip))")
                continue
            }

            result.append(NetworkInterface(posixName: name))
        }

        return result.sorted { $0.name < $1.name }
    }
}

// MARK: - Network Interface Monitor

/// Uses POSIX getifaddrs for an immediate first read, then NWPathMonitor for live change events.
final class NetworkInterfaceMonitor {

    private var pathMonitor: NWPathMonitor?
    private var isMonitoring = false
    private let queue = DispatchQueue(label: "com.ttbdebug.ifmonitor", qos: .utility)

    private(set) var activeInterfaces: [NetworkInterface] = []

    /// Called on main thread whenever the interface list changes.
    var onInterfacesChanged: (([NetworkInterface]) -> Void)?

    // MARK: - Start

    func start() {
        guard !isMonitoring else {
            rescan()
            return
        }
        isMonitoring = true

        // ── Step 1: Immediate POSIX scan so UI is never "No interfaces detected" ──
        let initial = NetworkInterface.posixScanAll()
        if !initial.isEmpty {
            activeInterfaces = initial
            DispatchQueue.main.async { [weak self] in
                self?.onInterfacesChanged?(initial)
            }
            print("[TTBDebug] 📡 Initial POSIX scan: \(initial.map { "\($0.name)(\($0.ipAddress ?? "no-ip"))" })")
        }

        // ── Step 2: NWPathMonitor for live updates & accurate NWInterface objects ──
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            var seen = Set<String>()
            let nwInterfaces = path.availableInterfaces
                .filter { iface in
                    guard iface.type != .loopback else { return false }
                    guard seen.insert(iface.name).inserted else { return false }
                    return true
                }
                .map { NetworkInterface(nwInterface: $0) }
                // Also filter link-local IPs here (NWPathMonitor can return them too)
                .filter { iface in
                    if let ip = iface.ipAddress, ip.hasPrefix("169.254.") {
                        print("[TTBDebug] 🔕 NWPath: skipping link-local \(iface.name) (\(ip))")
                        return false
                    }
                    return true
                }
                .sorted { $0.name < $1.name }

            // If NWPathMonitor returns empty (known first-call bug), fallback to POSIX
            let resolved = nwInterfaces.isEmpty
                ? NetworkInterface.posixScanAll()
                : nwInterfaces

            guard resolved != self.activeInterfaces else { return }
            self.activeInterfaces = resolved

            DispatchQueue.main.async {
                self.onInterfacesChanged?(resolved)
            }
            print("[TTBDebug] 📡 Interfaces updated: \(resolved.map { $0.name }.joined(separator: ", "))")
        }
        monitor.start(queue: queue)
        print("[TTBDebug] 📡 NetworkInterfaceMonitor started")
    }

    // MARK: - Manual Rescan

    /// Triggers a fresh POSIX scan and notifies. Useful for "Refresh" button.
    func rescan() {
        let fresh = NetworkInterface.posixScanAll()
        guard fresh != activeInterfaces else { return }
        activeInterfaces = fresh
        DispatchQueue.main.async { [weak self] in
            self?.onInterfacesChanged?(fresh)
        }
        print("[TTBDebug] 📡 Manual rescan: \(fresh.map { $0.name })")
    }

    // MARK: - Stop

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        print("[TTBDebug] 📡 NetworkInterfaceMonitor stopped")
    }

    deinit { stop() }
}
