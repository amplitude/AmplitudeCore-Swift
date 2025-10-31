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
    func increment(name: String) async
    func increment(name: String, size: Int) async
    func recordHistogram(name: String, value: Double) async
    func recordEvent(name: String, properties: [String: any Sendable]?) async

    var isRunning: Bool { get }
    func observeIsRunning() -> (stream: AsyncStream<Bool>, id: UUID)
    func stopObservingIsRunning(_ id: UUID)
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

enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case dictionary([String: JSONValue])
    case null

    // Custom initializer to decode based on the JSON type
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Attempt to decode each type, in order of most specific to least
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let dictValue = try? container.decode([String: JSONValue].self) {
            self = .dictionary(dictValue)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self,
                                             DecodingError.Context(codingPath: decoder.codingPath,
                                                                   debugDescription: "Unknown JSON type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let str):
            try container.encode(str)
        case .int(let int):
            try container.encode(int)
        case .double(let dbl):
            try container.encode(dbl)
        case .bool(let bool):
            try container.encode(bool)
        case .array(let arr):
            try container.encode(arr)
        case .dictionary(let dict):
            try container.encode(dict)
        case .null:
            try container.encodeNil()
        }
    }

    // Helper to convert Any to JSONValue
    static func from(_ value: Any) -> JSONValue? {
        if let stringValue = value as? String {
            return .string(stringValue)
        } else if let boolValue = value as? Bool {
            return .bool(boolValue)
        } else if let intValue = value as? Int {
            return .int(intValue)
        } else if let doubleValue = value as? Double {
            return .double(doubleValue)
        } else if let floatValue = value as? Float {
            return .double(Double(floatValue))
        } else if let arrayValue = value as? [Any] {
            let jsonValues = arrayValue.compactMap { JSONValue.from($0) }
            return .array(jsonValues)
        } else if let dictValue = value as? [String: Any] {
            let jsonDict = dictValue.compactMapValues { JSONValue.from($0) }
            return .dictionary(jsonDict)
        }
        return nil
    }

    // Helper to convert JSONValue back to Any
    func toAny() -> any Sendable {
        switch self {
        case .string(let str):
            return str
        case .int(let int):
            return int
        case .double(let dbl):
            return dbl
        case .bool(let bool):
            return bool
        case .array(let arr):
            return arr.map { $0.toAny() }
        case .dictionary(let dict):
            return dict.mapValues { $0.toAny() }
        case .null:
            return NSNull()
        }
    }
}
