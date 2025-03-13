//
//  AnalyticsIdentity.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/25/25.
//

public protocol AnalyticsIdentity {
    var deviceId: String? { get }
    var userId: String? { get }
    var userProperties: [String: Any] { get }
}
