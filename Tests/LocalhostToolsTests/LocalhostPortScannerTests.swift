//
//  LocalhostPortScannerTests.swift
//  LocalhostToolsTests
//

import XCTest
@testable import LocalhostTools

final class LocalhostPortScannerTests: XCTestCase {

    // MARK: - Address / port parse

    func testParseIPv4Listen() {
        let result = LocalhostPortScanner.parseAddressPort(from: "127.0.0.1:5173 (LISTEN)")
        XCTAssertEqual(result?.0, "127.0.0.1")
        XCTAssertEqual(result?.1, 5173)
    }

    func testParseIPv6Listen() {
        let result = LocalhostPortScanner.parseAddressPort(from: "[::1]:8080 (LISTEN)")
        XCTAssertEqual(result?.0, "[::1]")
        XCTAssertEqual(result?.1, 8080)
    }

    func testParseWildcard() {
        let result = LocalhostPortScanner.parseAddressPort(from: "*:3000 (LISTEN)")
        XCTAssertEqual(result?.0, "*")
        XCTAssertEqual(result?.1, 3000)
    }

    // MARK: - Command name decode

    func testDecodeLsofSpaceEscape() {
        let decoded = LocalhostPortScanner.decodeLsofCommandName(#"Code\x20Helper\x20(Plugin)"#)
        XCTAssertEqual(decoded, "Code Helper (Plugin)")
    }

    func testDecodeLsofPlainName() {
        XCTAssertEqual(LocalhostPortScanner.decodeLsofCommandName("ControlCenter"), "ControlCenter")
    }

    // MARK: - Full lsof sample

    func testParseSampleLsofWithFullNames() {
        let sample = """
        COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node      12345 me    23u  IPv4 0x1      0t0  TCP 127.0.0.1:3000 (LISTEN)
        ControlCenter 666 me  10u  IPv4 0x2      0t0  TCP *:5000 (LISTEN)
        ControlCenter 666 me  11u  IPv6 0x3      0t0  TCP *:5000 (LISTEN)
        Code\\x20Helper\\x20(Plugin) 44672 me 12u IPv4 0x4 0t0 TCP 127.0.0.1:20059 (LISTEN)
        """

        let endpoints = LocalhostPortScanner.parseLsofOutput(
            sample,
            protectedPIDs: [],
            protectedPorts: []
        )

        // Dedupe: ControlCenter v4+v6 → 1 row
        XCTAssertEqual(endpoints.count, 3)

        let node = endpoints.first { $0.port == 3000 }
        XCTAssertEqual(node?.processName, "node")
        XCTAssertEqual(node?.classification, .user)
        XCTAssertEqual(node?.pid, 12345)

        let control = endpoints.first { $0.port == 5000 }
        XCTAssertEqual(control?.processName, "ControlCenter")
        XCTAssertEqual(control?.classification, .system)
        // After dedupe, IPv4+IPv6 both bind * → single address entry
        XCTAssertEqual(Set(control?.addresses ?? []), ["*"])
        XCTAssertEqual(control?.id, "666:5000")

        let code = endpoints.first { $0.port == 20059 }
        XCTAssertEqual(code?.processName, "Code Helper (Plugin)")
        XCTAssertEqual(code?.classification, .user)
    }

    func testDedupeMergesDistinctAddresses() {
        let sample = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        nginx 99 me 1u IPv4 x 0t0 TCP 127.0.0.1:80 (LISTEN)
        nginx 99 me 2u IPv6 y 0t0 TCP [::1]:80 (LISTEN)
        """
        let endpoints = LocalhostPortScanner.parseLsofOutput(sample)
        XCTAssertEqual(endpoints.count, 1)
        XCTAssertEqual(endpoints[0].port, 80)
        XCTAssertEqual(Set(endpoints[0].addresses), ["127.0.0.1", "[::1]"])
        XCTAssertEqual(endpoints[0].preferredOpenHost, "127.0.0.1")
    }

    func testProtectedPortClassifiedAsTTB() {
        let sample = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        node 10 me 1u IPv4 x 0t0 TCP *:9911 (LISTEN)
        """
        let endpoints = LocalhostPortScanner.parseLsofOutput(
            sample,
            protectedPIDs: [],
            protectedPorts: [9911]
        )
        XCTAssertEqual(endpoints.first?.classification, .ttbdebug)
    }

    func testOccupantFindsPort() {
        let sample = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        vite 1 me 1u IPv4 x 0t0 TCP *:5173 (LISTEN)
        """
        let endpoints = LocalhostPortScanner.parseLsofOutput(sample)
        let occ = LocalhostPortScanner.occupant(of: 5173, in: endpoints)
        XCTAssertEqual(occ?.processName, "vite")
        XCTAssertNil(LocalhostPortScanner.occupant(of: 9999, in: endpoints))
    }
}
