//
//  JSONValueTests.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 9/25/26.
//

import XCTest
@testable import AmplitudeCore

final class JSONValueTests: XCTestCase {

    // MARK: - Swift values

    func testSwiftValuesKeepTheirTypes() {
        XCTAssertEqual(describe(JSONValue.from("text")), "string(text)")
        XCTAssertEqual(describe(JSONValue.from(true)), "bool(true)")
        XCTAssertEqual(describe(JSONValue.from(false)), "bool(false)")
        XCTAssertEqual(describe(JSONValue.from(0)), "int(0)")
        XCTAssertEqual(describe(JSONValue.from(1)), "int(1)")
        XCTAssertEqual(describe(JSONValue.from(1.5)), "double(1.5)")
        XCTAssertEqual(describe(JSONValue.from(Float(0.5))), "double(0.5)")
    }

    func testFixedWidthIntegersAreNotDropped() {
        XCTAssertEqual(describe(JSONValue.from(Int8(-8))), "int(-8)")
        XCTAssertEqual(describe(JSONValue.from(Int16(16))), "int(16)")
        XCTAssertEqual(describe(JSONValue.from(Int32(32))), "int(32)")
        XCTAssertEqual(describe(JSONValue.from(Int64(1_726_380_000_000))), "int(1726380000000)")
        XCTAssertEqual(describe(JSONValue.from(UInt(5))), "int(5)")
        XCTAssertEqual(describe(JSONValue.from(UInt8(1))), "int(1)")
        XCTAssertEqual(describe(JSONValue.from(UInt64.max)), "double(\(Double(UInt64.max)))")
    }

    func testDecimalAndCGFloat() throws {
        XCTAssertEqual(describe(JSONValue.from(try XCTUnwrap(Decimal(string: "6.5")))), "double(6.5)")
        XCTAssertEqual(describe(JSONValue.from(NSDecimalNumber(string: "7.5"))), "double(7.5)")
        XCTAssertEqual(describe(JSONValue.from(NSDecimalNumber(string: "8"))), "int(8)")
        XCTAssertEqual(describe(JSONValue.from(CGFloat(4.5))), "double(4.5)")
    }

    func testFloatsAndDecimalsKeepTheirDigits() throws {
        XCTAssertEqual(describe(JSONValue.from(Float(0.1))), "double(0.1)")
        XCTAssertEqual(describe(JSONValue.from(Float(1e-7))), "double(1e-07)")
        XCTAssertEqual(describe(JSONValue.from(try XCTUnwrap(Decimal(string: "19.99")))), "double(19.99)")
        XCTAssertEqual(describe(JSONValue.from(NSDecimalNumber(string: "1e30"))), "double(1e+30)")
        XCTAssertNil(JSONValue.from(Float.nan))
        XCTAssertNil(JSONValue.from(NSDecimalNumber.notANumber))
    }

    // MARK: - Bridged numbers

    func testBridgedNumbersAreNotBooleans() {
        XCTAssertEqual(describe(JSONValue.from(NSNumber(value: 0))), "int(0)")
        XCTAssertEqual(describe(JSONValue.from(NSNumber(value: 1))), "int(1)")
        XCTAssertEqual(describe(JSONValue.from(NSNumber(value: CChar(1)))), "int(1)")
        XCTAssertEqual(describe(JSONValue.from(NSNumber(value: 1.0))), "double(1.0)")
        XCTAssertEqual(describe(JSONValue.from(NSNumber(value: true))), "bool(true)")
        XCTAssertEqual(describe(JSONValue.from(kCFBooleanFalse as Any)), "bool(false)")
    }

    func testJSONSerializationValues() throws {
        let object = try jsonObject("""
        {"zero":0,"one":1,"two":2,"t":true,"f":false,"whole":1.0,"half":1.5,"big":1726380000000,"null":null}
        """)
        XCTAssertEqual(describe(JSONValue.from(object)),
                       "{big:int(1726380000000),f:bool(false),half:double(1.5),null:null,one:int(1),"
                       + "t:bool(true),two:int(2),whole:double(1.0),zero:int(0)}")
    }

    func testNestedCollectionsMatchCodableDecoding() throws {
        let json = #"{"a":[1,0,true,false,1.5,"s",null,{"n":1,"b":[true,0]}]}"#
        let converted = JSONValue.from(try jsonObject(json))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(describe(converted), describe(decoded))
    }

    // MARK: - Null and unsupported values

    func testNullIsPreserved() {
        XCTAssertEqual(describe(JSONValue.from(NSNull())), "null")
        XCTAssertEqual(describe(JSONValue.from(["key": NSNull()] as [String: Any])), "{key:null}")
    }

    func testValuesJSONCannotRepresentAreDropped() {
        XCTAssertNil(JSONValue.from(Double.nan))
        XCTAssertNil(JSONValue.from(Double.infinity))
        XCTAssertNil(JSONValue.from(-Float.infinity))
        XCTAssertNil(JSONValue.from(Date()))
        XCTAssertEqual(describe(JSONValue.from([1, Double.nan, 2] as [Any])), "[int(1),int(2)]")
    }

    func testToAnyRoundTrip() throws {
        let original = JSONValue.from(try jsonObject(#"{"a":[1,true,1.5,"s",null],"b":{"c":0}}"#))
        let roundTripped = original.flatMap { JSONValue.from($0.toAny()) }
        XCTAssertEqual(describe(roundTripped), describe(original))
    }

    // MARK: - Diagnostics events

    func testDiagnosticsEventEncodesBridgedNumbersAsNumbers() throws {
        let properties: [String: any Sendable] = [
            "count": NSNumber(value: 1),
            "retry": NSNumber(value: 0),
            "enabled": NSNumber(value: true),
        ]
        XCTAssertTrue(try encodedProperties(properties).contains(#""event_properties":{"count":1,"enabled":true,"retry":0}"#))
    }

    func testDiagnosticsEventPayloadForNativeValuesIsUnchanged() throws {
        // Same shape as the properties Amplitude-Swift records for `analytics.events.dropped`.
        let properties: [String: any Sendable] = [
            "events": ["a", "b"],
            "count": 2,
            "code": 413,
            "message": "Payload Too Large",
        ]
        XCTAssertTrue(try encodedProperties(properties).contains(
            #""event_properties":{"code":413,"count":2,"events":["a","b"],"message":"Payload Too Large"}"#))
    }

    func testDiagnosticsEventKeepsTheDigitsOfFloatsAndDecimals() throws {
        let properties: [String: any Sendable] = ["ratio": Float(0.1), "price": try XCTUnwrap(Decimal(string: "19.99"))]
        XCTAssertTrue(try encodedProperties(properties).contains(#""event_properties":{"price":19.99,"ratio":0.1}"#))
    }

    func testDiagnosticsEventWithNonFiniteNumberStillEncodes() throws {
        // A non-finite double used to make JSONEncoder throw for the whole event.
        let properties: [String: any Sendable] = ["ratio": Double.nan, "count": 1]
        XCTAssertTrue(try encodedProperties(properties).contains(#""event_properties":{"count":1}"#))
    }

    func testDiagnosticsEventRoundTripKeepsTypes() throws {
        let properties: [String: any Sendable] = ["count": NSNumber(value: 1), "flag": true, "ids": [Int64(7)]]
        let event = DiagnosticsEvent(eventName: "test", time: 1, eventProperties: properties)
        let decoded = try JSONDecoder().decode(DiagnosticsEvent.self, from: JSONEncoder().encode(event))
        let reencoded = try encodedProperties(decoded.eventProperties ?? [:])
        XCTAssertEqual(reencoded, try encodedProperties(properties))
        XCTAssertTrue(reencoded.contains(#""event_properties":{"count":1,"flag":true,"ids":[7]}"#))
    }

    // MARK: - Helpers

    private func jsonObject(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    }

    private func encodedProperties(_ properties: [String: any Sendable]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let event = DiagnosticsEvent(eventName: "test", time: 1, eventProperties: properties)
        return String(decoding: try encoder.encode(event), as: UTF8.self)
    }

    /// Canonical description that keeps the case of every value, with dictionary keys sorted.
    private func describe(_ value: JSONValue?) -> String {
        guard let value else {
            return "nil"
        }
        switch value {
        case .string(let string):
            return "string(\(string))"
        case .int(let int):
            return "int(\(int))"
        case .double(let double):
            return "double(\(double))"
        case .bool(let bool):
            return "bool(\(bool))"
        case .null:
            return "null"
        case .array(let array):
            return "[" + array.map { describe($0) }.joined(separator: ",") + "]"
        case .dictionary(let dictionary):
            return "{" + dictionary.keys.sorted().map { "\($0):\(describe(dictionary[$0]))" }.joined(separator: ",") + "}"
        }
    }
}
