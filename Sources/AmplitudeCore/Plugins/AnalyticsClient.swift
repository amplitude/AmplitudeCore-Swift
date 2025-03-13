import Combine
import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol AnalyticsClient<Identity>: AnyObject {

    associatedtype Identity: AnalyticsIdentity

    var identity: Identity { get }
    var sessionId: Int64 { get }
    var optOut: Bool { get }

    func track(eventType: String, eventProperties: [String: Any]?)
}
