//
//  EvaluationFlag.swift
//  AmplitudeCore
//
//  Created by Brian Giori on 9/11/23.
//  Ported from experiment-ios-client v1.20.3 (Sources/Experiment/EvaluationFlag.swift).
//

import Foundation

@_spi(Internal)
public struct EvaluationFlag: Codable {
    let key: String
    let variants: [String: EvaluationVariant]
    let segments: [EvaluationSegment]
    let metadata: [String: JSONValue]?
}

struct EvaluationSegment: Codable {
    let bucket: EvaluationBucket?
    let conditions: [[EvaluationCondition]]?
    let variant: String?
    let metadata: [String: JSONValue]?
}

struct EvaluationBucket: Codable {
    let selector: [String]
    let salt: String
    let allocations: [EvaluationAllocation]
}

struct EvaluationCondition: Codable {
    let selector: [String]
    let op: String
    let values: Set<String>
}

struct EvaluationAllocation: Codable {
    let range: [Int]
    let distributions: [EvaluationDistribution]
}

struct EvaluationDistribution: Codable {
    let variant: String
    let range: [Int]
}

@_spi(Internal)
public struct EvaluationVariant: Codable, Selectable {
    public let key: String?
    let value: JSONValue?
    let payload: JSONValue?
    /// The flag's, the matched segment's and the variant's metadata, merged in that order.
    public let metadata: [String: JSONValue]?
}

enum EvaluationOperator {
    static let IS = "is"
    static let IS_NOT = "is not"
    static let CONTAINS = "contains"
    static let DOES_NOT_CONTAIN = "does not contain"
    static let LESS_THAN = "less"
    static let LESS_THAN_EQUALS = "less or equal"
    static let GREATER_THAN = "greater"
    static let GREATER_THAN_EQUALS = "greater or equal"
    static let VERSION_LESS_THAN = "version less"
    static let VERSION_LESS_THAN_EQUALS = "version less or equal"
    static let VERSION_GREATER_THAN = "version greater"
    static let VERSION_GREATER_THAN_EQUALS = "version greater or equal"
    static let SET_IS = "set is"
    static let SET_IS_NOT = "set is not"
    static let SET_CONTAINS = "set contains"
    static let SET_DOES_NOT_CONTAIN = "set does not contain"
    static let SET_CONTAINS_ANY = "set contains any"
    static let SET_DOES_NOT_CONTAIN_ANY = "set does not contain any"
    static let REGEX_MATCH = "regex match"
    static let REGEX_DOES_NOT_MATCH = "regex does not match"
}

// Selectable Extensions

extension EvaluationVariant {

    func select(selector: String) -> Any? {
        // A condition on another flag's result reads plain values, as it does from the context.
        switch selector {
        case "key": return key
        case "value": return value?.toAny()
        case "payload": return payload?.toAny()
        case "metadata": return metadata?.mapValues { $0.toAny() }
        default: return nil
        }
    }
}

// Codable Extensions

extension EvaluationFlag {

    enum CodingKeys: CodingKey {
        case key
        case variants
        case segments
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.variants = try container.decode([String: EvaluationVariant].self, forKey: .variants)
        self.segments = try container.decode([EvaluationSegment].self, forKey: .segments)
        self.metadata = try? container.decode([String: JSONValue].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(variants, forKey: .variants)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

extension EvaluationSegment {

    enum CodingKeys: CodingKey {
        case bucket
        case conditions
        case variant
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Absent or null means none, but a malformed value fails decoding: silently dropping malformed
        // conditions would make the segment match everyone.
        self.bucket = try container.decodeIfPresent(EvaluationBucket.self, forKey: .bucket)
        self.conditions = try container.decodeIfPresent([[EvaluationCondition]].self, forKey: .conditions)
        self.variant = try container.decodeIfPresent(String.self, forKey: .variant)
        self.metadata = try? container.decode([String: JSONValue].self, forKey: .metadata)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encodeIfPresent(bucket, forKey: .bucket)
        try? container.encodeIfPresent(conditions, forKey: .conditions)
        try? container.encodeIfPresent(variant, forKey: .variant)
        try? container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

extension EvaluationCondition {

    enum CodingKeys: CodingKey {
        case selector
        case op
        case values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selector = try container.decode([String].self, forKey: .selector)
        self.op = try container.decode(String.self, forKey: .op)
        self.values = try container.decode(Set<String>.self, forKey: .values)
        // Without a selector the condition reads a missing property, so negated operators would match everyone.
        if selector.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .selector, in: container, debugDescription: "Empty selector")
        }
    }
}

extension EvaluationVariant {

    enum CodingKeys: CodingKey {
        case key
        case value
        case payload
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try? container.decode(String.self, forKey: .key)
        self.value = try? container.decodeIfPresent(JSONValue.self, forKey: .value)
        self.payload = try? container.decodeIfPresent(JSONValue.self, forKey: .payload)
        self.metadata = try? container.decode([String: JSONValue].self, forKey: .metadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encodeIfPresent(key, forKey: .key)
        try? container.encodeIfPresent(value, forKey: .value)
        try? container.encodeIfPresent(payload, forKey: .payload)
        try? container.encodeIfPresent(metadata, forKey: .metadata)
    }
}
