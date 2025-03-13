//
//  UniversalPlugin.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/12/25.
//

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol UniversalPlugin: AnyObject {

    var name: String? { get }

    func setup(analyticsClient: any AnalyticsClient, amplitudeContext: AmplitudeContext)
    func execute<Event: AnalyticsEvent>(_ event: inout Event)
    func teardown()

    func onIdentityChanged(_ identity: AnalyticsIdentity)
    func onSessionIdChanged(_ sessionId: Int64)
    func onOptOutChanged(_ optOut: Bool)
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension UniversalPlugin {

    var name: String? {
        return nil
    }

    func setup(analyticsClient: any AnalyticsClient, amplitudeContext: AmplitudeContext) {}
    func execute<Event: AnalyticsEvent>(_ event: inout Event) {}
    func teardown() {}

    func onIdentityChanged(_ identity: AnalyticsIdentity) {}
    func onSessionIdChanged(_ sessionId: Int64) {}
    func onOptOutChanged(_ optOut: Bool) {}
}
