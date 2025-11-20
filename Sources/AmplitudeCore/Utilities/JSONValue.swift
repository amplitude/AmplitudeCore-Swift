//
//  JSONValue.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/19/25.
//

import Foundation

public enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case dictionary([String: JSONValue])
    case null

    // Custom initializer to decode based on the JSON type
    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
    public static func from(_ value: Any) -> JSONValue? {
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
    public func toAny() -> any Sendable {
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
