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
        // Integers print exactly up to 2^53. Beyond it JavaScript numbers are doubles, so they print rounded.
        if let value = Int64(exactly: number), value.magnitude <= 1 << 53 {
            return String(value)
        }
        // JS has no Float or Decimal. They keep the digits they are written with (0.1, not 0.10000000149011612):
        // Amplitude-Swift uploads them with JSONEncoder, which writes the same digits, so they are what a customer
        // sees in Amplitude and copies into a rule.
        return string(number.digitPreservingDoubleValue)
    }

    /// Parses a string as JavaScript's `Number(value)` does, except that an empty or blank string is not a number
    /// (JS reads it as 0). Accepts a decimal literal with an optional sign, fraction and exponent, `Infinity`, and
    /// an unsigned `0x`, `0o` or `0b` integer. Swift's `Double(_:)` alone would also accept "inf", "nan" and
    /// hexadecimal floats such as "0x1p4", which JS reads as NaN.
    static func parse(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch text {
        case "Infinity", "+Infinity":
            return .infinity
        case "-Infinity":
            return -.infinity
        default:
            break
        }
        let bytes = Array(text.utf8)
        if bytes.count > 2, bytes[0] == UInt8(ascii: "0"), let radix = radix(prefix: bytes[1]) {
            return parseInteger(bytes.dropFirst(2), radix: radix)
        }
        return isDecimalLiteral(bytes) ? Double(text) : nil
    }

    private static func radix(prefix: UInt8) -> Int? {
        switch prefix {
        case UInt8(ascii: "x"), UInt8(ascii: "X"): return 16
        case UInt8(ascii: "o"), UInt8(ascii: "O"): return 8
        case UInt8(ascii: "b"), UInt8(ascii: "B"): return 2
        default: return nil
        }
    }

    private static func parseInteger(_ digits: ArraySlice<UInt8>, radix: Int) -> Double? {
        var result = 0.0
        for byte in digits {
            guard let digit = Character(Unicode.Scalar(byte)).hexDigitValue, digit < radix else {
                return nil
            }
            result = result * Double(radix) + Double(digit)
        }
        return result
    }

    /// `[+-]? (digits [. digits?] | . digits) ([eE] [+-]? digits)?`
    private static func isDecimalLiteral(_ bytes: [UInt8]) -> Bool {
        var index = 0
        func skipSign() {
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
        }
        func skipDigits() -> Int {
            let start = index
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                index += 1
            }
            return index - start
        }

        skipSign()
        var mantissaDigits = skipDigits()
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            mantissaDigits += skipDigits()
        }
        guard mantissaDigits > 0 else {
            return false
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            skipSign()
            guard skipDigits() > 0 else {
                return false
            }
        }
        return index == bytes.count
    }

    /// Formats a number like JavaScript's `Number.prototype.toString()`, using the shortest digits that round-trip
    /// the value (Swift's `description` provides them).
    static func string(_ value: Double) -> String {
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
