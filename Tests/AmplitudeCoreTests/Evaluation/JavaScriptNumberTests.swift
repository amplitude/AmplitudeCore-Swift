//
//  JavaScriptNumberTests.swift
//  AmplitudeCoreTests
//
//  Created by Jin Xu on 10/6/26.
//

import Foundation
import XCTest
@testable import AmplitudeCore

final class JavaScriptNumberTests: XCTestCase {

    func testDoublesFormatLikeJavaScript() {
        // Expected values are JavaScript's String(number).
        let cases: [(Double, String)] = [
            (9.99, "9.99"),
            (1.0, "1"),
            (100, "100"),
            (0.1 + 0.2, "0.30000000000000004"),
            (-2.5, "-2.5"),
            (0, "0"),
            (-0.0, "0"),
            (123_456.789, "123456.789"),
            (0.000001, "0.000001"),
            (0.0000012, "0.0000012"),
            (0.00001234, "0.00001234"),
            (1e-7, "1e-7"),
            (-1e-7, "-1e-7"),
            (5e-324, "5e-324"),
            (1e16, "10000000000000000"),
            (1e20, "100000000000000000000"),
            (1e21, "1e+21"),
            (1.5e21, "1.5e+21"),
            (9_007_199_254_740_994, "9007199254740994"),
            (1.7976931348623157e308, "1.7976931348623157e+308"),
            (.nan, "NaN"),
            (.infinity, "Infinity"),
            (-.infinity, "-Infinity"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(JavaScriptNumber.string(value), expected, "\(value)")
        }
    }

    func testFloatsUseTheirOwnShortestDigits() {
        XCTAssertEqual(JavaScriptNumber.string(Float(0.1)), "0.1")
        XCTAssertEqual(JavaScriptNumber.string(Float(0.1) as NSNumber), "0.1")
    }

    func testNumbersByType() throws {
        XCTAssertEqual(JavaScriptNumber.string(42 as NSNumber), "42")
        XCTAssertEqual(JavaScriptNumber.string(Int64(1_726_380_000_000) as NSNumber), "1726380000000")
        // Integers beyond 2^53 print rounded, as JavaScript numbers are doubles.
        XCTAssertEqual(JavaScriptNumber.string((Int64(1) << 53) as NSNumber), "9007199254740992")
        XCTAssertEqual(JavaScriptNumber.string(Int64.max as NSNumber), "9223372036854776000")
        XCTAssertEqual(JavaScriptNumber.string((-(Int64(1) << 53) - 2) as NSNumber), "-9007199254740994")
        XCTAssertEqual(JavaScriptNumber.string(UInt64.max as NSNumber), "18446744073709552000")
        XCTAssertEqual(JavaScriptNumber.string(CGFloat(4.5) as NSNumber), "4.5")
        XCTAssertEqual(JavaScriptNumber.string(NSDecimalNumber(string: "6.5")), "6.5")
        XCTAssertEqual(JavaScriptNumber.string(true as NSNumber), "true")
        XCTAssertEqual(JavaScriptNumber.string(NSNumber(value: false)), "false")

        // Numbers arriving through JSON, as from Flutter or React Native.
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(#"[9.99, 1.0, 1, 0.1, true]"#.utf8)) as? [NSNumber])
        XCTAssertEqual(json.map(JavaScriptNumber.string), ["9.99", "1", "1", "0.1", "true"])
    }
}
