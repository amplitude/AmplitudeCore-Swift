//
//  CoreDiagnosticsClient.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 10/22/25.
//

import Foundation

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
@_spi(Internal)
public protocol CoreDiagnostics: Actor {
    func setTag(name: String, value: String) async
    func setTags(_ tags: [String: String]) async
    func increment(name: String, size: Int) async
    func recordHistogram(name: String, value: Double) async
    func recordEvent(name: String, properties: [String: any Sendable]?) async

    var isRunning: Bool { get }
    func observeIsRunning() -> (stream: AsyncStream<Bool>, id: UUID)
    func stopObservingIsRunning(_ id: UUID)
}

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
@_spi(Internal)
public extension CoreDiagnostics {

    func increment(name: String) async {
        await increment(name: name, size: 1)
    }

    nonisolated func setTag(name: String, value: String) {
        Task.detached {
            await self.setTag(name: name, value: value)
        }
    }

    nonisolated func setTags(_ tags: [String: String]) {
        Task.detached {
            await self.setTags(tags)
        }
    }

    nonisolated func increment(name: String, size: Int = 1) {
        Task.detached {
            await self.increment(name: name, size: size)
        }
    }

    nonisolated func recordHistogram(name: String, value: Double) {
        Task.detached {
            await self.recordHistogram(name: name, value: value)
        }
    }

    nonisolated func recordEvent(name: String, properties: [String: any Sendable]? = nil) {
        Task.detached {
            await self.recordEvent(name: name, properties: properties)
        }
    }
}

struct DiagnosticsEvent: Codable, Sendable {
    let eventName: String
    let time: TimeInterval
    let eventProperties: [String: any Sendable]?

    enum CodingKeys: String, CodingKey {
        case eventName
        case time
        case eventProperties
    }

    init(eventName: String, time: TimeInterval, eventProperties: [String: any Sendable]?) {
        self.eventName = eventName
        self.time = time
        self.eventProperties = eventProperties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventName = try container.decode(String.self, forKey: .eventName)
        time = try container.decode(TimeInterval.self, forKey: .time)
        let jsonValueDict = try container.decode([String: JSONValue].self, forKey: .eventProperties)
        eventProperties = jsonValueDict.mapValues { $0.toAny() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(time, forKey: .time)

        // Convert [String: Any] to [String: JSONValue] for encoding
        let jsonValueDict = eventProperties?.compactMapValues { JSONValue.from($0) }
        try container.encode(jsonValueDict, forKey: .eventProperties)
    }
}

struct HistogramStats: Codable {
    var count: Int
    var min: Double
    var max: Double
    var sum: Double

    init(count: Int = 0,
         min: Double = Double.infinity,
         max: Double = -Double.infinity,
         sum: Double = 0,
    ) {
        self.count = count
        self.min = min
        self.max = max
        self.sum = sum
    }
}

struct HistogramResult: Codable {
    let count: Int
    let min: Double
    let max: Double
    let avg: Double
}

struct DiagnosticsSnapshot: Sendable {
    let tags: [String: String]
    let counters: [String: Int]
    let histograms: [String: HistogramStats]
    let events: [DiagnosticsEvent]
}

struct DiagnosticsPayload: Codable {
    let tags: [String: String]
    let counters: [String: Int]
    let histogram: [String: HistogramResult]
    let events: [DiagnosticsEvent]
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
protocol StorageOutputStream: Sendable {
    func write(_ data: Data) throws
    func close() throws
}
