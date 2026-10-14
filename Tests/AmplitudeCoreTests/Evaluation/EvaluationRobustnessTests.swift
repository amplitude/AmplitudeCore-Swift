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

    func testDecodingErrorsNameTheFailingField() {
        // Consumers report this path to diagnostics, so it is part of the contract.
        let condition: [String: Any] = ["selector": [String](), "op": "is", "values": ["A"]]
        let bucket: [String: Any] = ["selector": [String](), "salt": "s", "allocations": [[String: Any]]()]
        let cases: [([String: Any], String)] = [
            (["conditions": [[condition]]], "segments[0].conditions[0][0].selector"),
            (["conditions": [[]]], "segments[0].conditions"),
            (["bucket": bucket], "segments[0].bucket.selector"),
            (["variant": 1], "segments[0].variant"),
        ]
        for (segment, path) in cases {
            XCTAssertThrowsError(try decode(segments: [segment])) { error in
                XCTAssertEqual(codingPath(of: error), path)
            }
        }
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

    func testIntegersBeyondIntMaxDecodeAsDoubles() throws {
        let flag = try decode(segments: [["variant": "on"]], extra: ["metadata": ["max": Int.max, "beyond": UInt64.max]])
        let metadata = engine.evaluate(context: [:], flags: [flag])["flag"]?.metadata
        XCTAssertEqual(metadata?["max"], .int(Int.max))
        XCTAssertEqual(metadata?["beyond"], .double(Double(UInt64.max)))
    }

    func testLaterMetadataWinsAKey() throws {
        let variants: [String: Any] = ["on": ["key": "on", "metadata": ["k": "variant"]], "off": ["key": "off"]]
        let flag = try decode(segments: [["variant": "on", "metadata": ["k": "segment"]], ["variant": "off"]],
                              extra: ["metadata": ["k": "flag"], "variants": variants])
        XCTAssertEqual(engine.evaluate(context: [:], flags: [flag])["flag"]?.metadata?["k"], .string("variant"))
        let withoutVariantMetadata = try decode(segments: [["variant": "off", "metadata": ["k": "segment"]]],
                                                extra: ["metadata": ["k": "flag"], "variants": variants])
        XCTAssertEqual(engine.evaluate(context: [:], flags: [withoutVariantMetadata])["flag"]?.metadata?["k"],
                       .string("segment"))
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
                             ["when": Date()], [Date()], ["ratio": Double.nan], [[Double.infinity]]]
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
        // Expected strings are JS `String(value)`.
        let cases: [(Any, String)] = [
            (0.1, "0.1"), (9.99, "9.99"), (1.0, "1"), (-0.0, "0"), (-2.5, "-2.5"), (0.1 + 0.2, "0.30000000000000004"),
            (Int64(1_726_380_000_000), "1726380000000"), (Float(0.1), "0.1"), (Float(16_777_216), "16777216"),
            (CGFloat(4.5), "4.5"), (Decimal(string: "19.99")!, "19.99"), (NSDecimalNumber(string: "0.729"), "0.729"),
            (true, "true"), (NSNumber(value: false), "false"),
        ]
        for (value, string) in cases {
            XCTAssertEqual(evaluate(try conditionFlag("is", [string]), properties(["p": value])), "on", "\(value)")
        }
        // JS writes 0.00001; rules do not hold numbers this small.
        XCTAssertEqual(evaluate(try conditionFlag("is", ["1e-05"]), properties(["p": 0.00001])), "on")
    }

    func testDecimalsDoNotPickUpBinaryRoundingErrors() throws {
        // Decimal's doubleValue is 19.990000000000002, which would be "greater" than 19.99.
        let price = Decimal(string: "19.99")!
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["19.99"]), properties(["p": price])), "off")
        XCTAssertEqual(evaluate(try conditionFlag("less or equal", ["19.99"]), properties(["p": price])), "on")
    }

    func testNumbersFromJSONAndInArrays() throws {
        // Numbers arriving through JSON, as from Flutter or React Native.
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"price":9.99,"tags":[0.1,1.0],"long":0.1234567890123456789}"#.utf8))
                as? [String: Any])
        XCTAssertEqual(evaluate(try conditionFlag("is", ["9.99"]), properties(["p": json["price"] as Any])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["0.1", "1"]), properties(["p": json["tags"] as Any])), "on")
        // JSONSerialization returns NSDecimalNumber for mantissas beyond 17 digits.
        XCTAssertEqual(evaluate(try conditionFlag("is", ["0.12345678901234568"]), properties(["p": json["long"] as Any])),
                       "on")
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
        // Not numbers: infinity and NaN, which Swift's `Double(_:)` reads, and blank text, which JS reads as 0.
        for value in ["inf", "infinity", "nan", "", " "] {
            XCTAssertEqual(evaluate(try conditionFlag("greater", ["1"]), properties(["p": value])), "off", value)
            XCTAssertEqual(evaluate(try conditionFlag("less", [value]), properties(["p": 1])), "off", value)
        }
        // Filter values that are not numbers are skipped; the others still compare.
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["abc", "10"]), properties(["p": 12])), "on")
        // Version operators still fall back to comparing strings when a value is not a version.
        XCTAssertEqual(evaluate(try conditionFlag("version greater", ["abc"]), properties(["p": "abd"])), "on")
    }

    func testNumericComparisonsIgnoreSurroundingWhitespace() throws {
        XCTAssertEqual(evaluate(try conditionFlag("greater", ["10"]), properties(["p": " 12\n"])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("less", [" 20 "]), properties(["p": 12])), "on")
    }

    // MARK: - Missing properties

    func testNegatedSetAndRegexOperatorsMatchAMissingProperty() throws {
        // Kotlin agrees; JS 0.13.6 returns false only because its missing-value branch omits these two operators.
        let missing: [[String: Any?]] = [[:], ["event": ["event_properties": ["p": nil] as [String: Any?]]],
                                         properties(["p": NSNull()])]
        for context in missing {
            for values in [["a"], ["(none)"]] {
                XCTAssertEqual(evaluate(try conditionFlag("set is not", values), context), "on", "\(context) \(values)")
                XCTAssertEqual(evaluate(try conditionFlag("regex does not match", values), context), "on", "\(context) \(values)")
            }
        }
    }

    // MARK: - Strings

    func testEmptyStringsInArraysAreDropped() throws {
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["a"]), properties(["p": ["a", ""]])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("set is", ["a"]), properties(["p": #"["a",""]"#])), "on")
        // A scalar empty string is still a value.
        XCTAssertEqual(evaluate(try conditionFlag("is", [""]), properties(["p": ""])), "on")
    }

    func testObjectsCompareAsJSON() throws {
        // Expected strings are JS `JSON.stringify` of the same values, apart from the sorted keys.
        let cases: [(Any, String)] = [
            (["q": "a\"b\\c\n\u{01}/\u{08}\u{0C}\r\t"], #"{"q":"a\"b\\c\n\u0001/\b\f\r\t"}"#),
            (["c": [1, "x"], "b": NSNull(), "a": true] as [String: Any], #"{"a":true,"b":null,"c":[1,"x"]}"#),
        ]
        for (value, json) in cases {
            XCTAssertEqual(evaluate(try conditionFlag("is", [json]), properties(["p": value])), "on", json)
        }
        XCTAssertEqual(evaluate(try conditionFlag("set is", [#"["a",1]"#]), properties(["p": [["a", 1]]])), "on")
        XCTAssertEqual(evaluate(try conditionFlag("contains", ["https://amplitude.com/a"]),
                                properties(["p": ["url": "https://amplitude.com/a"]])), "on")
        // JS writes {"n":0.1}; rules do not compare decimals inside objects.
        XCTAssertEqual(evaluate(try conditionFlag("is", [#"{"n":0.10000000000000001}"#]), properties(["p": ["n": 0.1]])),
                       "on")
    }

    // MARK: - Helpers

    private func codingPath(of error: Error) -> String? {
        let path: [CodingKey]
        switch error {
        case DecodingError.dataCorrupted(let context), DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context), DecodingError.keyNotFound(_, let context):
            path = context.codingPath
        default:
            return nil
        }
        return path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().drop { $0 == "." }.description
    }

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
