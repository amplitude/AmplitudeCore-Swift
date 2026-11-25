import Foundation

/// Supplies wall-clock dates. Subclasses must keep `getDate()` safe for concurrent calls.
class DateProvider: @unchecked Sendable {
    func getDate() -> Date {
        return Date()
    }
}
