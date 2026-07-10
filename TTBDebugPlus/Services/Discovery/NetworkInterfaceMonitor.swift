//
//  NetworkInterfaceMonitor.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-04-09.
//  Monitors active network interfaces via NWPathMonitor and publishes changes.
//  Fixed: POSIX-based immediate scan avoids empty-first-call NWPathMonitor bug.
//  Hardened 2026-07-10: queue-owned state, merge rescan (preserve NWInterface), stopAndWait.
//  Hardened 2026-07-10b: rescanAndWait for wake/reconnect (no race with async publish).
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
    let id: String
    let name: String
    let kind: InterfaceKind
    let ipAddress: String?
    let nwInterface: NWInterface?

    static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        lhs.name == rhs.name
            && lhs.ipAddress == rhs.ipAddress
            && lhs.kind == rhs.kind
            && (lhs.nwInterface != nil) == (rhs.nwInterface != nil)
    }

    init(nwInterface: NWInterface) {
        self.nwInterface = nwInterface
        self.name        = nwInterface.name
        self.id          = nwInterface.name
        self.ipAddress   = NetworkInterface.resolveIP(for: nwInterface.name)

        switch nwInterface.type {
        case .wifi:          self.kind = .wifi
        case .wiredEthernet: self.kind = .ethernet
        case .other:         self.kind = nwInterface.name.hasPrefix("utun") ? .vpn : .other
        default:             self.kind = .other
        }
    }

    init(posixName: String) {
        self.nwInterface = nil
        self.name        = posixName
        self.id          = posixName
        self.ipAddress   = NetworkInterface.resolveIP(for: posixName)

        if posixName.hasPrefix("utun") || posixName.hasPrefix("ipsec") || posixName.hasPrefix("tun") {
            self.kind = .vpn
        } else if posixName.hasPrefix("bridge") || posixName.hasPrefix("bond") || posixName.hasPrefix("eth") {
            self.kind = .ethernet
        } else if posixName.hasPrefix("en") {
            self.kind = .wifi
        } else {
            self.kind = .other
        }
    }

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

    static func posixScanAll() -> [NetworkInterface] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        let excludePrefixes = ["lo", "awdl", "llw"]
        var seen = Set<String>()
        var result: [NetworkInterface] = []

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard !excludePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard seen.insert(name).inserted else { continue }
            guard let ip = NetworkInterface.resolveIP(for: name) else { continue }
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

/// POSIX getifaddrs for immediate first read, then NWPathMonitor for live updates.
/// All mutations run on `queue`; callbacks always fire on main.
final class NetworkInterfaceMonitor {

    private var pathMonitor: NWPathMonitor?
    private var isMonitoring = false
    private let queue = DispatchQueue(label: "com.ttbdebug.ifmonitor", qos: .utility)

    private var _activeInterfaces: [NetworkInterface] = []

    /// Thread-safe snapshot of the latest interface list.
    var activeInterfaces: [NetworkInterface] {
        queue.sync { _activeInterfaces }
    }

    /// Called on main thread whenever the interface list changes.
    var onInterfacesChanged: (([NetworkInterface]) -> Void)?

    // MARK: - Start

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isMonitoring {
                self.rescanOnQueue(forceNotify: true)
                return
            }
            self.isMonitoring = true

            let initial = NetworkInterface.posixScanAll()
            if !initial.isEmpty {
                self._activeInterfaces = initial
                self.publishOnMain(initial)
                print("[TTBDebug] 📡 Initial POSIX scan: \(initial.map { "\($0.name)(\($0.ipAddress ?? "no-ip"))" })")
            }

            let monitor = NWPathMonitor()
            self.pathMonitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                self?.handlePathUpdate(path)
            }
            monitor.start(queue: self.queue)
            print("[TTBDebug] 📡 NetworkInterfaceMonitor started")
        }
    }

    // MARK: - Path Update (on queue)

    private func handlePathUpdate(_ path: NWPath) {
        var seen = Set<String>()
        let nwInterfaces = path.availableInterfaces
            .filter { iface in
                guard iface.type != .loopback else { return false }
                let n = iface.name
                if n.hasPrefix("awdl") || n.hasPrefix("llw") { return false }
                return seen.insert(n).inserted
            }
            .map { NetworkInterface(nwInterface: $0) }
            .filter { iface in
                if let ip = iface.ipAddress, ip.hasPrefix("169.254.") {
                    print("[TTBDebug] 🔕 NWPath: skipping link-local \(iface.name) (\(ip))")
                    return false
                }
                return true
            }
            .filter { iface in
                // Keep WiFi/Ethernet even without IPv4 yet (DHCP race after wake)
                if let ip = iface.ipAddress, !ip.isEmpty { return true }
                return iface.kind == .wifi || iface.kind == .ethernet
            }
            .sorted { $0.name < $1.name }

        // Prefer NWPath list when it has real IPs; otherwise merge with POSIX so we
        // don't wipe interfaces during brief path flaps.
        let resolved: [NetworkInterface]
        if nwInterfaces.isEmpty {
            resolved = NetworkInterface.posixScanAll()
        } else if nwInterfaces.contains(where: { $0.ipAddress != nil }) {
            resolved = nwInterfaces
        } else {
            let posix = NetworkInterface.posixScanAll()
            resolved = mergePreservingNW(existing: nwInterfaces, posix: posix)
        }

        applyIfChanged(resolved, source: "NWPath")
    }

    // MARK: - Manual Rescan

    /// Fresh scan without waiting for NWPathMonitor. Preserves NWInterface handles when possible.
    func rescan() {
        queue.async { [weak self] in
            self?.rescanOnQueue(forceNotify: false)
        }
    }

    /// Synchronous rescan for wake/reconnect recovery. Must NOT be called from `queue`.
    /// Returns the post-rescan interface list and notifies the main-thread callback.
    @discardableResult
    func rescanAndWait() -> [NetworkInterface] {
        queue.sync {
            rescanOnQueue(forceNotify: true)
            return _activeInterfaces
        }
    }

    private func rescanOnQueue(forceNotify: Bool) {
        let fresh = NetworkInterface.posixScanAll()

        if _activeInterfaces.contains(where: { $0.nwInterface != nil }) {
            let merged = mergePreservingNW(existing: _activeInterfaces, posix: fresh)
            applyIfChanged(merged, source: "rescan-merge", force: forceNotify)
        } else {
            applyIfChanged(fresh, source: "rescan", force: forceNotify)
        }
    }

    /// Rebuild list: keep NWInterface when POSIX still sees the name; add new POSIX entries.
    private func mergePreservingNW(existing: [NetworkInterface], posix: [NetworkInterface]) -> [NetworkInterface] {
        let posixNames = Set(posix.map(\.name))
        var merged: [NetworkInterface] = []
        var seen = Set<String>()

        for existing in existing {
            if let nw = existing.nwInterface, posixNames.contains(existing.name) {
                // Re-resolve IP while keeping NWInterface handle
                merged.append(NetworkInterface(nwInterface: nw))
                seen.insert(existing.name)
            } else if let p = posix.first(where: { $0.name == existing.name }) {
                merged.append(p)
                seen.insert(existing.name)
            }
        }

        for p in posix where !seen.contains(p.name) {
            merged.append(p)
        }

        return merged.sorted { $0.name < $1.name }
    }

    // MARK: - Apply + Publish

    private func applyIfChanged(_ resolved: [NetworkInterface], source: String, force: Bool = false) {
        guard force || resolved != _activeInterfaces else { return }
        _activeInterfaces = resolved
        publishOnMain(resolved)
        let desc = resolved.map { "\($0.name)\($0.nwInterface != nil ? "*" : "")" }.joined(separator: ", ")
        print("[TTBDebug] 📡 Interfaces updated (\(source)): \(desc)")
    }

    private func publishOnMain(_ interfaces: [NetworkInterface]) {
        DispatchQueue.main.async { [weak self] in
            self?.onInterfacesChanged?(interfaces)
        }
    }

    // MARK: - Stop

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    /// Synchronous stop for clean server teardown. Must not be called from `queue`.
    func stopAndWait() {
        queue.sync { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        guard isMonitoring else {
            _activeInterfaces = []
            return
        }
        isMonitoring = false
        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        _activeInterfaces = []
        print("[TTBDebug] 📡 NetworkInterfaceMonitor stopped")
    }

    deinit { stop() }
}
