//
//  UniversalPlugin.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/12/25.
//

public protocol UniversalPlugin: AnyObject {

    var name: String? { get }

    func setup(analyticsClient: AnalyticsClient, amplitudeContext: AmplitudeContext)
    func execute<Event: AnalyticsEvent>(_ event: inout Event)
    func teardown()
    func onUserIdChanged(_ userId: String?)
    func onDeviceIdChanged(_ deviceId: String?)
    func onSessionIdChanged(_ sessionId: Int64)
    func onOptOutChanged(_ optOut: Bool)
}
