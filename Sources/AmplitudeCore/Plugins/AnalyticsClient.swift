import Foundation

public protocol AnalyticsClient: AnyObject {

    @discardableResult
    func track(eventType: String, eventProperties: [String: Any]?) -> Self

    func getUserId() -> String?

    func getDeviceId() -> String?

    func getSessionId() -> Int64
}
