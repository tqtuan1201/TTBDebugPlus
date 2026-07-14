//
//  LocalhostServerLauncherTests.swift
//  LocalhostToolsTests
//

import XCTest
@testable import LocalhostTools

final class LocalhostServerLauncherTests: XCTestCase {

    func testRingBufferCaps() {
        var lines: [String] = []
        for i in 0..<100 {
            LocalhostServerLauncher.appendLogLine("line-\(i)", to: &lines, max: 10)
        }
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(lines.first, "line-90")
        XCTAssertEqual(lines.last, "line-99")
    }
}
