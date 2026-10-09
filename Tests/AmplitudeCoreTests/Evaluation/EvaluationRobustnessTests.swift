//
//  EvaluationRobustnessTests.swift
//  AmplitudeCoreTests
//
//  Created by Jin Xu on 10/6/26.
//
//  Malformed rules and unusual property values, written against the SPI surface only. For rules and
//  values that JSON can carry, the expected results are those of @amplitude/experiment-core 0.13.6,
//  except that malformed rules fail decoding, where JS throws, matches or misses depending on the defect.
//

import Foundation
import XCTest
@_spi(Internal) import AmplitudeCore

final class EvaluationRobustnessTests: XCTestCase {

    private let engine = EvaluationEngine()

    // MARK: - Decoding

    func testAbsentOrNullFieldsMeanNone() throws {
        // A segment without conditions matches everyone; one without a bucket returns its variant.
        let flag = try decode(segments: [["conditions": NSNull(), "bucket": NSNull(), "variant": "on"]])
        XCTAssertEqual(evaluate(flag, [:]), "on")
    }

    func testMalformedConditionsFailDecoding() {
        let valid: [String: Any] = ["selector": ["context", "event_types"], "op": "set contains", "values": ["A"]]
        let malformed: [String: Any] = [
            "missing values": valid.filter { $0.key != "values" },
            "values not an array": valid.merging(["values": "A"]) { $1 },
            "number in values": valid.merging(["values": [9.99]]) { $1 },
            "selector not an array": valid.merging(["selector": "context.event_types"]) { $1 },
            "empty selector": valid.merging(["selector": [String]()]) { $1 },
            "missing op": valid.filter { $0.key != "op" },
            "op not a string": valid.merging(["op": 1]) { $1 },
        ]
        for (name, condition) in malformed {
            XCTAssertThrowsError(try decode(segments: [["conditions": [[condition]], "variant": "on"]]), name)
        }
        XCTAssertThrowsError(try decode(segments: [["conditions": [valid], "variant": "on"]]), "one level of nesting")
        // Remote Config turns `[[null]]` into `[[]]`, which would match everyone.
        XCTAssertThrowsError(try decode(segments: [["conditions": [[]], "variant": "on"]]), "empty group")
        XCTAssertThrowsError(try decode(segments: [["conditions": [[valid], []], "variant": "on"]]), "one empty group")
        XCTAssertThrowsError(try decode(segments: [["conditions": "x", "variant": "on"]]), "conditions not an array")
    }

    func testMalformedBucketsFailDecoding() {
        let distribution: [String: Any] = ["variant": "on", "range": [0, 42_949_673]]
        let allocation: [String: Any] = ["range": [0, 100], "distributions": [distribution]]
        let valid: [String: Any] = ["selector": ["context", "session_id"], "salt": "s", "allocations": [allocation]]
        let malformed: [String: Any] = [
            "missing salt": valid.filter { $0.key != "salt" },
            "missing selector": valid.filter { $0.key != "selector" },
            "empty selector": valid.merging(["selector": [String]()]) { $1 },
            "missing allocations": valid.filter { $0.key != "allocations" },
            "missing distributions": valid.merging(["allocations": [["range": [0, 100]]]]) { $1 },
            "distribution without variant": valid.merging(
                ["allocations": [["range": [0, 100], "distributions": [["range": [0, 1]]]]]]) { $1 },
            "non-integer range": valid.merging(
                ["allocations": [["range": [0, 1.5], "distributions": [distribution]]]]) { $1 },
        ]
        for (name, bucket) in malformed {
            XCTAssertThrowsError(try decode(segments: [["bucket": bucket]]), name)
        }
    }

    func testMalformedSegmentVariantFailsDecoding() {
        XCTAssertThrowsError(try decode(segments: [["variant": 1]]))
    }

    func testMetadataStaysLenient() throws {
        let flag = try decode(segments: [["variant": "on", "metadata": "not an object"]], extra: ["metadata": 1])
        XCTAssertEqual(evaluate(flag, [:]), "on")
    }

    // MARK: - Metadata, values and payloads

    func testMetadataIsJSON() throws {
        let flag = try decode(segments: [["variant": "on", "metadata": ["segmentId": "s1", "note": NSNull()]]],
                              extra: ["metadata": ["flagVersion": 3, "nested": ["a": NSNull()]]])
        let metadata = engine.evaluate(context: [:], flags: [flag])["flag"]?.metadata
        // A null value stays distinct from an absent key.
        XCTAssertEqual(metadata, ["segmentId": .string("s1"), "note": .null, "flagVersion": .int(3),
                                  "nested": .dictionary(["a": .null])])
        XCTAssertNil(metadata?["absent"])
    }

    func testConditionsReadAnotherFlagsResult() throws {
        let dependency = try JSONDecoder().decode(EvaluationFlag.self, from: Data(#"""
        {"key": "dependency", "segments": [{"metadata": {"segmentName": "all"}, "variant": "on"}],
         "variants": {"on": {"key": "on", "value": "on", "payload": {"n": null, "ratio": 1.5, "tags": ["a", null, "b"]}}}}
        """#.utf8))
        let cases: [([String], String, String)] = [
            (["value"], "is", "on"),
            (["metadata", "segmentName"], "is", "all"),
            (["payload", "ratio"], "greater", "1"),
            (["payload", "n"], "is", "(none)"),
            (["payload", "tags"], "set contains", "b"),
            (["payload"], "is", #"{"n":null,"ratio":1.5,"tags":["a",null,"b"]}"#),
        ]
        for (path, op, value) in cases {
            let condition: [String: Any] = ["selector": ["result", "dependency"] + path, "op": op, "values": [value]]
            let flag = try decode(segments: [["conditions": [[condition]], "variant": "on"], ["variant": "off"]])
            XCTAssertEqual(engine.evaluate(context: [:], flags: [dependency, flag])["flag"]?.key, "on", "\(path) \(op) \(value)")
        }
    }

    // MARK: - Bucket ranges

    func testShortOrReversedRangesDoNotMatch() throws {
        // JS compares against `range[1]`, so a missing end or a reversed range never matches.
        let badRanges: [[Int]] = [[], [0], [42_949_673, 0], [100, 0]]
        for range in badRanges {
            let badAllocation = try decode(segments: [["bucket": bucket(allocationRange: range)], ["variant": "off"]])
            XCTAssertEqual(evaluate(badAllocation, ["session_id": 1]), "off", "allocation \(range)")
            let badDistribution = try decode(segments: [["bucket": bucket(distributionRange: range)], ["variant": "off"]])
            XCTAssertEqual(evaluate(badDistribution, ["session_id": 1]), "off", "distribution \(range)")
        }
    }

    func testRangeUsesItsFirstTwoElements() throws {
        let flag = try decode(segments: [["bucket": bucket(allocationRange: [0, 100, 0])], ["variant": "off"]])
        XCTAssertEqual(evaluate(flag, ["session_id": 1]), "on")
    }

    func testLaterAllocationIsTriedAfterABadOne() throws {
        var bucket = bucket(allocationRange: [5])
        let good: [String: Any] = ["range": [0, 100], "distributions": [["variant": "on", "range": [0, 42_949_673]]]]
        bucket["allocations"] = (bucket["allocations"] as? [Any] ?? []) + [good]
        let flag = try decode(segments: [["bucket": bucket], ["variant": "off"]])
        XCTAssertEqual(evaluate(flag, ["session_id": 1]), "on")
    }

    // MARK: - Values JSON cannot represent

    func testUnrepresentableValuesDoNotCrash() throws {
        let values: [Any] = [Date(), Data([1]), URL(string: "https://amplitude.com")!, NSObject(),
                             ["when": Date()], [Date()]]
        for value in values {
            for op in ["is", "is not", "contains", "set contains", "greater", "regex match"] {
                let flag = try conditionFlag(op, ["x"])
                XCTAssertEqual(evaluate(flag, properties(["p": value])), "off", "\(op) on \(type(of: value))")
            }
        }
    }

    func testUnrepresentableArrayElementsAreDropped() throws {
        let flag = try conditionFlag("set is", ["a", "1.5"])
        XCTAssertEqual(evaluate(flag, properties(["p": [Date(), "a", 1.5, NSNull(), ""] as [Any]])), "on")
    }

    // MARK: - Numbers

    func testNumbersCompareAsJavaScriptStrings() throws {
        let cases: [(Any, String)] = [
            (0.1, "0.1"), (9.99, "9.99"), (1.0, "1"), (-0.0, "0"), (1e21, "1e+21"), (1e-7, "1e-7"),
            (Float(0.1), "0.1"), (NSDecimalNumber(string: "6.5"), "6.5"), (Int64(1) << 53, "9007199254740992"),
            (Int64.max, "9223372036854776000"), (Double.nan, "NaN"), (-Double.infinity, "-Infinity"),
            (true, "true"), (Decimal(string: "19.99")!, "19.99"),
        ]
        for (value, string) in cases {
            XCTAssertEqual(evaluate(try conditionFlag("is", [string]), properties(["p": value])), "on", "\(value)")
        }
    }

    func testDecimalsDoNotPickUpBinaryRoundingErrors() throws {
        // Decimal's doubleValue is 19.990000000000002, which would be "greater" than 19.99.
        let price = Decimal(string: "19.99")!
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["19.99"]), properties(["p": price])), "off")
        XCTAssertEqual(evaluate(try conditionFlag("less or equal", ["19.99"]), properties(["p": price])), "on")
    }

    func testNumbersFromJSONAndInArrays() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"price":9.99,"tags":[0.1,1.0]}"#.utf8)) as? [String: Any])
        XCTAssertEqual(evaluate(try conditionFlag("is", ["9.99"]), properties(["p": json["price"] as Any])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["0.1", "1"]), properties(["p": json["tags"] as Any])), "on")
    }

    func testNumericOperatorsNeverMatchNonNumbers() throws {
        // Comparing strings instead would put letters above digits: "N/A" greater 100.
        for value in ["N/A", "unknown", "abc"] as [Any] + [true] {
            XCTAssertEqual(evaluate(try conditionFlag("greater", ["100"]), properties(["p": value])), "off", "\(value)")
            XCTAssertEqual(evaluate(try conditionFlag("greater or equal", ["0"]), properties(["p": value])), "off", "\(value)")
        }
        XCTAssertEqual(evaluate(try conditionFlag("less", ["abc"]), properties(["p": 5])), "off")
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["2026-01-01"]), properties(["p": "2026-10-06"])), "off")
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["NaN"]), properties(["p": "NaN"])), "off")
        // Swift's `Double(_:)` reads these as numbers; JS `Number()` does not.
        for value in ["inf", "infinity", "0x1p4"] {
            XCTAssertEqual(evaluate(try conditionFlag("greater", ["1"]), properties(["p": value])), "off", value)
        }
        // JS reads unsigned 0x / 0o / 0b integers, on either side.
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["15"]), properties(["p": "0x10"])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("less", ["0b11"]), properties(["p": 2])), "on")
        // Filter values that are not numbers are skipped; the others still compare.
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["abc", "10"]), properties(["p": 12])), "on")
        // Version operators still fall back to comparing strings when a value is not a version.
        XCTAssertEqual(evaluate(try conditionFlag("version greater", ["abc"]), properties(["p": "abd"])), "on")
    }

    func testNumericComparisonsIgnoreSurroundingWhitespace() throws {
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["10"]), properties(["p": " 12\n"])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("less", [" 20 "]), properties(["p": 12])), "on")
    }

    // MARK: - Strings

    func testEmptyStringsInArraysAreDropped() throws {
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["a"]), properties(["p": ["a", ""]])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["a"]), properties(["p": #"["a",""]"#])), "on")
        // A scalar empty string is still a value.
        XCTAssertEqual(evaluate(try conditionFlag("is", [""]), properties(["p": ""])), "on")
    }

    func testObjectsStringifyLikeJavaScript() throws {
        // Expected strings are JS `JSON.stringify` of the same values.
        let cases: [(Any, String)] = [
            (["n": 0.1], #"{"n":0.1}"#),
            (["ratio": Double.nan], #"{"ratio":null}"#),
            (["q": "a\"b\\c\n\u{01}/"], #"{"q":"a\"b\\c\n\u0001/"}"#),
            (["a": true, "b": NSNull(), "c": [1, "x"]] as [String: Any], #"{"a":true,"b":null,"c":[1,"x"]}"#),
            (["big": Int64.max], #"{"big":9223372036854776000}"#),
        ]
        for (value, json) in cases {
            XCTAssertEqual(evaluate(try conditionFlag("is", [json]), properties(["p": value])), "on", json)
        }
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["[0.1]"]), properties(["p": [[0.1]]])), "on")
        // "/" is not escaped, on every OS version.
        XCTAssertEqual(evaluate(try conditionFlag("contains", ["https://amplitude.com/a"]),
                                properties(["p": ["url": "https://amplitude.com/a"]])), "on")
    }

    // MARK: - Helpers

    private func evaluate(_ flag: EvaluationFlag, _ context: [String: Any?]) -> String? {
        return engine.evaluate(context: context, flags: [flag])["flag"]?.key
    }

    private func properties(_ properties: [String: Any]) -> [String: Any?] {
        return ["event": ["event_properties": properties]]
    }

    private func decode(segments: [[String: Any]], extra: [String: Any] = [:]) throws -> EvaluationFlag {
        let json: [String: Any] = ["key": "flag", "variants": ["on": ["key": "on"], "off": ["key": "off"]],
                                   "segments": segments].merging(extra) { $1 }
        return try JSONDecoder().decode(EvaluationFlag.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// A single condition on the event property `p`, falling back to `off`.
    private func conditionFlag(_ op: String, _ values: [String]) throws -> EvaluationFlag {
        let condition: [String: Any] = ["selector": ["context", "event", "event_properties", "p"], "op": op,
                                        "values": values]
        return try decode(segments: [["conditions": [[condition]], "variant": "on"], ["variant": "off"]])
    }

    /// A bucket on `session_id` that puts everyone in `on`, unless a range is overridden.
    private func bucket(allocationRange: [Int] = [0, 100], distributionRange: [Int] = [0, 42_949_673]) -> [String: Any] {
        let distribution: [String: Any] = ["variant": "on", "range": distributionRange]
        return ["selector": ["context", "session_id"], "salt": "salt",
                "allocations": [["range": allocationRange, "distributions": [distribution]]]]
    }
}
