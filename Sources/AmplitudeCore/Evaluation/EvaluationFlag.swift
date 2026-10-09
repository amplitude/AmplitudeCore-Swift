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
    let metadata: [String: Any?]?
}

struct EvaluationSegment: Codable {
    let bucket: EvaluationBucket?
    let conditions: [[EvaluationCondition]]?
    let variant: String?
    let metadata: [String: Any?]?
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
    let value: Any?
    let payload: Any?
    /// The flag's, the matched segment's and the variant's metadata, merged in that order.
    public let metadata: [String: Any?]?
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
        switch selector {
        case "key": return key
        case "value": return value
        case "payload": return payload
        case "metadata": return metadata
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
        let metadata = try? container.decode([String: AnyDecodable].self, forKey: .metadata)
        self.metadata = metadata?.mapValues { anyDecodable in anyDecodable.value }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(variants, forKey: .variants)
        try container.encode(segments, forKey: .segments)
        if let metadata {
            try? container.encodeIfPresent(AnyEncodable(metadata), forKey: .metadata)
        }
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
        self.bucket = try? container.decode(EvaluationBucket.self, forKey: .bucket)
        self.conditions = try? container.decode([[EvaluationCondition]].self, forKey: .conditions)
        self.variant = try? container.decode(String.self, forKey: .variant)
        let metadata = try? container.decode([String: AnyDecodable].self, forKey: .metadata)
        self.metadata = metadata?.mapValues { anyDecodable in anyDecodable.value }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encodeIfPresent(bucket, forKey: .bucket)
        try? container.encodeIfPresent(conditions, forKey: .conditions)
        try? container.encodeIfPresent(variant, forKey: .variant)
        if let metadata {
            try? container.encodeIfPresent(AnyEncodable(metadata), forKey: .metadata)
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
        self.value = try? container.decode(AnyDecodable.self, forKey: .value).value
        self.payload = try? container.decode(AnyDecodable.self, forKey: .payload).value
        let metadata = try? container.decode([String: AnyDecodable].self, forKey: .metadata)
        self.metadata = metadata?.mapValues { anyDecodable in anyDecodable.value }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encodeIfPresent(key, forKey: .key)
        if let value {
            try? container.encodeIfPresent(AnyEncodable(value), forKey: .value)
        }
        if let payload {
            try? container.encodeIfPresent(AnyEncodable(payload), forKey: .payload)
        }
        if let metadata {
            try? container.encodeIfPresent(AnyEncodable(metadata), forKey: .metadata)
        }
    }
}
