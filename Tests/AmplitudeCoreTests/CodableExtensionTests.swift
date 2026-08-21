import Foundation
import XCTest

@_spi(Internal) @testable import AmplitudeCore

final class CodableExtensionTests: XCTestCase {
    private enum NonCodableValue {
        case value
    }

    private struct CodableValue: Codable {
        let id: Int
    }

    private struct TestEvent: AnalyticsEvent {
        var userId: String?
        var deviceId: String?
        var timestamp: Int64?
        var sessionId: Int64?
        var eventType: String
        var eventProperties: [String: Any]?
    }

    func testSnapshotEncodesAnalyticsDynamicPropertyTypes() throws {
        let properties: [String: Any] = [
            "integer": 1,
            "int64": Int64(2),
            "int32": Int32(3),
            "cgfloat": CGFloat(4.5),
            "double": 5.5,
            "decimal": Decimal(string: "6.5")!,
            "decimalNumber": NSDecimalNumber(string: "7.5"),
            "boolean": true,
            "numberBoolean": true as NSNumber,
            "array": [1, "two", ["three": 3]],
            "dictionary": ["nested": ["value": "four"]],
            "codable": CodableValue(id: 8),
            "null": NSNull(),
            "deeplyNested": [["one": [["two": 2]]]],
        ]
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "Dynamic types",
                              eventProperties: properties)

        let json = try jsonObject(for: event.encodableSnapshot())
        let encoded = try XCTUnwrap(json["event_properties"] as? [String: Any])

        XCTAssertEqual(encoded["integer"] as? Int, 1)
        XCTAssertEqual(encoded["int64"] as? Int64, 2)
        XCTAssertEqual(encoded["int32"] as? Int32, 3)
        XCTAssertEqual(encoded["cgfloat"] as? CGFloat, 4.5)
        XCTAssertEqual(encoded["double"] as? Double, 5.5)
        XCTAssertEqual(encoded["decimal"] as? Double, 6.5)
        XCTAssertEqual(encoded["decimalNumber"] as? Double, 7.5)
        XCTAssertEqual(encoded["boolean"] as? Bool, true)
        XCTAssertEqual(encoded["numberBoolean"] as? Bool, true)
        XCTAssertTrue(encoded["null"] is NSNull)
        XCTAssertEqual((encoded["codable"] as? [String: Any])?["id"] as? Int, 8)

        let array = try XCTUnwrap(encoded["array"] as? [Any])
        XCTAssertEqual(array[0] as? Int, 1)
        XCTAssertEqual(array[1] as? String, "two")
        XCTAssertEqual((array[2] as? [String: Any])?["three"] as? Int, 3)
        XCTAssertEqual((encoded["dictionary"] as? [String: Any])?["nested"] as? [String: String], ["value": "four"])
        XCTAssertEqual(encoded["deeplyNested"] as? NSArray, [["one": [["two": 2]]]])
    }

    func testSnapshotUsesAnalyticsFallbackForUnsupportedValuesAtEveryDepth() throws {
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "Unsupported",
                              eventProperties: [
                                  "direct": NonCodableValue.value,
                                  "array": [NonCodableValue.value],
                                  "dictionary": ["nested": NonCodableValue.value],
                              ])

        let json = try jsonObject(for: event.encodableSnapshot())
        let encoded = try XCTUnwrap(json["event_properties"] as? [String: Any])

        XCTAssertEqual(encoded["direct"] as? String, "[Non-Encodable]")
        XCTAssertEqual((encoded["array"] as? [Any])?.first as? String, "[Non-Encodable]")
        XCTAssertEqual((encoded["dictionary"] as? [String: Any])?["nested"] as? String, "[Non-Encodable]")
    }

    func testSnapshotEncodesFoundationCodableValues() throws {
        let date = Date(timeIntervalSinceReferenceDate: 123)
        let data = Data("payload".utf8)
        let url = try XCTUnwrap(URL(string: "https://amplitude.com/engagement"))
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "Foundation values",
                              eventProperties: [
                                  "date": date,
                                  "data": data,
                                  "url": url,
                              ])

        let json = try jsonObject(for: event.encodableSnapshot())
        let encoded = try XCTUnwrap(json["event_properties"] as? [String: Any])

        XCTAssertEqual(encoded["date"] as? Double, 123)
        XCTAssertEqual(encoded["data"] as? String, data.base64EncodedString())
        XCTAssertEqual(encoded["url"] as? String, url.absoluteString)
    }

    func testSnapshotOmitsNilEventPropertyValues() throws {
        let properties: [String: Any] = [
            "integer": 1,
            "string": Optional<String>.none as Any,
            "array": Optional<[Any]>.none as Any,
        ]
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "Nil properties",
                              eventProperties: properties)

        let json = try jsonObject(for: event.encodableSnapshot())
        let encoded = try XCTUnwrap(json["event_properties"] as? [String: Any])

        XCTAssertEqual(encoded["integer"] as? Int, 1)
        XCTAssertNil(encoded["string"])
        XCTAssertNil(encoded["array"])
    }

    func testSnapshotOmitsEventPropertiesWhenTheyAreNil() throws {
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "No properties",
                              eventProperties: nil)

        let json = try jsonObject(for: event.encodableSnapshot())

        XCTAssertNil(json["event_properties"])
    }

    func testSnapshotEncodingFailsForNonFiniteNumbers() {
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "Non-finite",
                              eventProperties: ["value": Double.nan])

        XCTAssertThrowsError(try JSONEncoder().encode(event.encodableSnapshot()))
    }

    func testSnapshotDecodesNestedAnalyticsEventProperties() throws {
        let data = Data(
            """
            {
              "event_type": "test",
              "user_id": "test-user",
              "device_id": "test-device",
              "time": 1670030478000,
              "session_id": 42,
              "event_properties": {
                "integer": 1,
                "string": "stringValue",
                "array": [1, 2, 3],
                "nestedarray": [[{"a": {"b": 1}}]],
                "nesteddictionary": {"a": {"b": [[1]]}}
              }
            }
            """.utf8)

        let snapshot = try JSONDecoder().decode(AnalyticsEventSnapshot.self, from: data)

        XCTAssertEqual(snapshot.eventType, "test")
        XCTAssertEqual(snapshot.userId, "test-user")
        XCTAssertEqual(snapshot.deviceId, "test-device")
        XCTAssertEqual(snapshot.timestamp, 1_670_030_478_000)
        XCTAssertEqual(snapshot.sessionId, 42)
        XCTAssertEqual(snapshot.eventProperties?["integer"] as? Int, 1)
        XCTAssertEqual(snapshot.eventProperties?["string"] as? String, "stringValue")
        XCTAssertEqual(snapshot.eventProperties?["array"] as? [Double], [1, 2, 3])
        XCTAssertEqual(snapshot.eventProperties?["nestedarray"] as? NSArray, [[ ["a": ["b": 1]] ]])
        XCTAssertEqual(snapshot.eventProperties?["nesteddictionary"] as? NSDictionary, ["a": ["b": [[1]]]])
    }

    func testSnapshotDecodesNullEventPropertiesAsAbsent() throws {
        let data = Data(
            """
            {
              "event_type": "test",
              "event_properties": {
                "integer": 1,
                "string": null,
                "array": null
              }
            }
            """.utf8)

        let snapshot = try JSONDecoder().decode(AnalyticsEventSnapshot.self, from: data)

        XCTAssertEqual(snapshot.eventProperties?["integer"] as? Int, 1)
        XCTAssertNil(snapshot.eventProperties?["string"])
        XCTAssertNil(snapshot.eventProperties?["array"])
    }

    private func jsonObject(for snapshot: any EncodableAnalyticsEvent) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
