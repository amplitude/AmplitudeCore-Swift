//
//  AnalyticsEventSnapshot.swift
//  AmplitudeCore
//

import Foundation

@_spi(Internal)
public protocol EncodableAnalyticsEvent: AnalyticsEvent, Encodable {}

/// A Codable representation of the fields guaranteed by ``AnalyticsEvent``.
///
/// This deliberately excludes concrete SDK-specific event fields so plugins can
/// serialize events from any analytics host consistently.
struct AnalyticsEventSnapshot: EncodableAnalyticsEvent, Decodable {
    let eventType: String
    let userId: String?
    let deviceId: String?
    let timestamp: Int64?
    let sessionId: Int64?
    var eventProperties: [String: Any]?

    init(userId: String? = nil,
         deviceId: String? = nil,
         timestamp: Int64? = nil,
         sessionId: Int64? = nil,
         eventType: String,
         eventProperties: [String: Any]? = nil) {
        self.userId = userId
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.eventType = eventType
        self.eventProperties = eventProperties
    }

    init(event: any AnalyticsEvent) {
        self.init(userId: event.userId,
                  deviceId: event.deviceId,
                  timestamp: event.timestamp,
                  sessionId: event.sessionId,
                  eventType: event.eventType,
                  eventProperties: event.eventProperties)
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case userId = "user_id"
        case deviceId = "device_id"
        case timestamp = "time"
        case sessionId = "session_id"
        case eventProperties = "event_properties"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventType = try container.decode(String.self, forKey: .eventType)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp)
        sessionId = try container.decodeIfPresent(Int64.self, forKey: .sessionId)
        eventProperties = try container.decodeIfPresent([String: Any].self, forKey: .eventProperties)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventType, forKey: .eventType)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(deviceId, forKey: .deviceId)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeAny(eventProperties, forKey: .eventProperties)
    }
}

@_spi(Internal)
public extension AnalyticsEvent {
    func encodableSnapshot() -> any EncodableAnalyticsEvent {
        if let snapshot = self as? AnalyticsEventSnapshot {
            return snapshot
        }

        return AnalyticsEventSnapshot(event: self)
    }
}
