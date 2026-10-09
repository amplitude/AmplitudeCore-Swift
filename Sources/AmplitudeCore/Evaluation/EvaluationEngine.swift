//
//  EvaluationEngine.swift
//  AmplitudeCore
//
//  Created by Brian Giori on 9/11/23.
//  Ported from experiment-ios-client v1.20.3 (Sources/Experiment/EvaluationEngine.swift).
//

import Foundation

@_spi(Internal)
public final class EvaluationEngine: Sendable {

    public init() {}

    struct EvaluationTarget: Selectable {
        let context: [String: Any?]
        var result: [String: EvaluationVariant]

        func select(selector: String) -> Any? {
            switch selector {
            case "context": return context
            case "result": return result
            default: return nil
            }
        }
    }

    public func evaluate(context: [String: Any?], flags: [EvaluationFlag]) -> [String: EvaluationVariant] {
        var results: [String: EvaluationVariant] = [:]
        var target = EvaluationTarget(context: context, result: results)
        for flag in flags {
            if let variant = evaluateFlag(target: target, flag: flag) {
                results[flag.key] = variant
                target.result = results
            }
        }
        return results
    }

    private func evaluateFlag(target: EvaluationTarget, flag: EvaluationFlag) -> EvaluationVariant? {
        var result: EvaluationVariant?
        for segment in flag.segments {
            if let segmentResult = evaluateSegment(target: target, flag: flag, segment: segment) {
                // Merge all metadata into the result
                let metadata = mergeMetadata(flag.metadata, segment.metadata, segmentResult.metadata)
                result = EvaluationVariant(key: segmentResult.key, value: segmentResult.value, payload: segmentResult.payload, metadata: metadata)
                break
            }
        }
        return result
    }

    private func evaluateSegment(target: EvaluationTarget, flag: EvaluationFlag, segment: EvaluationSegment) -> EvaluationVariant? {
        guard let segmentConditions = segment.conditions else {
            // Null conditions always match
            guard let variantKey = bucket(target: target, segment: segment) else {
                return nil
            }
            return flag.variants[variantKey]
        }
        // Outer logic is "or" (||)
        for conditions in segmentConditions {
            var match = true
            // Inner list logic is "and" (&&)
            for condition in conditions {
                match = matchCondition(target: target, condition: condition)
                if !match {
                    break
                }
            }
            if match {
                guard let variantKey = bucket(target: target, segment: segment) else {
                    return nil
                }
                return flag.variants[variantKey]
            }
        }
        return nil
    }

    private func matchCondition(target: EvaluationTarget, condition: EvaluationCondition) -> Bool {
        let propValue = target.select(selector: condition.selector)
        if propValue == nil {
            return matchNull(op: condition.op, filterValues: condition.values)
        }
        let propValueStringList = coerceStringList(value: propValue)
        if isSetOperator(op: condition.op) {
            guard let propValueStringList else {
                return false
            }
            return matchSet(propValues: propValueStringList, op: condition.op, filterValues: condition.values)
        }
        if let propValueStringList {
            return matchStringsNonSet(propValues: propValueStringList, op: condition.op, filterValues: condition.values)
        }
        guard let propValueString = coerceString(value: propValue) else {
            return false
        }
        return matchString(propValue: propValueString, op: condition.op, filterValues: condition.values)
    }

    private func getHash(key: String) -> Int64 {
        let data = key.data(using: .utf8) ?? Data()
        let hash = data.murmurHash32x86(seed: 0)
        return Int64(hash) & 0xffffffff
    }

    private func bucket(target: EvaluationTarget, segment: EvaluationSegment) -> String? {
        guard let segmentBucket = segment.bucket else {
            // A null bucket means the segment is fully rolled out. Select the default variant.
            return segment.variant
        }
        // Select the bucketing value.
        let bucketingValue = coerceString(value: target.select(selector: segmentBucket.selector))
        // A null or empty bucketing value cannot be bucketed. Select the default variant.
        guard let bucketingValue else {
            return segment.variant
        }
        if bucketingValue.isEmpty {
            return segment.variant
        }
        // Salt and hash the value, and compute the allocation and distribution values.
        let keyToHash = "\(segmentBucket.salt)/\(bucketingValue)"
        let hash = getHash(key: keyToHash)
        let allocationValue = hash % 100
        let distributionValue = hash / 100
        // Ranges are compared rather than turned into a Range, so that a short or reversed range from remote
        // config does not match instead of trapping, as in the JS and Kotlin engines.
        for allocation in segmentBucket.allocations {
            guard contains(range: allocation.range, value: allocationValue) else {
                continue
            }
            for distribution in allocation.distributions where contains(range: distribution.range, value: distributionValue) {
                return distribution.variant
            }
        }
        return segment.variant
    }

    private func contains(range: [Int], value: Int64) -> Bool {
        guard range.count >= 2 else {
            return false
        }
        return value >= Int64(range[0]) && value < Int64(range[1])
    }

    private func matchNull(op: String, filterValues: Set<String>) -> Bool {
        let containsNone = containsNone(filterValues: filterValues)
        switch op {
        case EvaluationOperator.IS, EvaluationOperator.CONTAINS, EvaluationOperator.LESS_THAN,
            EvaluationOperator.LESS_THAN_EQUALS, EvaluationOperator.GREATER_THAN,
            EvaluationOperator.GREATER_THAN_EQUALS, EvaluationOperator.VERSION_LESS_THAN,
            EvaluationOperator.VERSION_LESS_THAN_EQUALS, EvaluationOperator.VERSION_GREATER_THAN,
            EvaluationOperator.VERSION_GREATER_THAN_EQUALS, EvaluationOperator.SET_IS,
            EvaluationOperator.SET_CONTAINS, EvaluationOperator.SET_CONTAINS_ANY: return containsNone
        case EvaluationOperator.IS_NOT, EvaluationOperator.DOES_NOT_CONTAIN,
            EvaluationOperator.SET_DOES_NOT_CONTAIN, EvaluationOperator.SET_DOES_NOT_CONTAIN_ANY: return !containsNone
        case EvaluationOperator.REGEX_MATCH: return false
        case EvaluationOperator.REGEX_DOES_NOT_MATCH, EvaluationOperator.SET_IS_NOT: return true
        default: return false
        }
    }

    private func matchSet(propValues: Set<String>, op: String, filterValues: Set<String>) -> Bool {
        switch op {
        case EvaluationOperator.SET_IS: return propValues == filterValues
        case EvaluationOperator.SET_IS_NOT: return propValues != filterValues
        case EvaluationOperator.SET_CONTAINS: return matchesSetContainsAll(propValues: propValues, filterValues: filterValues)
        case EvaluationOperator.SET_DOES_NOT_CONTAIN: return !matchesSetContainsAll(propValues: propValues, filterValues: filterValues)
        case EvaluationOperator.SET_CONTAINS_ANY: return matchesSetContainsAny(propValues: propValues, filterValues: filterValues)
        case EvaluationOperator.SET_DOES_NOT_CONTAIN_ANY: return !matchesSetContainsAny(propValues: propValues, filterValues: filterValues)
        default: return false
        }
    }

    private func matchString(propValue: String, op: String, filterValues: Set<String>) -> Bool {
        switch op {
        case EvaluationOperator.IS: return matchesIs(propValue: propValue, filterValues: filterValues)
        case EvaluationOperator.IS_NOT: return !matchesIs(propValue: propValue, filterValues: filterValues)
        case EvaluationOperator.CONTAINS: return matchesContains(propValue: propValue, filterValues: filterValues)
        case EvaluationOperator.DOES_NOT_CONTAIN: return !matchesContains(propValue: propValue, filterValues: filterValues)
        case EvaluationOperator.LESS_THAN, EvaluationOperator.LESS_THAN_EQUALS, EvaluationOperator.GREATER_THAN, EvaluationOperator.GREATER_THAN_EQUALS:
            return matchesNumber(propValue: propValue, op: op, filterValues: filterValues)
        case EvaluationOperator.VERSION_LESS_THAN, EvaluationOperator.VERSION_LESS_THAN_EQUALS, EvaluationOperator.VERSION_GREATER_THAN, EvaluationOperator.VERSION_GREATER_THAN_EQUALS:
            return matchesComparable(propValue: propValue, op: op, filterValues: filterValues) { value in
                return SemanticVersion.parse(version: value)
            }
        case EvaluationOperator.REGEX_MATCH: return matchesRegex(propValue: propValue, filterValues: filterValues)
        case EvaluationOperator.REGEX_DOES_NOT_MATCH: return !matchesRegex(propValue: propValue, filterValues: filterValues)
        default: return false
        }
    }

    private func matchStringsNonSet(propValues: Set<String>, op: String, filterValues: Set<String>) -> Bool {
        return propValues.contains { element in
            matchString(propValue: element, op: op, filterValues: filterValues)
        }
    }

    private func matchesIs(propValue: String, filterValues: Set<String>) -> Bool {
        if containsBooleans(filterValues: filterValues) {
            let lower = propValue.lowercased()
            if lower == "true" || lower == "false" {
                return filterValues.contains { $0.lowercased() == lower }
            }
        }
        return filterValues.contains(propValue)
    }

    private func matchesContains(propValue: String, filterValues: Set<String>) -> Bool {
        for filterValue in filterValues where propValue.lowercased().contains(filterValue.lowercased()) {
            return true
        }
        return false
    }

    /// Numeric operators compare numbers only: a value that is not a number never matches, as in JS, where it
    /// becomes NaN. Falling back to comparing strings, as the version operators do, would make "N/A" greater
    /// than 100, since letters sort after digits.
    private func matchesNumber(propValue: String, op: String, filterValues: Set<String>) -> Bool {
        guard let propNumber = JavaScriptNumber.parse(propValue) else {
            return false
        }
        return filterValues.contains { filterValue in
            guard let filterNumber = JavaScriptNumber.parse(filterValue) else {
                return false
            }
            return matchesComparable(propValue: propNumber, op: op, filterValue: filterNumber)
        }
    }

    private func matchesComparable<T: Comparable>(propValue: String, op: String, filterValues: Set<String>, transformer: (String) -> T?) -> Bool {
        let filterValuesTransformed = filterValues.compactMap(transformer)
        guard let propValueTransformed = transformer(propValue), !filterValuesTransformed.isEmpty else {
            // If the prop value or none of the filter values transform, fall
            // back on string comparison.
            return filterValues.contains { filterValue in
                matchesComparable(propValue: propValue, op: op, filterValue: filterValue)
            }
        }
        return filterValuesTransformed.contains { filterValueTransformed in
            matchesComparable(propValue: propValueTransformed, op: op, filterValue: filterValueTransformed)
        }
    }

    private func matchesComparable<T: Comparable>(propValue: T, op: String, filterValue: T) -> Bool {
        switch op {
        case EvaluationOperator.LESS_THAN, EvaluationOperator.VERSION_LESS_THAN: return propValue < filterValue
        case EvaluationOperator.LESS_THAN_EQUALS, EvaluationOperator.VERSION_LESS_THAN_EQUALS: return propValue <= filterValue
        case EvaluationOperator.GREATER_THAN, EvaluationOperator.VERSION_GREATER_THAN: return propValue > filterValue
        case EvaluationOperator.GREATER_THAN_EQUALS, EvaluationOperator.VERSION_GREATER_THAN_EQUALS: return propValue >= filterValue
        default: return false
        }
    }

    private func matchesRegex(propValue: String, filterValues: Set<String>) -> Bool {
        return filterValues.contains { filterValue in
            propValue.range(of: filterValue, options: .regularExpression) != nil
        }
    }

    private func matchesSetContainsAll(propValues: Set<String>, filterValues: Set<String>) -> Bool {
        if propValues.count < filterValues.count {
            return false
        }
        for filterValue in filterValues where !matchesIs(propValue: filterValue, filterValues: propValues) {
            return false
        }
        return true
    }

    private func matchesSetContainsAny(propValues: Set<String>, filterValues: Set<String>) -> Bool {
        for filterValue in filterValues where matchesIs(propValue: filterValue, filterValues: propValues) {
            return true
        }
        return false
    }

    private func coerceString(value: Any?) -> String? {
        guard let value else {
            return nil
        }
        switch value {
        case let stringValue as String:
            return stringValue
        case is NSNull:
            return nil
        case let number as NSNumber:
            // As JS `String(value)`, so that 0.1 matches "0.1" rather than "0.10000000000000001".
            return JavaScriptNumber.string(number)
        default:
            // Arrays and dictionaries become JSON, as with JS `JSON.stringify`. Values JSON cannot represent, such
            // as Date, have no string form.
            return javaScriptJSON(value: value)
        }
    }

    /// JSON text as JS `JSON.stringify` writes it: numbers as JS `String()`, non-finite numbers as null, "/" not
    /// escaped. Dictionaries have no order, so keys are sorted where JS would keep insertion order. Returns nil when
    /// the value contains something JSON cannot represent. JSONSerialization is not used: it prints 0.1 as
    /// 0.10000000000000001, escapes "/" before iOS 13, and raises an uncatchable exception on such values.
    private func javaScriptJSON(value: Any) -> String? {
        switch value {
        case let string as String:
            return javaScriptJSONString(string)
        case is NSNull:
            return "null"
        case let number as NSNumber:
            if CFGetTypeID(number) != CFBooleanGetTypeID() && !number.doubleValue.isFinite {
                return "null"
            }
            return JavaScriptNumber.string(number)
        case let array as NSArray:
            var elements: [String] = []
            for element in array {
                guard let json = javaScriptJSON(value: element) else {
                    return nil
                }
                elements.append(json)
            }
            return "[" + elements.joined(separator: ",") + "]"
        case let dictionary as NSDictionary:
            var members: [(key: String, json: String)] = []
            for (key, element) in dictionary {
                guard let key = key as? String, let json = javaScriptJSON(value: element) else {
                    return nil
                }
                members.append((key, json))
            }
            members.sort { $0.key < $1.key }
            return "{" + members.map { javaScriptJSONString($0.key) + ":" + $0.json }.joined(separator: ",") + "}"
        default:
            return nil
        }
    }

    private func javaScriptJSONString(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private func coerceStringList(value: Any?) -> Set<String>? {
        guard let value else {
            return nil
        }
        // Convert sequences to a set of strings
        if let sequence = value as? NSArray {
            return sequenceToSet(sequence: sequence)
        }
        if let sequence = value as? [Any?] {
            return sequenceToSet(sequence: sequence)
        }
        // A dictionary is never a list (JS: `String(object)` is "[object Object]"); skip serializing it here.
        if value is NSDictionary {
            return nil
        }
        // Parse the string value as a json array and convert to a set of strings
        // or return nil if the string could not be parsed as a json array.
        guard let stringValue = coerceString(value: value), stringValue.hasPrefix("[") else {
            return nil
        }
        guard let dataValue = stringValue.data(using: .utf8) else {
            return nil
        }
        if let opt = try? JSONSerialization.jsonObject(with: dataValue) {
            if let nsArray = opt as? NSArray {
                var result = Set<String>()
                for element in nsArray {
                    if let stringElement = coerceString(value: element), !stringElement.isEmpty {
                        result.insert(stringElement)
                    }
                }
                return result
            }
        }

        return nil
    }

    private func sequenceToSet(sequence: any Sequence) -> Set<String>? {
        var result = Set<String>()
        // As JS, elements without a string form or with an empty one are dropped.
        for element in sequence {
            if let stringElement = coerceString(value: element), !stringElement.isEmpty {
                result.insert(stringElement)
            }
        }
        return result
    }

    private func containsNone(filterValues: Set<String>) -> Bool {
        return filterValues.contains("(none)")
    }

    private func containsBooleans(filterValues: Set<String>) -> Bool {
        return filterValues.contains { filterValue in
            let lower = filterValue.lowercased()
            return lower == "true" || lower == "false"
        }
    }

    private func isSetOperator(op: String) -> Bool {
        switch op {
        case EvaluationOperator.SET_IS: return true
        case EvaluationOperator.SET_IS_NOT: return true
        case EvaluationOperator.SET_CONTAINS: return true
        case EvaluationOperator.SET_DOES_NOT_CONTAIN: return true
        case EvaluationOperator.SET_CONTAINS_ANY: return true
        case EvaluationOperator.SET_DOES_NOT_CONTAIN_ANY: return true
        default: return false
        }
    }

    private func mergeMetadata(
        _ m1: [String: JSONValue]?,
        _ m2: [String: JSONValue]?,
        _ m3: [String: JSONValue]?
    ) -> [String: JSONValue]? {
        var mergedMetadata = m1 ?? [:]
        if let m2 {
            mergedMetadata = mergedMetadata.merging(m2, uniquingKeysWith: { _, other in other })
        }
        if let m3 {
            mergedMetadata = mergedMetadata.merging(m3, uniquingKeysWith: { _, other in other })
        }
        if mergedMetadata.isEmpty {
            return nil
        }
        return mergedMetadata
    }
}
