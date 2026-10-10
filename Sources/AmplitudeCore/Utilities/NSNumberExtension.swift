//
//  NSNumberExtension.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 10/9/26.
//

import CoreFoundation
import Foundation

extension NSNumber {

    /// The value as a Double with the digits the number is written with. `doubleValue` widens a Float bit for bit
    /// (0.1 becomes 0.10000000149011612) and does not round a decimal number correctly (19.99 becomes
    /// 19.990000000000002). JSONEncoder writes a Float and a Decimal with their own digits, so these are the digits
    /// a reader of the JSON sees.
    var digitPreservingDoubleValue: Double {
        if let decimal = self as? NSDecimalNumber {
            // `stringValue` always uses "." as the separator.
            return Double(decimal.stringValue) ?? decimal.doubleValue
        }
        switch CFNumberGetType(self) {
        case .float32Type, .floatType:
            // `description` gives the Float's shortest round-trip digits.
            return Double(floatValue.description) ?? doubleValue
        default:
            return doubleValue
        }
    }
}
