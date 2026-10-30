import Foundation

/// Modifies and sends a complete request, returning the final response or throwing on failure.
/// The body may be compressed; preserve Content-Encoding when forwarding it unchanged.
/// Implementations must cooperate with task cancellation, for example by using URLSession's
/// async APIs. The SDK applies its retry policy after the client returns or throws.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol HttpClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}
