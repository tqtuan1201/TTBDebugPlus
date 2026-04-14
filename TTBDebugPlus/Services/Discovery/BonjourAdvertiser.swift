//
//  BonjourAdvertiser.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Advertises the macOS debug service via Bonjour for iOS device discovery.
//  Refactored 2026-04-09: multi-interface, thread-safe, TCP keepalive on listener.
//

import Foundation
import Network

// MARK: - Bonjour Advertiser (Multi-Interface, Thread-Safe)

/// Manages one NWListener per active network interface (excluding loopback).
/// All mutations to `listeners` and `ports` run on `queue` to prevent data races.
final class BonjourAdvertiser {

    static let serviceType   = "_ttbdebug._tcp"
    static let serviceDomain = "local"

    // MARK: - Internal State (only accessed on `queue`)

    private var listeners: [String: NWListener] = [:]

    /// Thread-safe snapshot of port assignments. Read from any thread.
    private(set) var ports: [String: UInt16] = [:]

    /// Serial queue serializes ALL mutations to listeners/ports.
    private let queue = DispatchQueue(label: "com.ttbdebug.advertiser", qos: .userInitiated)

    // MARK: - Callbacks (called on main thread)

    var onNewConnection: ((NWConnection) -> Void)?
    var onStateChange:   ((String, NWListener.State) -> Void)?

    // MARK: - Update Interfaces (thread-safe)

    /// Diff the desired interface list against running listeners.
    /// Always dispatched onto the serial `queue`.
    func updateInterfaces(_ interfaces: [NetworkInterface],
                          preferences: InterfacePreferences = .shared) {
        queue.async { [weak self] in
            guard let self else { return }

            let enabledNames = Set(
                interfaces
                    .filter { preferences.isEnabled($0.name) }
                    .map { $0.name }
            )

            // Stop listeners for removed/disabled interfaces
            for name in Array(self.listeners.keys) where !enabledNames.contains(name) {
                self.listeners[name]?.cancel()
                self.listeners.removeValue(forKey: name)
                self.ports.removeValue(forKey: name)
                print("[TTBDebug] ⏹ Listener stopped: \(name)")
            }

            // Start listeners for newly enabled interfaces
            for iface in interfaces
                where enabledNames.contains(iface.name) && self.listeners[iface.name] == nil {
                do {
                    try self.startListenerOnQueue(for: iface)
                } catch {
                    print("[TTBDebug] ❌ Failed to start listener for \(iface.name): \(error)")
                }
            }
        }
    }

    // MARK: - Start Single Listener (must be called on `queue`)

    private func startListenerOnQueue(for interface: NetworkInterface) throws {
        // ── Build NWParameters with TCP keepalive ───────────────────────────
        // TCP keepalive on the LISTENER params is inherited by all accepted
        // connections. This is the ONLY correct place to set it — setting it
        // on individual NWConnection objects after accept is a no-op.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive    = true
        tcpOptions.keepaliveIdle      = 5    // seconds idle before first probe
        tcpOptions.keepaliveInterval  = 3    // seconds between probes
        tcpOptions.keepaliveCount     = 5    // max failed probes → force close (~20s total)
        tcpOptions.connectionTimeout  = 10   // connection establish timeout

        let params = NWParameters(tls: nil, tcp: tcpOptions)

        // Use requiredInterface only when NWPathMonitor provides a proper NWInterface.
        // POSIX-only entries (startup scan) have nil → unrestricted listener (accepts all).
        if let nwIface = interface.nwInterface {
            params.requiredInterface = nwIface
        }
        params.includePeerToPeer = true

        let newListener = try NWListener(using: params, on: .any)

        // Service name must be UNIFORM — iOS SDK browses by type only.
        // Including the interface name suffix broke iOS discovery.
        newListener.service = NWListener.Service(
            name: "TTBDebugPlus",
            type: Self.serviceType,
            domain: Self.serviceDomain
        )

        let ifName = interface.name

        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .ready:
                    if let port = newListener?.port {
                        self.ports[ifName] = port.rawValue
                        print("[TTBDebug] ✅ Bonjour ready on \(ifName) port \(port.rawValue)")
                    }
                case .failed(let error):
                    self.listeners.removeValue(forKey: ifName)
                    self.ports.removeValue(forKey: ifName)
                    print("[TTBDebug] ❌ Listener failed on \(ifName): \(error)")
                case .cancelled:
                    self.ports.removeValue(forKey: ifName)
                    print("[TTBDebug] ⏹ Listener cancelled on \(ifName)")
                case .waiting(let error):
                    print("[TTBDebug] ⏳ Listener waiting on \(ifName): \(error)")
                default:
                    break
                }
                // Notify AFTER ports dict is mutated, still on queue.
                DispatchQueue.main.async {
                    self.onStateChange?(ifName, state)
                }
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            print("[TTBDebug] 📱 New connection via \(ifName): \(connection.endpoint)")
            self.onNewConnection?(connection)
        }

        newListener.start(queue: queue)
        listeners[ifName] = newListener
        print("[TTBDebug] 🔍 Advertising '\(Self.serviceType)' on \(ifName)...")
    }

    // MARK: - Stop All

    func stopAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for (name, listener) in self.listeners {
                listener.cancel()
                print("[TTBDebug] ⏹ Listener stopped: \(name)")
            }
            self.listeners.removeAll()
            self.ports.removeAll()
        }
    }

    // MARK: - Thread-safe port snapshot (for UI)

    /// Returns a stable port snapshot (safe to read from main thread).
    var portSnapshot: [String: UInt16] {
        queue.sync { ports }
    }

    /// True if at least one listener port is assigned.
    var isAdvertising: Bool { queue.sync { !ports.isEmpty } }

    /// All advertising interface names.
    var activeInterfaceNames: [String] { queue.sync { Array(listeners.keys).sorted() } }

    deinit { stopAll() }
}
