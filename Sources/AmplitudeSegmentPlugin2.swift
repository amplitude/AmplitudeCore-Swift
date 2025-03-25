//
//  AmplitudeSegmentPlugin2.swift
//  SegmentUnified
//
//  Created by Chris Leonavicius on 3/14/25.
//

import AmplitudeCore
import Combine
import Foundation
import Segment
import UIKit

public class AmplitudeSegmentPlugin2: Segment.Plugin, PluginHost {

    private let context: AmplitudeContext
    private let analyticsWrapper = AnalyticsWrapper()
    private let timeline = Timeline()

    private var cancellables = Set<AnyCancellable>()

    init(apiKey: String, serverZone: ServerZone = .US) {
        let logger = ConsoleLogger(logLevel: .DEBUG)
        let remoteConfigClient = RemoteConfigClient(apiKey: apiKey,
                                                    serverZone: serverZone,
                                                    logger: logger)
        context = AmplitudeContext(apiKey: apiKey,
                                            serverZone: serverZone,
                                            remoteConfigClient: remoteConfigClient,
                                            logger: logger)

        analyticsWrapper.userId.sink { [weak self] userId in
            self?.timeline.execute {
                $0.onUserIdChanged(userId)
            }
        }
        .store(in: &cancellables)

        analyticsWrapper.sessionId.sink { [weak self] sessionId in
            self?.timeline.execute {
                $0.onSessionIdChanged(sessionId ?? -1)
            }
        }
        .store(in: &cancellables)
        
        analyticsWrapper.deviceId.sink { [weak self] deviceId in
            self?.timeline.execute {
                $0.onDeviceIdChanged(deviceId ?? "")
            }
        }
        .store(in: &cancellables)
    }

    // MARK: - Segment.Plugin

    public var type: Segment.PluginType {
        return .enrichment
    }

    public var analytics: Segment.Analytics?

    public func configure(analytics: Analytics) {
        self.analytics = analytics
        analyticsWrapper.wrappedAnalytics = analytics
    }

    public func update(settings: Settings, type: UpdateType) {

    }

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event else {
            return nil
        }

        var wrappedEvent = EventWrapper(event)

        if analyticsWrapper.userId.value != wrappedEvent.userId {
            analyticsWrapper.userId.send(wrappedEvent.userId)
        }

        if analyticsWrapper.deviceId.value != wrappedEvent.deviceId {
            analyticsWrapper.deviceId.send(wrappedEvent.deviceId)
        }

        if analyticsWrapper.sessionId.value != wrappedEvent.sessionId {
            analyticsWrapper.sessionId.send(wrappedEvent.sessionId)
        }

        timeline.execute {
            $0.execute(&wrappedEvent)
        }

        // copy back properties to original event
        let updatedEvent: T
        let updatedProperties = try? JSON(nilOrObject: wrappedEvent.eventProperties)
        switch event {
        case var trackEvent as TrackEvent:
            trackEvent.properties = updatedProperties
            updatedEvent = trackEvent as? T ?? event
        case var screenEvent as ScreenEvent:
            screenEvent.properties = updatedProperties
            updatedEvent = screenEvent as? T ?? event
        default:
            updatedEvent = event
        }

        return updatedEvent
    }

    public func shutdown() {
        timeline.execute {
            $0.teardown()
        }
    }

    // MARK: - PluginHost

    public func add(plugin: UniversalPlugin) {
        plugin.setup(analyticsClient: analyticsWrapper, amplitudeContext: context)
        timeline.add(plugin: plugin)
    }

    public func remove(plugin: UniversalPlugin) {
        timeline.remove(plugin: plugin)
    }

    public func plugin(name: String) -> (any AmplitudeCore.UniversalPlugin)? {
        return timeline.plugin(name: name)
    }
}

// MARK: - AnalyticsWrapper

private class AnalyticsWrapper: AnalyticsClient {

    let userId = CurrentValueSubject<String?, Never>(nil)
    let sessionId = CurrentValueSubject<Int64?, Never>(nil)
    let deviceId = CurrentValueSubject<String?, Never>(nil)

    private var pendingTracks: [(eventType: String, eventProperties: [String: Any]?)] = []

    var wrappedAnalytics: Analytics? = nil {
        didSet {
            if let wrappedAnalytics {
                pendingTracks.forEach {
                    wrappedAnalytics.track(name: $0.eventType, properties: $0.eventProperties)
                }
                pendingTracks.removeAll()
            }
        }
    }

    func track(eventType: String, eventProperties: [String : Any]?) -> Self {
        if let wrappedAnalytics {
            wrappedAnalytics.track(name: eventType, properties: eventProperties)
        } else {
            pendingTracks.append((eventType: eventType, eventProperties: eventProperties))
        }
        return self
    }
    
    func getUserId() -> String? {
        return userId.value
    }
    
    func getDeviceId() -> String? {
        return deviceId.value
    }
    
    func getSessionId() -> Int64 {
        return sessionId.value ?? -1
    }

}

// MARK: - EventWrapper

private class EventWrapper: AnalyticsEvent {

    private static let dateFormatter = ISO8601DateFormatter()

    let userId: String?
    let deviceId: String?
    let timestamp: Int64?
    let sessionId: Int64?
    let eventType: String
    var eventProperties: [String: Any]?

    init(_ event: RawEvent) {
        let propertiesJson: JSON?
        switch event {
        case let trackEvent as TrackEvent:
            propertiesJson = trackEvent.properties
        case let screenEvent as ScreenEvent:
            propertiesJson = screenEvent.properties
        default:
            propertiesJson = nil
        }
        eventProperties = propertiesJson?.dictionaryValue

        userId = event.userId
        deviceId = UIDevice.current.identifierForVendor?.uuidString // TODO
        timestamp = event.timestamp
            .flatMap { Self.dateFormatter.date(from: $0)?.timeIntervalSince1970 }
            .map { Int64($0 * 1000) }
        if let actionsSessionId = event.integrations?["Actions Amplitude"]?["session_id"]?.intValue {
            sessionId = Int64(actionsSessionId)
        } else if let propertiesSessionId = eventProperties?["session_id"] as? Int64 {
            sessionId = propertiesSessionId
        } else {
            sessionId = nil
        }
        eventType = event.type ?? ""
    }
}

// MARK: - Timeline

private class Timeline {

    private let lock = NSLock()
    private var plugins: [UniversalPlugin] = []
    private var pluginsByName: [String: UniversalPlugin] = [:]

    func add(plugin: UniversalPlugin) {
        lock.withLock {
            plugins.append(plugin)
            if let name = plugin.name {
                pluginsByName[name] = plugin
            }
        }
    }

    func remove(plugin: UniversalPlugin) {
        lock.withLock {
            plugins.removeAll { plugin === $0 }
            pluginsByName = pluginsByName.filter {
                $0.value === plugin
            }
        }
    }

    func plugin(name: String) -> UniversalPlugin? {
        lock.withLock {
            return pluginsByName[name]
        }
    }

    func execute(block: (UniversalPlugin) -> Void) {
        let plugins = lock.withLock {
            self.plugins
        }

        plugins.forEach {
            block($0)
        }
    }
}
