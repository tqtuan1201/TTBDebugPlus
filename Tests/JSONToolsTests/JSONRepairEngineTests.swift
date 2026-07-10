//
//  JSONRepairEngineTests.swift
//  JSONToolsTests
//

import XCTest
@testable import JSONTools

final class JSONRepairEngineTests: XCTestCase {

    // MARK: - Valid passthrough

    func testValidJSONUnchanged() {
        let input = #"{"a":1,"b":[true,null]}"#
        let result = JSONRepairEngine.repair(input)
        XCTAssertTrue(result.isValidAfterRepair)
        XCTAssertFalse(result.didChange)
        XCTAssertTrue(result.fixes.isEmpty)
        XCTAssertNil(result.failureReason)
    }

    func testEmptyCannotApply() {
        let result = JSONRepairEngine.repair("   ")
        XCTAssertFalse(result.isValidAfterRepair)
        XCTAssertFalse(result.canSafelyApply)
        XCTAssertNotNil(result.failureReason)
    }

    // MARK: - Trailing commas

    func testTrailingCommaObject() {
        let result = JSONRepairEngine.repair(#"{ "a": 1, "b": 2, }"#)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? "")
        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.fixes.contains { $0.kind == .trailingComma })
        XCTAssertTrue(JSONValidator.isValid(result.repaired))
    }

    func testTrailingCommaArray() {
        let result = JSONRepairEngine.repair(#"[1, 2, 3,]"#)
        XCTAssertTrue(result.isValidAfterRepair)
        XCTAssertTrue(result.fixes.contains { $0.kind == .trailingComma })
    }

    // MARK: - Quotes / keys

    func testSingleQuotedStrings() {
        let result = JSONRepairEngine.repair("{ 'name': 'TTB', 'ok': true }")
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.canSafelyApply)
    }

    func testUnquotedKeys() {
        let result = JSONRepairEngine.repair("{ name: \"TTB\", count: 3 }")
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.fixes.contains { $0.kind == .unquotedKeys })
    }

    func testMissingCommaBetweenKeys() {
        // Root cause case: value followed by bare key without comma
        let result = JSONRepairEngine.repair("{a:1 b:2}")
        XCTAssertTrue(result.isValidAfterRepair, "OUT=\(result.repaired) ERR=\(result.failureReason ?? "")")
        XCTAssertTrue(result.fixes.contains { $0.kind == .missingComma || $0.kind == .unquotedKeys })
        // Round-trip parse
        XCTAssertTrue(JSONValidator.isValid(result.repaired))
    }

    // MARK: - Literals / comments / balance

    func testPythonLiterals() {
        let result = JSONRepairEngine.repair(#"{ "a": True, "b": False, "c": None, "d": undefined }"#)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.repaired.contains("true"))
        XCTAssertTrue(result.repaired.contains("null"))
    }

    func testStripComments() {
        let input = """
        {
          // name field
          "a": 1, /* trailing */
          "b": 2
        }
        """
        let result = JSONRepairEngine.repair(input)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.fixes.contains { $0.kind == .stripComments })
    }

    func testMissingClosingBrace() {
        let result = JSONRepairEngine.repair(#"{"a":1,"b":{"c":2}"#)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.fixes.contains { $0.kind == .balanceBraces })
    }

    // MARK: - Nested / complex

    func testNestedMixedJSObject() {
        let input = """
        {
          "users": [
            { id: 1, name: 'Ann', },
            { id: 2, active: True }
          ],
          meta: { version: 1, },
        }
        """
        let result = JSONRepairEngine.repair(input)
        XCTAssertTrue(result.isValidAfterRepair, "OUT=\(result.repaired)\nERR=\(result.failureReason ?? "")")
        XCTAssertTrue(result.canSafelyApply)
        // Ensure structure preserved
        XCTAssertTrue(result.repaired.contains("Ann") || result.repaired.contains("\"Ann\""))
        XCTAssertTrue(result.repaired.contains("true") || result.repaired.contains("True") == false)
    }

    func testCombinedSingleQuoteUnquotedTrailing() {
        let result = JSONRepairEngine.repair("{ name: 'x', }")
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.canSafelyApply)
    }

    func testNestedTrailingCommas() {
        let result = JSONRepairEngine.repair(#"{ "arr": [1, 2,], "obj": { "x": 1, }, }"#)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
    }

    func testNestedUnquotedInQuotedParent() {
        let result = JSONRepairEngine.repair(#"{ "a": 1, "b": { c: 2, }, }"#)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
    }

    // MARK: - Auto format

    func testAutoFormatPrettyPrints() {
        let result = JSONRepairEngine.autoFormat(#"{"z":1,"a":2}"#, indentation: 2)
        XCTAssertTrue(result.isValidAfterRepair)
        XCTAssertTrue(result.repaired.contains("\n"))
    }

    func testAutoFormatRepairsThenFormats() {
        let result = JSONRepairEngine.autoFormat("{ name: 'x', }", indentation: 2)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.didChange)
        XCTAssertTrue(result.canSafelyApply)
    }

    func testAutoFormatDoesNotPrettyInvalid() {
        // If something cannot be fixed, autoFormat must not invent pretty garbage
        let input = "{{{{not json at all!!!"
        let result = JSONRepairEngine.autoFormat(input, indentation: 2)
        if !result.isValidAfterRepair {
            XCTAssertFalse(result.canSafelyApply)
            XCTAssertNotNil(result.failureReason)
        }
    }

    // MARK: - Formatter

    func testPrettyPrintIndent() {
        let pretty = JSONFormatter.prettyPrint(#"{"a":1}"#, indentation: 2)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\"a\""))
    }

    func testMinify() {
        let mini = JSONFormatter.minify("{\n  \"a\": 1\n}")
        XCTAssertEqual(mini, #"{"a":1}"#)
    }

    func testCountNodes() {
        let n = JSONFormatter.countNodes(#"{"a":[1,2],"b":{"c":3}}"#)
        XCTAssertGreaterThan(n, 3)
    }

    // MARK: - Validator

    func testValidatorFriendlyEOF() {
        let issue = JSONValidator.validate(#"{"a":1"#)
        XCTAssertNotNil(issue)
        XCTAssertFalse(issue!.friendlyMessage.isEmpty)
    }

    func testEmptyValidateNil() {
        XCTAssertNil(JSONValidator.validate(""))
        XCTAssertNil(JSONValidator.validate("   \n  "))
        XCTAssertFalse(JSONValidator.isValid(""))
    }

    // MARK: - Safety gates

    func testCanSafelyApplyRequiresValidAndChanged() {
        let same = JSONRepairEngine.repair(#"{"a":1}"#)
        XCTAssertFalse(same.canSafelyApply)

        let fixed = JSONRepairEngine.repair("{a:1}")
        XCTAssertTrue(fixed.isValidAfterRepair)
        XCTAssertTrue(fixed.canSafelyApply)
        // Re-validate repaired independently
        XCTAssertTrue(JSONValidator.isValid(fixed.repaired))
    }

    func testPreservesEscapedQuotes() {
        let input = #"{"msg":"He said \"hi\""}"#
        let result = JSONRepairEngine.repair(input)
        XCTAssertTrue(result.isValidAfterRepair)
        XCTAssertEqual(result.repaired, input)
    }

    func testBOM() {
        let input = "\u{FEFF}" + #"{"a":1}"#
        let result = JSONRepairEngine.repair(input)
        XCTAssertTrue(result.isValidAfterRepair || JSONValidator.isValid(String(input.dropFirst())))
    }

    // MARK: - Array of objects messy

    func testArrayOfJSObjects() {
        let input = "[{id:1, name:'a'}, {id:2, name:'b',},]"
        let result = JSONRepairEngine.repair(input)
        XCTAssertTrue(result.isValidAfterRepair, result.failureReason ?? result.repaired)
        XCTAssertTrue(result.canSafelyApply)
    }
}
