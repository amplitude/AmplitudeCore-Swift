//
//  AmplitudeSegmentPlugin.swift
//  SegmentUnified
//
//  Created by Chris Leonavicius on 3/13/25.
//

import AdSupport
import AppTrackingTransparency
import AmplitudeCore
import Foundation
import Segment
import UIKit

public class AmplitudeSegmentPlugin: Segment.Plugin, PluginHost {

    private let amplitudeContext: AmplitudeContext
    private var analyticsClient: MockSegmentAnalyticsClient?

    private var settings: AmplitudeSettings?

    private var plugins: [UniversalPlugin] = []

    private var queuedPlugins: [UniversalPlugin] = []

    public var type: PluginType {
        return .enrichment
    }

    init(apiKey: String, serverZone: ServerZone = .US) {
        let logger = ConsoleLogger(logLevel: .DEBUG)
        let remoteConfigClient = RemoteConfigClient(apiKey: apiKey,
                                                    serverZone: serverZone,
                                                    logger: logger)
        amplitudeContext = AmplitudeContext(apiKey: apiKey,
                                            serverZone: serverZone,
                                            remoteConfigClient: remoteConfigClient,
                                            logger: logger)
    }


    public var analytics: Analytics? = nil {
        didSet {
            plugins.forEach {
                $0.teardown()
            }

            guard let analytics else {
                return
            }

            let analyticsClient = MockSegmentAnalyticsClient(analytics)
            self.analyticsClient = analyticsClient

            plugins.forEach {
                $0.setup(analyticsClient: analyticsClient, amplitudeContext: amplitudeContext)
            }

            queuedPlugins.forEach {
                $0.setup(analyticsClient: analyticsClient, amplitudeContext: amplitudeContext)
                plugins.append($0)
            }
            queuedPlugins.removeAll()
        }
    }

    public func configure(analytics: Analytics) {
        self.analytics = analytics
    }

    public func update(settings: Settings, type: UpdateType) {
        guard let amplitudeSettings = settings.integrationSettings(forKey: "Amplitude") else {
            return
        }

        let preferAnonymousIdForDeviceId = amplitudeSettings["preferAnonymousIdForDeviceId"] as? Bool ?? false
        let useAdvertisingIdForDeviceId = amplitudeSettings["useAdvertisingIdForDeviceId"] as? Bool ?? false
        self.settings = AmplitudeSettings(preferAnonymousIdForDeviceId: preferAnonymousIdForDeviceId,
                                          useAdvertisingIdForDeviceId: useAdvertisingIdForDeviceId)
    }

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event else {
            return nil
        }
        var eventWrapper = EventWrapper(event, settings: settings)

        // Update device / user / session id from events, since we can't access internal data
        if let analyticsClient = analyticsClient {
            let sessionId = eventWrapper.sessionId ?? -1
            if sessionId != analyticsClient.sessionId {
                analyticsClient.sessionId = sessionId
                plugins.forEach {
                    $0.onSessionIdChanged(sessionId)
                }
            }

            let deviceId = eventWrapper.deviceId
            if deviceId != analyticsClient.deviceId {
                analyticsClient.deviceId = deviceId
                plugins.forEach {
                    $0.onDeviceIdChanged(deviceId)
                }
            }
            
            let userId = eventWrapper.userId
            if userId != analyticsClient.userId {
                analyticsClient.userId = userId
                plugins.forEach {
                    $0.onUserIdChanged(userId)
                }
            }
        }

        plugins.forEach {
            $0.execute(&eventWrapper)
        }
        return eventWrapper.event
    }

    public func shutdown() {
        plugins.forEach {
            $0.teardown()
        }
    }

    public func add(plugin: UniversalPlugin) {
        guard let analyticsClient else {
            queuedPlugins.append(plugin)
            return
        }

        plugin.setup(analyticsClient: analyticsClient, amplitudeContext: amplitudeContext)
        plugins.append(plugin)
    }

    public func remove(plugin: UniversalPlugin) {
        plugins.removeAll {
            if $0 === plugin {
                $0.teardown()
                return true
            }
            return false
        }
        queuedPlugins.removeAll {
            $0 === plugin
        }
    }

    public func plugin(name: String) -> UniversalPlugin? {
        return nil

    }
}

// MARK: - EventWrapper

private class EventWrapper<EventType: RawEvent>: AnalyticsEvent {

    private var settings: AmplitudeSettings?

    var userId: String? {
        return event.userId
    }

    var deviceId: String? {
        if let settings {
            if settings.preferAnonymousIdForDeviceId {
                return event.anonymousId
            }
            if settings.useAdvertisingIdForDeviceId {
                switch ATTrackingManager.trackingAuthorizationStatus {
                case .authorized:
                    return ASIdentifierManager.shared().advertisingIdentifier.uuidString
                default:
                    return nil
                }
            }
        }

        return UIDevice.current.identifierForVendor?.uuidString
    }

    var timestamp: Int64? {
        return event.timestamp
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            .flatMap { Int64($0.timeIntervalSince1970 * 1000) }
    }

    var sessionId: Int64? {
        if let sessionId = event.integrations?["Actions Amplitude"]?["session_id"]?.intValue {
            return Int64(sessionId)
        }

        if let sessionId = eventProperties?["session_id"] as? Int64 {
            return sessionId
        }

        return nil
    }

    var eventType: String {
        return event.type ?? ""
    }

    var eventProperties: [String : Any]? {
        get {
            let properties: JSON?
            switch event {
            case let trackEvent as TrackEvent:
                properties = trackEvent.properties
            case let screenEvent as ScreenEvent:
                properties = screenEvent.properties
            default:
                properties = nil
            }
            return properties?.dictionaryValue
        }
        set {
            do {
                let properties = try JSON(nilOrObject: newValue)
                switch event {
                case var trackEvent as TrackEvent:
                    trackEvent.properties = properties
                    event = trackEvent as? EventType ?? event
                case var screenEvent as ScreenEvent:
                    screenEvent.properties = properties
                    event = screenEvent as? EventType ?? event
                default:
                    break
                }
            } catch {
                // TODO
            }
        }
    }

    var event: EventType

    init(_ event: EventType, settings: AmplitudeSettings?) {
        self.event = event
        self.settings = settings
    }
}

// MARK: - SegmentAnalyticsWrapper

private class MockSegmentAnalyticsClient: AnalyticsClient {

    private let analytics: Analytics

    init(_ analytics: Analytics) {
        self.analytics = analytics
    }

    var userId: String?
    var deviceId: String?
    var sessionId: Int64 = -1

    func track(eventType: String, eventProperties: [String : Any]?) -> Self {
        analytics.track(name: eventType, properties: eventProperties as? [String: Encodable & Decodable])
        return self
    }
    
    func getUserId() -> String? {
        return userId
    }
    
    func getDeviceId() -> String? {
        return deviceId
    }
    
    func getSessionId() -> Int64 {
        return sessionId
    }
}

private struct AmplitudeSettings {
    let preferAnonymousIdForDeviceId: Bool
    let useAdvertisingIdForDeviceId: Bool
}
