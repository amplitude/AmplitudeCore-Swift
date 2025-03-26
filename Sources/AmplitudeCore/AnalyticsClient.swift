import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol AnalyticsClientConfiguration {
    var apiKey: String { get }
    var optOut: Bool { get }
    var serverZone: ServerZone { get }
    var remoteConfigClient: RemoteConfigClient { get }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol AnalyticsClient<ConfigurationType>: AnyObject {

    associatedtype ConfigurationType: AnalyticsClientConfiguration

    var logger: Logger { get }

    var configuration: ConfigurationType { get }

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
    @discardableResult
    func add(plugin: Plugin) -> Self

    @discardableResult
    func remove(plugin: Plugin) -> Self

    func plugin(name: String) -> Plugin?

    func apply(closure: (Plugin) -> Void)
 */

    // MARK: Identity

    // TODO:
}
