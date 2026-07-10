//
//  BonjourAdvertiser.swift
//  TTBDebugPlus
//
//  Created by TuanTruong on 2026-03-27.
//  Advertises the macOS debug service via Bonjour for iOS device discovery.
//  Refactored 2026-04-09: multi-interface, thread-safe, TCP keepalive on listener.
//  Hardened 2026-07-10: IP/nwInterface fingerprint restart, stop barrier, generation guard.
//

import Foundation
import Network

// MARK: - Bonjour Advertiser (Multi-Interface, Thread-Safe)

/// Manages one NWListener per active network interface (excluding loopback).
/// All mutations to `listeners` / `ports` / fingerprints run on `queue`.
final class BonjourAdvertiser {

    static let serviceType   = "_ttbdebug._tcp"
    static let serviceDomain = "local"

    // MARK: - Fingerprint

    /// Material interface properties that require a listener restart when they change.
    private struct InterfaceFingerprint: Equatable {
        let name: String
        let ipAddress: String?
        let hasNWInterface: Bool
    }

    // MARK: - Internal State (only accessed on `queue`)

    private var listeners: [String: NWListener] = [:]
    private var fingerprints: [String: InterfaceFingerprint] = [:]
    private var ports: [String: UInt16] = [:]

    /// Serial queue serializes ALL mutations to listeners/ports/fingerprints.
    private let queue = DispatchQueue(label: "com.ttbdebug.advertiser", qos: .utility)

    /// Bumped on every full stop so late state callbacks from cancelled listeners are ignored.
    private var generation: UInt64 = 0

    // MARK: - Callbacks (invoked on main thread)

    var onNewConnection: ((NWConnection) -> Void)?
    var onStateChange:   ((String, NWListener.State) -> Void)?

    // MARK: - Update Interfaces (thread-safe)

    /// Diff the desired interface list against running listeners.
    /// Restarts a listener when its fingerprint changes (IP drift or POSIX→NWInterface upgrade).
    func updateInterfaces(_ interfaces: [NetworkInterface],
                          preferences: InterfacePreferences = .shared) {
        queue.async { [weak self] in
            self?.applyInterfacesOnQueue(interfaces, preferences: preferences)
        }
    }

    private func applyInterfacesOnQueue(_ interfaces: [NetworkInterface],
                                        preferences: InterfacePreferences) {
        let desired: [(NetworkInterface, InterfaceFingerprint)] = interfaces
            .filter { preferences.isEnabled($0.name) }
            .map { iface in
                (
                    iface,
                    InterfaceFingerprint(
                        name: iface.name,
                        ipAddress: iface.ipAddress,
                        hasNWInterface: iface.nwInterface != nil
                    )
                )
            }

        let enabledNames = Set(desired.map { $0.1.name })

        for name in Array(listeners.keys) where !enabledNames.contains(name) {
            cancelListener(named: name, reason: "removed/disabled")
        }

        for (iface, fp) in desired {
            if let existing = fingerprints[iface.name], existing == fp,
               listeners[iface.name] != nil {
                continue
            }

            if listeners[iface.name] != nil {
                cancelListener(named: iface.name, reason: "fingerprint changed")
            }

            do {
                try startListenerOnQueue(for: iface, fingerprint: fp)
            } catch {
                print("[TTBDebug] ❌ Failed to start listener for \(iface.name): \(error)")
            }
        }
    }

    // MARK: - Start Single Listener (must be called on `queue`)

    private func startListenerOnQueue(for interface: NetworkInterface,
                                      fingerprint: InterfaceFingerprint) throws {
        // TCP keepalive on LISTENER params is inherited by accepted connections.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive    = true
        tcpOptions.keepaliveIdle      = 5
        tcpOptions.keepaliveInterval  = 3
        tcpOptions.keepaliveCount     = 5
        tcpOptions.connectionTimeout  = 10

        let params = NWParameters(tls: nil, tcp: tcpOptions)

        // Prefer interface-bound listeners when NWPathMonitor provides NWInterface.
        // POSIX-only entries have nil → unrestricted; fingerprint restart upgrades later.
        if let nwIface = interface.nwInterface {
            params.requiredInterface = nwIface
        }
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: params, on: .any)

        // Uniform service name — iOS SDK browses by type only.
        newListener.service = NWListener.Service(
            name: "TTBDebugPlus",
            type: Self.serviceType,
            domain: Self.serviceDomain
        )

        let ifName = interface.name
        let startGeneration = generation

        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self else { return }
            self.queue.async {
                guard self.generation == startGeneration else { return }

                // Ignore callbacks from a replaced listener instance
                if let current = self.listeners[ifName], current !== newListener {
                    return
                }

                switch state {
                case .ready:
                    if let port = newListener?.port {
                        self.ports[ifName] = port.rawValue
                        let bound = fingerprint.hasNWInterface ? "bound" : "unrestricted"
                        print("[TTBDebug] ✅ Bonjour ready on \(ifName) port \(port.rawValue) (\(bound))")
                    }
                case .failed(let error):
                    if self.listeners[ifName] === newListener {
                        self.listeners.removeValue(forKey: ifName)
                        self.fingerprints.removeValue(forKey: ifName)
                    }
                    self.ports.removeValue(forKey: ifName)
                    print("[TTBDebug] ❌ Listener failed on \(ifName): \(error)")
                case .cancelled:
                    if self.listeners[ifName] === newListener {
                        self.listeners.removeValue(forKey: ifName)
                        self.fingerprints.removeValue(forKey: ifName)
                        self.ports.removeValue(forKey: ifName)
                    } else if self.listeners[ifName] == nil {
                        self.ports.removeValue(forKey: ifName)
                    }
                    print("[TTBDebug] ⏹ Listener cancelled on \(ifName)")
                case .waiting(let error):
                    print("[TTBDebug] ⏳ Listener waiting on \(ifName): \(error)")
                default:
                    break
                }

                DispatchQueue.main.async {
                    self.onStateChange?(ifName, state)
                }
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            guard self.listeners[ifName] != nil else {
                connection.cancel()
                return
            }
            print("[TTBDebug] 📱 New connection via \(ifName): \(connection.endpoint)")
            self.onNewConnection?(connection)
        }

        newListener.start(queue: queue)
        listeners[ifName] = newListener
        fingerprints[ifName] = fingerprint
        let bound = fingerprint.hasNWInterface ? "bound" : "unrestricted"
        print("[TTBDebug] 🔍 Advertising '\(Self.serviceType)' on \(ifName) [\(bound)]...")
    }

    // MARK: - Cancel single (on queue)

    private func cancelListener(named name: String, reason: String) {
        if let listener = listeners.removeValue(forKey: name) {
            listener.cancel()
            print("[TTBDebug] ⏹ Listener stopped: \(name) — \(reason)")
        }
        fingerprints.removeValue(forKey: name)
        ports.removeValue(forKey: name)
    }

    // MARK: - Stop All

    /// Async stop — safe from any thread. Prefer `stopAllAndWait` when restarting.
    func stopAll() {
        queue.async { [weak self] in
            self?.stopAllOnQueue()
        }
    }

    /// Synchronously stops all listeners. Use before restart to avoid overlapping NWListeners.
    /// Must NOT be called from the advertiser queue (would deadlock).
    func stopAllAndWait() {
        queue.sync { [weak self] in
            self?.stopAllOnQueue()
        }
    }

    private func stopAllOnQueue() {
        generation &+= 1
        for (name, listener) in listeners {
            listener.cancel()
            print("[TTBDebug] ⏹ Listener stopped: \(name)")
        }
        listeners.removeAll()
        fingerprints.removeAll()
        ports.removeAll()
    }

    // MARK: - Thread-safe snapshots

    var portSnapshot: [String: UInt16] {
        queue.sync { ports }
    }

    var isAdvertising: Bool { queue.sync { !ports.isEmpty } }

    var activeInterfaceNames: [String] { queue.sync { Array(listeners.keys).sorted() } }

    deinit { stopAll() }
}
