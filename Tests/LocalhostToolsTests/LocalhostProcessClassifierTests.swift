//
//  LocalhostProcessClassifierTests.swift
//  LocalhostToolsTests
//

import XCTest
@testable import LocalhostTools

final class LocalhostProcessClassifierTests: XCTestCase {

    func testControlCenterFullNameIsSystem() {
        let c = LocalhostProcessClassifier.classify(
            processName: "ControlCenter",
            pid: 666,
            port: 5000,
            protectedPIDs: [],
            protectedPorts: []
        )
        XCTAssertEqual(c, .system)
        XCTAssertFalse(LocalhostProcessClassifier.canSoftStop(c))
        XCTAssertFalse(LocalhostProcessClassifier.canForceKill(c))
    }

    func testControlCenterTruncatedNameIsSystem() {
        // Legacy lsof without +c 0 produces "ControlCe"
        let c = LocalhostProcessClassifier.classify(
            processName: "ControlCe",
            pid: 666,
            port: 5000,
            protectedPIDs: [],
            protectedPorts: []
        )
        XCTAssertEqual(c, .system)
        XCTAssertTrue(LocalhostProcessClassifier.isSystemProcessName("ControlCe"))
    }

    func testRapportdIsSystem() {
        let c = LocalhostProcessClassifier.classify(
            processName: "rapportd",
            pid: 662,
            port: 54542,
            protectedPIDs: [],
            protectedPorts: []
        )
        XCTAssertEqual(c, .system)
    }

    func testNodeIsUser() {
        let c = LocalhostProcessClassifier.classify(
            processName: "node",
            pid: 100,
            port: 3000,
            protectedPIDs: [],
            protectedPorts: []
        )
        XCTAssertEqual(c, .user)
        XCTAssertTrue(LocalhostProcessClassifier.canSoftStop(c))
        XCTAssertTrue(LocalhostProcessClassifier.canForceKill(c))
    }

    func testDockerProxy() {
        let c = LocalhostProcessClassifier.classify(
            processName: "com.docker.backend",
            pid: 200,
            port: 8080,
            protectedPIDs: [],
            protectedPorts: []
        )
        XCTAssertEqual(c, .docker)
    }

    func testProtectedPID() {
        let c = LocalhostProcessClassifier.classify(
            processName: "TTBDebugPlus",
            pid: 42,
            port: 1234,
            protectedPIDs: [42],
            protectedPorts: []
        )
        XCTAssertEqual(c, .ttbdebug)
        XCTAssertFalse(LocalhostProcessClassifier.canForceKill(c))
    }

    func testShortPrefixDoesNotFalsePositive() {
        // "User" is too short to match via truncation prefix rules.
        XCTAssertFalse(LocalhostProcessClassifier.isSystemProcessName("User"))
        XCTAssertFalse(LocalhostProcessClassifier.isSystemProcessName("Cont"))
    }

    func testAppleBundlePrefix() {
        let c = LocalhostProcessClassifier.classify(
            processName: "com.apple.WebKit.Networking",
            pid: 1,
            port: 9_000,
            protectedPIDs: [],
            protectedPorts: []
        )
        XCTAssertEqual(c, .system)
    }
}
