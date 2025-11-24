//
//  StringExtensionTests.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/21/25.
//

import XCTest
@_spi(Internal) @testable import AmplitudeCore

final class StringExtensionTests: XCTestCase {

    // MARK: - Equal Versions

    func testIsGreaterThanOrEqualToVersion_EqualVersions_SingleComponent() throws {
        XCTAssertTrue(try "1".isGreaterThanOrEqualToVersion("1"))
        XCTAssertTrue(try "5".isGreaterThanOrEqualToVersion("5"))
    }

    func testIsGreaterThanOrEqualToVersion_EqualVersions_TwoComponents() throws {
        XCTAssertTrue(try "1.0".isGreaterThanOrEqualToVersion("1.0"))
        XCTAssertTrue(try "2.5".isGreaterThanOrEqualToVersion("2.5"))
    }

    func testIsGreaterThanOrEqualToVersion_EqualVersions_ThreeComponents() throws {
        XCTAssertTrue(try "1.0.0".isGreaterThanOrEqualToVersion("1.0.0"))
        XCTAssertTrue(try "2.3.4".isGreaterThanOrEqualToVersion("2.3.4"))
    }

    func testIsGreaterThanOrEqualToVersion_EqualVersions_DifferentLengths() throws {
        XCTAssertTrue(try "1.0".isGreaterThanOrEqualToVersion("1.0.0"))
        XCTAssertTrue(try "1.0.0".isGreaterThanOrEqualToVersion("1.0"))
        XCTAssertTrue(try "2".isGreaterThanOrEqualToVersion("2.0.0"))
        XCTAssertTrue(try "2.0.0".isGreaterThanOrEqualToVersion("2"))
    }

    // MARK: - Greater Major Version

    func testIsGreaterThanOrEqualToVersion_GreaterMajor_SingleComponent() throws {
        XCTAssertTrue(try "2".isGreaterThanOrEqualToVersion("1"))
        XCTAssertTrue(try "10".isGreaterThanOrEqualToVersion("5"))
    }

    func testIsGreaterThanOrEqualToVersion_GreaterMajor_TwoComponents() throws {
        XCTAssertTrue(try "2.0".isGreaterThanOrEqualToVersion("1.0"))
        XCTAssertTrue(try "3.5".isGreaterThanOrEqualToVersion("2.9"))
    }

    func testIsGreaterThanOrEqualToVersion_GreaterMajor_ThreeComponents() throws {
        XCTAssertTrue(try "2.0.0".isGreaterThanOrEqualToVersion("1.0.0"))
        XCTAssertTrue(try "3.0.0".isGreaterThanOrEqualToVersion("2.9.9"))
    }

    // MARK: - Greater Minor Version

    func testIsGreaterThanOrEqualToVersion_GreaterMinor_TwoComponents() throws {
        XCTAssertTrue(try "1.2".isGreaterThanOrEqualToVersion("1.1"))
        XCTAssertTrue(try "1.10".isGreaterThanOrEqualToVersion("1.5"))
    }

    func testIsGreaterThanOrEqualToVersion_GreaterMinor_ThreeComponents() throws {
        XCTAssertTrue(try "1.2.0".isGreaterThanOrEqualToVersion("1.1.0"))
        XCTAssertTrue(try "1.5.0".isGreaterThanOrEqualToVersion("1.4.9"))
    }

    func testIsGreaterThanOrEqualToVersion_GreaterMinor_DifferentLengths() throws {
        XCTAssertTrue(try "1.2".isGreaterThanOrEqualToVersion("1.1.5"))
        XCTAssertTrue(try "1.3.0".isGreaterThanOrEqualToVersion("1.2"))
    }

    // MARK: - Greater Patch Version

    func testIsGreaterThanOrEqualToVersion_GreaterPatch() throws {
        XCTAssertTrue(try "1.0.2".isGreaterThanOrEqualToVersion("1.0.1"))
        XCTAssertTrue(try "1.2.10".isGreaterThanOrEqualToVersion("1.2.5"))
    }

    func testIsGreaterThanOrEqualToVersion_GreaterPatch_DifferentLengths() throws {
        XCTAssertTrue(try "1.0.1".isGreaterThanOrEqualToVersion("1.0"))
        XCTAssertTrue(try "1.2.1".isGreaterThanOrEqualToVersion("1.2"))
    }

    // MARK: - Lesser Versions

    func testIsGreaterThanOrEqualToVersion_LesserMajor_SingleComponent() throws {
        XCTAssertFalse(try "1".isGreaterThanOrEqualToVersion("2"))
        XCTAssertFalse(try "5".isGreaterThanOrEqualToVersion("10"))
    }

    func testIsGreaterThanOrEqualToVersion_LesserMajor_MultiComponent() throws {
        XCTAssertFalse(try "1.9".isGreaterThanOrEqualToVersion("2.0"))
        XCTAssertFalse(try "1.9.9".isGreaterThanOrEqualToVersion("2.0.0"))
    }

    func testIsGreaterThanOrEqualToVersion_LesserMinor() throws {
        XCTAssertFalse(try "1.1".isGreaterThanOrEqualToVersion("1.2"))
        XCTAssertFalse(try "1.4.9".isGreaterThanOrEqualToVersion("1.5.0"))
    }

    func testIsGreaterThanOrEqualToVersion_LesserPatch() throws {
        XCTAssertFalse(try "1.0.1".isGreaterThanOrEqualToVersion("1.0.2"))
        XCTAssertFalse(try "1.2.5".isGreaterThanOrEqualToVersion("1.2.10"))
    }

    func testIsGreaterThanOrEqualToVersion_LesserPatch_DifferentLengths() throws {
        XCTAssertFalse(try "1.0".isGreaterThanOrEqualToVersion("1.0.1"))
        XCTAssertFalse(try "1.2".isGreaterThanOrEqualToVersion("1.2.5"))
    }

    // MARK: - Edge Cases

    func testIsGreaterThanOrEqualToVersion_Zero() throws {
        XCTAssertTrue(try "0".isGreaterThanOrEqualToVersion("0"))
        XCTAssertTrue(try "0.0.0".isGreaterThanOrEqualToVersion("0.0.0"))
        XCTAssertTrue(try "1.0.0".isGreaterThanOrEqualToVersion("0.0.0"))
        XCTAssertFalse(try "0.0.0".isGreaterThanOrEqualToVersion("1.0.0"))
    }

    func testIsGreaterThanOrEqualToVersion_LargeNumbers() throws {
        XCTAssertTrue(try "100.200.300".isGreaterThanOrEqualToVersion("100.200.299"))
        XCTAssertTrue(try "999.999.999".isGreaterThanOrEqualToVersion("999.999.998"))
        XCTAssertFalse(try "100.200.299".isGreaterThanOrEqualToVersion("100.200.300"))
    }

    func testIsGreaterThanOrEqualToVersion_MixedLengths() throws {
        XCTAssertTrue(try "1.2.3".isGreaterThanOrEqualToVersion("1.2"))
        XCTAssertTrue(try "1.2.3".isGreaterThanOrEqualToVersion("1"))
        XCTAssertFalse(try "1".isGreaterThanOrEqualToVersion("1.0.1"))
        XCTAssertFalse(try "1.2".isGreaterThanOrEqualToVersion("1.2.1"))
    }

    // MARK: - Real-World Version Examples

    func testIsGreaterThanOrEqualToVersion_RealWorldExamples() throws {
        XCTAssertTrue(try "1.2.3".isGreaterThanOrEqualToVersion("1.2.3"))
        XCTAssertTrue(try "1.2.4".isGreaterThanOrEqualToVersion("1.2.3"))
        XCTAssertTrue(try "1.3.0".isGreaterThanOrEqualToVersion("1.2.9"))
        XCTAssertTrue(try "2.0.0".isGreaterThanOrEqualToVersion("1.9.9"))

        XCTAssertFalse(try "1.2.2".isGreaterThanOrEqualToVersion("1.2.3"))
        XCTAssertFalse(try "1.1.9".isGreaterThanOrEqualToVersion("1.2.0"))
        XCTAssertFalse(try "0.9.9".isGreaterThanOrEqualToVersion("1.0.0"))
    }

    func testIsGreaterThanOrEqualToVersion_NegativeNumbers() throws {
        XCTAssertTrue(try "1.0".isGreaterThanOrEqualToVersion("-1.0"))
        XCTAssertFalse(try "-1.0".isGreaterThanOrEqualToVersion("1.0"))
        XCTAssertTrue(try "-1.-2".isGreaterThanOrEqualToVersion("-1.-3"))
    }

    // MARK: - Error Cases - Empty Strings

    func testIsGreaterThanOrEqualToVersion_EmptyString_CurrentVersion() {
        XCTAssertThrowsError(try "".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .emptyVersionString)
        }
    }

    func testIsGreaterThanOrEqualToVersion_EmptyString_ComparisonVersion() {
        XCTAssertThrowsError(try "1.0.0".isGreaterThanOrEqualToVersion("")) { error in
            XCTAssertEqual(error as? VersionError, .emptyVersionString)
        }
    }

    func testIsGreaterThanOrEqualToVersion_EmptyString_BothVersions() {
        XCTAssertThrowsError(try "".isGreaterThanOrEqualToVersion("")) { error in
            XCTAssertEqual(error as? VersionError, .emptyVersionString)
        }
    }

    // MARK: - Error Cases - Non-Numeric Characters

    func testIsGreaterThanOrEqualToVersion_NonNumericCharacters_Letters() {
        XCTAssertThrowsError(try "1.a.2".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1.a.2"))
        }

        XCTAssertThrowsError(try "1.0.0".isGreaterThanOrEqualToVersion("1.b.2")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1.b.2"))
        }
    }

    func testIsGreaterThanOrEqualToVersion_NonNumericCharacters_Prefix() {
        XCTAssertThrowsError(try "v1.2.3".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("v1.2.3"))
        }
    }

    func testIsGreaterThanOrEqualToVersion_NonNumericCharacters_Suffix() {
        XCTAssertThrowsError(try "1.2.beta".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1.2.beta"))
        }

        XCTAssertThrowsError(try "2.0-alpha".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("2.0-alpha"))
        }
    }

    // MARK: - Error Cases - Malformed Versions

    func testIsGreaterThanOrEqualToVersion_LeadingDot() {
        XCTAssertThrowsError(try ".1.2".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString(".1.2"))
        }
    }

    func testIsGreaterThanOrEqualToVersion_TrailingDot() {
        XCTAssertThrowsError(try "1.2.".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1.2."))
        }
    }

    func testIsGreaterThanOrEqualToVersion_ConsecutiveDots() {
        XCTAssertThrowsError(try "1..2".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1..2"))
        }

        XCTAssertThrowsError(try "1...2".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1...2"))
        }
    }

    // MARK: - Error Cases - Special Characters

    func testIsGreaterThanOrEqualToVersion_SpecialCharacters() {
        XCTAssertThrowsError(try "1.@.2".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1.@.2"))
        }

        XCTAssertThrowsError(try "1.#.3".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1.#.3"))
        }
    }

    // MARK: - Error Cases - Whitespace

    func testIsGreaterThanOrEqualToVersion_Whitespace() {
        XCTAssertThrowsError(try "1. 2.3".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1. 2.3"))
        }

        XCTAssertThrowsError(try "1 .2.3".isGreaterThanOrEqualToVersion("1.0.0")) { error in
            XCTAssertEqual(error as? VersionError, .invalidVersionString("1 .2.3"))
        }
    }
}
