//
//  JavaScriptNumber.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 10/6/26.
//

import CoreFoundation
import Foundation

/// Formats numbers the way JavaScript's `String(value)` does, which is how the reference experiment-core
/// implementation turns a number into the string its string operators compare. Rule values are written in the
/// web UI, so `0.1` must become "0.1" and `1.0` must become "1".
enum JavaScriptNumber {

    static func string(_ number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if number is NSDecimalNumber || CFNumberIsFloatType(number) {
            // JS has no Float or Decimal. Keep the digits they are written with (0.1, not 0.10000000149011612):
            // Amplitude-Swift uploads them with JSONEncoder, which writes the same digits, so they are what a
            // customer sees in Amplitude and copies into a rule.
            return string(number.digitPreservingDoubleValue)
        }
        // JavaScript numbers are doubles, so integers beyond 2^53 print rounded there.
        if let value = Int64(exactly: number), value.magnitude <= 1 << 53 {
            return String(value)
        }
        return string(number.doubleValue)
    }

    /// Formats a number like JavaScript's `Number.prototype.toString()`, using the shortest digits that round-trip
    /// the value (Swift's `description` provides them).
    static func string<T: BinaryFloatingPoint & CustomStringConvertible>(_ value: T) -> String {
        if value.isNaN {
            return "NaN"
        }
        if value.isInfinite {
            return value < 0 ? "-Infinity" : "Infinity"
        }
        guard value != 0 else {
            return "0"
        }

        // Swift prints the shortest round-trip digits, for example "0.1", "100.0", "1e-07" or "1.5e+21".
        let text = value.magnitude.description
        let parts = text.split(separator: "e", maxSplits: 1)
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        let integerDigits = String(mantissa[0])
        let fractionDigits = mantissa.count > 1 ? String(mantissa[1]) : ""

        // value = 0.digits × 10^pointPosition
        var digits = integerDigits + fractionDigits
        var pointPosition = integerDigits.count + exponent
        while digits.first == "0" {
            digits.removeFirst()
            pointPosition -= 1
        }
        while digits.last == "0" {
            digits.removeLast()
        }

        let count = digits.count
        let formatted: String
        if count <= pointPosition && pointPosition <= 21 {
            formatted = digits + String(repeating: "0", count: pointPosition - count)
        } else if 0 < pointPosition && pointPosition <= 21 {
            let splitIndex = digits.index(digits.startIndex, offsetBy: pointPosition)
            formatted = String(digits[..<splitIndex]) + "." + String(digits[splitIndex...])
        } else if -6 < pointPosition && pointPosition <= 0 {
            formatted = "0." + String(repeating: "0", count: -pointPosition) + digits
        } else {
            let exponentValue = pointPosition - 1
            let exponentText = (exponentValue < 0 ? "-" : "+") + String(abs(exponentValue))
            let head = String(digits.prefix(1))
            let tail = String(digits.dropFirst())
            formatted = head + (tail.isEmpty ? "" : "." + tail) + "e" + exponentText
        }
        return value < 0 ? "-" + formatted : formatted
    }
}
