import Foundation
import XCTest

@_spi(Internal) @testable import AmplitudeCore

final class AnalyticsEventSnapshotTests: XCTestCase {
    private enum NonCodableValue {
        case value
    }

    private struct TestEvent: AnalyticsEvent {
        var userId: String?
        var deviceId: String?
        var timestamp: Int64?
        var sessionId: Int64?
        var eventType: String
        var eventProperties: [String: Any]?
    }

    func testSnapshotConformsToEncodableAnalyticsEventAndOnlyPropertiesMutate() {
        let event = TestEvent(userId: "user-id",
                              deviceId: "device-id",
                              timestamp: 123,
                              sessionId: 456,
                              eventType: "event-type",
                              eventProperties: ["before": true])
        var snapshot = event.encodableSnapshot()

        snapshot.eventProperties = ["after": true]

        XCTAssertEqual(snapshot.userId, "user-id")
        XCTAssertEqual(snapshot.deviceId, "device-id")
        XCTAssertEqual(snapshot.timestamp, 123)
        XCTAssertEqual(snapshot.sessionId, 456)
        XCTAssertEqual(snapshot.eventType, "event-type")
        XCTAssertEqual(snapshot.eventProperties?["after"] as? Bool, true)
    }

    func testSnapshotOfSnapshotPreservesSnapshot() {
        let source = TestEvent(userId: "user-id",
                               deviceId: "device-id",
                               timestamp: 123,
                               sessionId: 456,
                               eventType: "event-type",
                               eventProperties: ["property": "value"])
        let snapshot = source.encodableSnapshot()
        let event: any AnalyticsEvent = snapshot

        let resnapshot = event.encodableSnapshot()

        XCTAssertEqual(resnapshot.userId, snapshot.userId)
        XCTAssertEqual(resnapshot.deviceId, snapshot.deviceId)
        XCTAssertEqual(resnapshot.timestamp, snapshot.timestamp)
        XCTAssertEqual(resnapshot.sessionId, snapshot.sessionId)
        XCTAssertEqual(resnapshot.eventType, snapshot.eventType)
        XCTAssertEqual(resnapshot.eventProperties?["property"] as? String, "value")
    }

    func testSnapshotEncodesOnlyAnalyticsEventFields() throws {
        let event = TestEvent(userId: "user-id",
                              deviceId: "device-id",
                              timestamp: 1_713_000_000_000,
                              sessionId: 1_713_000_000_000,
                              eventType: "Order Completed",
                              eventProperties: [
                                  "product": "socks",
                                  "quantity": 2,
                                  "nested": ["enabled": true],
                              ])

        let data = try JSONEncoder().encode(event.encodableSnapshot())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["event_type"] as? String, "Order Completed")
        XCTAssertEqual(json["user_id"] as? String, "user-id")
        XCTAssertEqual(json["device_id"] as? String, "device-id")
        XCTAssertEqual(json["time"] as? Int64, 1_713_000_000_000)
        XCTAssertEqual(json["session_id"] as? Int64, 1_713_000_000_000)

        let properties = try XCTUnwrap(json["event_properties"] as? [String: Any])
        XCTAssertEqual(properties["product"] as? String, "socks")
        XCTAssertEqual(properties["quantity"] as? Int, 2)
        XCTAssertEqual((properties["nested"] as? [String: Any])?["enabled"] as? Bool, true)
    }

    func testSnapshotUsesAnalyticsFallbackForNonCodableProperties() throws {
        let event = TestEvent(userId: nil,
                              deviceId: nil,
                              timestamp: nil,
                              sessionId: nil,
                              eventType: "Enum Property",
                              eventProperties: ["state": NonCodableValue.value])

        let data = try JSONEncoder().encode(event.encodableSnapshot())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(json["event_properties"] as? [String: Any])

        XCTAssertEqual(properties["state"] as? String, "[Non-Encodable]")
    }

    func testSnapshotRoundTripsNestedProperties() throws {
        let event = TestEvent(userId: "user-id",
                              deviceId: "device-id",
                              timestamp: 42,
                              sessionId: 7,
                              eventType: "Nested",
                              eventProperties: [
                                  "array": ["one", ["two": 2]],
                              ])

        let data = try JSONEncoder().encode(event.encodableSnapshot())
        let decoded = try JSONDecoder().decode(AnalyticsEventSnapshot.self, from: data)

        XCTAssertEqual(decoded.eventType, "Nested")
        XCTAssertEqual(decoded.userId, "user-id")
        XCTAssertEqual(decoded.deviceId, "device-id")
        XCTAssertEqual(decoded.timestamp, 42)
        XCTAssertEqual(decoded.sessionId, 7)
        let array = try XCTUnwrap(decoded.eventProperties?["array"] as? [Any])
        XCTAssertEqual(array[0] as? String, "one")
        XCTAssertEqual((array[1] as? [String: Any])?["two"] as? Int, 2)
    }
}
