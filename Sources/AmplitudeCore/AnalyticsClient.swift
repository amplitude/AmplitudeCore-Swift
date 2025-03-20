import Foundation

public protocol AnalyticsClient: AnyObject {

    var analyticsContext: AnalyticsContext { get }

    var optOut: Bool { get }

    @discardableResult
    func track(event: BaseEvent) -> Self

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

    // MARK: Plugins

    // TODO: are these needed?
/*

 */

    // MARK: Identity

    // TODO:
}
