//
//  AnalyticsEvent.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/11/25.
//

public protocol AnalyticsEvent: AnyObject {
    var userId: String? { get }
    var deviceId: String? { get }
    var timestamp: Int64? { get }
    var sessionId: Int64? { get }
    var eventType: String { get }
    var eventProperties: [String: Any]? { get set }
}
