import XCTest
@_spi(Internal) @testable import AmplitudeCore

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class HttpClientTests: XCTestCase {
    private let request = URLRequest(url: URL(string: "https://example.invalid/test")!)

    func testTransportRetainsStatefulActorClient() async throws {
        var client: StatefulHttpClient? = StatefulHttpClient()
        weak var retainedClient = client
        let transport: any HttpClient = (client as (any HttpClient)?) ?? URLSessionHttpClient()
        client = nil
        XCTAssertNotNil(retainedClient)
        for expectedCount in 1...2 {
            let (data, _) = try await transport.data(for: request)
            XCTAssertEqual(String(data: data, encoding: .utf8), String(expectedCount))
        }
    }

    func testCustomHandlerSkipsDefaultSessionEvenOnFailure() async {
        func unexpectedSession() -> URLSession {
            XCTFail("Custom handlers must not create or fall back to the SDK session")
            return .shared
        }
        let customClient: (any HttpClient)? = ClosureHttpClient { _ in throw URLError(.timedOut) }
        let transport = customClient ?? URLSessionHttpClient(session: unexpectedSession())
        for _ in 0..<2 {
            do {
                _ = try await transport.data(for: request)
                XCTFail("Expected the custom handler's error")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .timedOut)
            }
        }
    }

    func testHandlerResponseReachesCallback() async {
        let completed = expectation(description: "callback receives response")
        let handler = ClosureHttpClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data("ok".utf8), response)
        }
        _ = handler.send(request) { data, response, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data("ok".utf8))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 3)
    }

    func testHandlerErrorReachesCallback() async {
        let completed = expectation(description: "callback receives failure")
        let handler = ClosureHttpClient { _ in
            throw URLError(.timedOut)
        }
        _ = handler.send(request) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 3)
    }

    func testCallbackCancellationReachesAsyncHandler() async {
        let started = expectation(description: "handler started")
        let cancelled = expectation(description: "handler cancelled")
        let completed = expectation(description: "callback cancelled once")
        completed.assertForOverFulfill = true
        let handler = ClosureHttpClient { _ in
            try await withTaskCancellationHandler(operation: {
                started.fulfill()
                try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC)
                throw URLError(.timedOut)
            }, onCancel: { cancelled.fulfill() })
        }
        let cancel = handler.send(request) { _, _, error in
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        cancel()
        cancel()
        await fulfillment(of: [cancelled, completed], timeout: 3)
    }

    func testHandlerCanModifyAndSendRequest() async throws {
        #if os(watchOS)
        throw XCTSkip("watchOS URLSession does not reliably intercept requests through URLProtocol")
        #endif
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HandlerURLProtocol.self]
        let session = URLSession(configuration: config)
        let handler = ClosureHttpClient { original in
            var request = original
            request.url = URL(string: "https://example.invalid/proxy")!
            request.httpMethod = "POST"
            request.httpBody = Data("modified".utf8)
            request.setValue("custom-value", forHTTPHeaderField: "X-Custom")
            return try await session.data(for: request)
        }
        let (data, response) = try await handler.data(for: request)
        XCTAssertEqual(data, Data("modified".utf8))
        XCTAssertEqual(response.url?.path, "/proxy")
    }

    func testDefaultTransportPreservesRequestBody() async throws {
        #if os(watchOS)
        throw XCTSkip("watchOS URLSession does not reliably intercept requests through URLProtocol")
        #endif
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HandlerURLProtocol.self]
        var sessionCreations = 0
        func makeSession() -> URLSession {
            sessionCreations += 1
            return URLSession(configuration: config)
        }
        let transport = URLSessionHttpClient(session: makeSession())
        var request = request
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)
        request.setValue("custom-value", forHTTPHeaderField: "X-Custom")
        for _ in 0..<2 {
            let (data, _) = try await transport.data(for: request)
            XCTAssertEqual(data, Data("payload".utf8))
        }
        XCTAssertEqual(sessionCreations, 1)
    }

    func testAlreadyCancelledTaskDoesNotInvokeHandler() async {
        let gate = DispatchSemaphore(value: 0)
        let transport = ClosureHttpClient { _ in
            XCTFail("Cancelled task must not start a request")
            throw URLError(.unknown)
        }
        let request = request
        let waitForGate: @Sendable () -> Void = { _ = gate.wait(timeout: .now() + 5) }
        let task = Task.detached {
            waitForGate()
            return try await transport.data(for: request)
        }
        task.cancel()
        gate.signal()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testContextRoutesRemoteConfigAndDiagnosticsThroughHandler() async throws {
        let configReceived = expectation(description: "remote config")
        let diagnosticReceived = expectation(description: "diagnostic upload")
        let handler = ClosureHttpClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-ApiKey"), "test-key")
                XCTAssertNotNil(request.httpBody)
                diagnosticReceived.fulfill()
                return (Data(), response)
            } else {
                configReceived.fulfill()
                return (Data(#"{"configs":{}}"#.utf8), response)
            }
        }
        let context = AmplitudeContext(apiKey: "test-key", instanceName: UUID().uuidString, httpClient: handler)
        await fulfillment(of: [configReceived], timeout: 3)
        let diagnostics = try XCTUnwrap(context.diagnosticsClient as? DiagnosticsClient)
        await diagnostics.initializationTask?.value
        await diagnostics.updateConfig(enabled: true, sampleRate: 1)
        await diagnostics.increment(name: "test", size: 1)
        await diagnostics.flush()
        await fulfillment(of: [diagnosticReceived], timeout: 3)
    }
}

private final class HandlerURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom"), "custom-value")
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct ClosureHttpClient: HttpClient {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(_ handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private actor StatefulHttpClient: HttpClient {
    private var count = 0

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1
        return (Data(String(count).utf8), URLResponse(url: request.url!, mimeType: nil,
                                                    expectedContentLength: 0, textEncodingName: nil))
    }
}
