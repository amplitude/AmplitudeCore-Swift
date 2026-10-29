import Foundation

/// Default SDK sending implementation; retries remain with each caller.
@_spi(Internal)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct URLSessionHttpClient: HttpClient {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        return try await session.data(for: request)
    }
}
