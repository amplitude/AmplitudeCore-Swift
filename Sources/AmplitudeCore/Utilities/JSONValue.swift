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

    /// Converts a Foundation or Swift value into a `JSONValue`.
    ///
    /// Numbers are classified by their Core Foundation type instead of Swift casts. A bridged
    /// `NSNumber` (from `JSONSerialization`, Objective-C, or cross-platform bridges such as Flutter
    /// and React Native) succeeds `as? Bool` for any `0` or `1` and `as? Int` for whole doubles,
    /// so cast order alone cannot tell `1`, `1.0` and `true` apart. A Float or a decimal number keeps the digits
    /// it is written with (0.1, not 0.10000000149011612), as JSONEncoder writes it.
    ///
    /// Returns `nil` for values JSON cannot represent, such as non-finite numbers or unsupported
    /// types. Collections drop such elements.
    public static func from(_ value: Any) -> JSONValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            return from(number: number)
        case is NSNull:
            return .null
        case let array as [Any]:
            return .array(array.compactMap { JSONValue.from($0) })
        case let dictionary as [String: Any]:
            return .dictionary(dictionary.compactMapValues { JSONValue.from($0) })
        default:
            return nil
        }
    }

    private static func from(number: NSNumber) -> JSONValue? {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        // NSDecimalNumber (and bridged Decimal) always reports a floating-point type,
        // so keep its integral values as ints.
        let isFloatingPoint = !(number is NSDecimalNumber) && CFNumberIsFloatType(number)
        if !isFloatingPoint, let intValue = Int(exactly: number) {
            return .int(intValue)
        }
        let doubleValue = number.digitPreservingDoubleValue
        return doubleValue.isFinite ? .double(doubleValue) : nil
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
