import Foundation

public protocol AnalyticsClient: AnyObject {

    var optOut: Bool { get }

    @discardableResult
    func track(eventType: String, eventProperties: [String: Any]?) -> Self

    // MARK: Lifecycle

    @discardableResult
    func flush() -> Self

    // MARK: UserId

    func getUserId() -> String?

    @discardableResult
    func setUserId(userId: String?) -> Self

    // MARK: DeviceId

    func getDeviceId() -> String?

    @discardableResult
    func setDeviceId(deviceId: String?) -> Self

    // MARK: SessionId

    func getSessionId() -> Int64

    @discardableResult
    func setSessionId(timestamp: Int64) -> Self
}
