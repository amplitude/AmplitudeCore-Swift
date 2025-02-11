//
//  Plugin.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

import Foundation

@objc(AMPPluginType)
public enum PluginType: Int, CaseIterable {
    case before
    case enrichment
    case destination
    case utility
}

public protocol Plugin: AnyObject {
    var type: PluginType { get }
    var name: String? { get }
    func setup(analyticsClient: any AnalyticsClient)
    func execute(event: BaseEvent) -> BaseEvent?
    func teardown()
    func onUserIdChanged(_ userId: String?)
    func onDeviceIdChanged(_ deviceId: String?)
    func onSessionIdChanged(_ sessionId: Int64)
    func onOptOutChanged(_ optOut: Bool)
}

public extension Plugin {

    var name: String? {
        return nil
    }

    // default behavior
    func execute(event: BaseEvent) -> BaseEvent? {
        return event
    }

    func setup(anaylticsClient: any AnalyticsClient) {
    }

    func teardown(){
        // Clean up any resources from setup if necessary
    }

    func onUserIdChanged(_ userId: String?) {}
    func onDeviceIdChanged(_ deviceId: String?) {}
    func onSessionIdChanged(_ sessionId: Int64) {}
    func onOptOutChanged(_ optOut: Bool) {}
}
