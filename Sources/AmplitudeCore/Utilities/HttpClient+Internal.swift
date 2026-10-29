import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension HttpClient {
    @_spi(Internal)
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let result = try await send(request)
        try Task.checkCancellation()
        return result
    }

    @_spi(Internal)
    public func send(
        _ request: URLRequest,
        completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> @Sendable () -> Void {
        let task = Task {
            do {
                let (data, response) = try await data(for: request)
                completion(data, response, nil)
            } catch {
                // Preserve the URLSession cancellation error expected by callback callers.
                completion(nil, nil, error is CancellationError ? URLError(.cancelled) : error)
            }
        }
        return { task.cancel() }
    }
}
