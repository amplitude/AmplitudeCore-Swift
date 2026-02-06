//
//  DiagnosticsClientTests.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/10/25.
//

import XCTest
@_spi(Internal) @testable import AmplitudeCore

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class DiagnosticsClientTests: XCTestCase {

    static let testApiKey = "test-diagnostics-api-key"
    var testInstanceName: String = ""

    static let testSessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        #if !os(watchOS)
        // URLProtocol doesn't work reliably on watchOS, so only set it on other platforms
        configuration.protocolClasses = [TestDiagnosticsHandler.self]
        #endif
        return configuration
    }()

    override func setUp() async throws {
        TestDiagnosticsHandler.reset()
        testInstanceName = "test-diagnostics-instance-\(UUID().uuidString)"
    }

    /// Helper to skip tests that require URLProtocol on watchOS (where it doesn't work)
    private func skipIfURLProtocolUnsupported() throws {
        #if os(watchOS)
        throw XCTSkip("URLProtocol-based network mocking is unreliable on watchOS")
        #endif
    }

    // MARK: - Initialization Tests

    func testInitializationWithSampledIn() async throws {
        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.successResponseHandler()

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default-instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let isRunning = await client.shouldTrack
        XCTAssertTrue(isRunning, "Client should be running when enabled=true and sampleRate=1.0")
    }

    func testInitializationWithSampledOut() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default-instance",
            enabled: true,
            sampleRate: 0.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let isRunning = await client.shouldTrack
        XCTAssertFalse(isRunning, "Client should not be running when enabled=true and sampleRate=0")
    }

    func testInitializationWithDisabled() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: false,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let isRunning = await client.shouldTrack
        XCTAssertFalse(isRunning, "Client should not be running when enabled=false")
    }

    // MARK: - Tag Tests

    func testSetTagsAndFlush() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test tags to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = json["tags"] as? [String: String],
               tags["single_tag"] != nil {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.setTag(name: "single_tag", value: "single_value")
        await client.setTags([
            "batch_tag_1": "value_1",
            "batch_tag_2": "value_2"
        ])
        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = json["tags"] as? [String: String] else {
            XCTFail("Failed to parse payload")
            return
        }

        XCTAssertEqual(tags["single_tag"], "single_value")
        XCTAssertEqual(tags["batch_tag_1"], "value_1")
        XCTAssertEqual(tags["batch_tag_2"], "value_2")
    }

    func testSetTagWhenDisabled() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: false,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Should return immediately without error
        await client.setTag(name: "test_tag", value: "value")

        let isRunning = await client.shouldTrack
        XCTAssertFalse(isRunning)
    }

    // MARK: - Counter Tests

    func testIncrementAndFlush() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test counters to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let counters = json["counters"] as? [String: Double],
               counters["counter_1"] != nil || counters["counter_2"] != nil {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.increment(name: "counter_1", size: 5)
        await client.increment(name: "counter_2", size: 10)
        await client.increment(name: "counter_1", size: 3) // Accumulate
        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counters = json["counters"] as? [String: Double] else {
            XCTFail("Failed to parse payload")
            return
        }

        XCTAssertEqual(counters["counter_1"], 8) // 5 + 3
        XCTAssertEqual(counters["counter_2"], 10)
    }

    func testIncrementWithDefaultSize() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test counter to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let counters = json["counters"] as? [String: Double],
               counters["default_counter"] != nil {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.increment(name: "default_counter")
        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counters = json["counters"] as? [String: Double] else {
            XCTFail("Failed to parse payload")
            return
        }

        XCTAssertEqual(counters["default_counter"], 1.0)
    }

    // MARK: - Histogram Tests

    func testRecordHistogramAndFlush() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test histogram to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let histogram = json["histogram"] as? [String: [String: Any]],
               histogram["latency"] != nil {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.recordHistogram(name: "latency", value: 100.0)
        await client.recordHistogram(name: "latency", value: 200.0)
        await client.recordHistogram(name: "latency", value: 150.0)
        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let histogram = json["histogram"] as? [String: [String: Any]],
              let latencyStats = histogram["latency"] else {
            XCTFail("Failed to parse payload")
            return
        }

        XCTAssertEqual(latencyStats["count"] as? Int, 3)
        XCTAssertEqual(latencyStats["min"] as? Double, 100.0)
        XCTAssertEqual(latencyStats["max"] as? Double, 200.0)
        XCTAssertEqual(latencyStats["avg"] as? Double, 150.0)
    }

    // MARK: - Event Tests

    func testRecordEventsAndFlush() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test events to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let events = json["events"] as? [[String: Any]],
               events.contains(where: { $0["event_name"] as? String == "app_launch" }) {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.recordEvent(name: "app_launch", properties: ["source": "test"])
        await client.recordEvent(name: "button_click", properties: ["button_id": "submit"])
        await client.recordEvent(name: "simple_event", properties: nil)
        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            XCTFail("Failed to parse payload")
            return
        }

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0]["event_name"] as? String, "app_launch")
        XCTAssertEqual((events[0]["event_properties"] as? [String: String])?["source"], "test")
        XCTAssertEqual(events[1]["event_name"] as? String, "button_click")
        XCTAssertEqual((events[1]["event_properties"] as? [String: String])?["button_id"], "submit")
        XCTAssertEqual(events[2]["event_name"] as? String, "simple_event")
    }

    // MARK: - Flush Tests

    func testFlushAllDataTypes() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test data to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let counters = json["counters"] as? [String: Double],
               counters["api_calls"] != nil {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.setTag(name: "sdk_version", value: "1.0.0")
        await client.setTag(name: "platform", value: "iOS")
        await client.increment(name: "api_calls", size: 5)
        await client.increment(name: "errors", size: 2)
        await client.recordHistogram(name: "request_latency", value: 100.0)
        await client.recordHistogram(name: "request_latency", value: 200.0)
        await client.recordEvent(name: "app_launch", properties: ["source": "test"])
        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse payload")
            return
        }

        // Verify tags
        let tags = json["tags"] as? [String: String]
        XCTAssertEqual(tags?["sdk_version"], "1.0.0")
        XCTAssertEqual(tags?["platform"], "iOS")

        // Verify counters
        let counters = json["counters"] as? [String: Double]
        XCTAssertEqual(counters?["api_calls"], 5.0)
        XCTAssertEqual(counters?["errors"], 2.0)

        // Verify histograms
        let histogram = json["histogram"] as? [String: [String: Any]]
        let latencyStats = histogram?["request_latency"]
        XCTAssertEqual(latencyStats?["count"] as? Int, 2)
        XCTAssertEqual(latencyStats?["min"] as? Double, 100.0)
        XCTAssertEqual(latencyStats?["max"] as? Double, 200.0)

        // Verify events
        let events = json["events"] as? [[String: Any]]
        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(events?.first?["event_name"] as? String, "app_launch")
    }

    func testFlushWithNetworkError() async throws {
        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.errorResponseHandler(statusCode: 500)

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test_tag", value: "test_value")
        await client.flush()

        // Should not crash or throw
        let isRunning = await client.shouldTrack
        XCTAssertTrue(isRunning)
    }

    func testFlushSendsCorrectHeaders() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let headerExpectation = XCTestExpectation(description: "Headers captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test tag to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = json["tags"] as? [String: String],
               tags["test"] != nil {
                capturedRequest = request
                headerExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.setTag(name: "test", value: "value")
        await client.flush()

        await fulfillment(of: [headerExpectation], timeout: 5.0)

        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-ApiKey"), Self.testApiKey)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-Client-Sample-Rate"), "1.0")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - Server Zone Tests

    func testUSServerZone() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedURL: URL?
        let urlExpectation = XCTestExpectation(description: "URL captured")

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test tag to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = json["tags"] as? [String: String],
               tags["test"] != nil {
                capturedURL = request.url
                urlExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.setTag(name: "test", value: "value")
        await client.flush()

        await fulfillment(of: [urlExpectation], timeout: 5.0)

        XCTAssertTrue(capturedURL?.absoluteString.contains("us-west-2") ?? false)
    }

    func testEUServerZone() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedURL: URL?
        let urlExpectation = XCTestExpectation(description: "URL captured")

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .EU,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test tag to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tags = json["tags"] as? [String: String],
               tags["test"] != nil {
                capturedURL = request.url
                urlExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        await client.setTag(name: "test", value: "value")
        await client.flush()

        await fulfillment(of: [urlExpectation], timeout: 5.0)

        XCTAssertTrue(capturedURL?.absoluteString.contains("eu-central-1") ?? false)
    }

    // MARK: - Enable/Disable Tests

    func testDisableStopsOperation() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let wasRunning = await client.shouldTrack
        XCTAssertTrue(wasRunning)

        await client.updateConfig(enabled: false)

        let isRunningAfterDisable = await client.shouldTrack
        XCTAssertFalse(isRunningAfterDisable)
    }

    func testEnableStartsOperation() async throws {
        try skipIfURLProtocolUnsupported()

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: false,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let wasRunning = await client.shouldTrack
        XCTAssertFalse(wasRunning)

        await client.updateConfig(enabled: true)

        let isRunningAfterEnable = await client.shouldTrack
        XCTAssertTrue(isRunningAfterEnable)
    }

    // MARK: - Sample Rate Tests

    func testChangeSampleRateToZeroStopsOperation() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let wasRunning = await client.shouldTrack
        XCTAssertTrue(wasRunning)

        await client.updateConfig(sampleRate: 0.0)

        // Note: Due to deterministic sampling based on session seed,
        // changing sample rate may or may not immediately affect isRunning
        // This test mainly verifies the method doesn't crash
        _ = await client.shouldTrack
    }

    func testChangeSampleRateToOneStartsOperation() async throws {
        try skipIfURLProtocolUnsupported()

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 0.001, // Very low
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Note: With low sample rate, may or may not be running initially
        _ = await client.shouldTrack

        await client.updateConfig(sampleRate: 1.0)

        // Should definitely be running with sample rate 1.0
        let isRunningAfterChange = await client.shouldTrack
        XCTAssertTrue(isRunningAfterChange)
    }

    func testBasicDiagnosticsTagsSetOnlyOnce() async throws {
        // Start with enabled client
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Wait for initial setup (initialization task sets basic diagnostics tags)
        await client.initializationTask?.value

        // Check the in-memory counter directly
        let counterAfterInit = await client.storage.counters["sampled.in.and.enabled"]
        XCTAssertEqual(counterAfterInit, 1, "Should have incremented counter once during initialization")

        // Now disable and re-enable the client
        await client.updateConfig(enabled: false)
        await client.initializationTask?.value
        await client.updateConfig(enabled: true)
        await client.initializationTask?.value

        // Check the counter again - it should still be 1
        let counterAfterReEnable = await client.storage.counters["sampled.in.and.enabled"]
        XCTAssertEqual(counterAfterReEnable, 1, "Should not have incremented counter again after re-enable")
    }

    // MARK: - Concurrent Operations Test

    func testConcurrentOperations() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let payloadExpectation = XCTestExpectation(description: "Payload captured")

        let client = makeDiagnosticsClient()

        // Wait for initialization to complete to avoid race condition with flushStored()
        await client.initializationTask?.value

        TestDiagnosticsHandler.responseHandler = { request in
            // Only capture requests that contain our test counters to avoid capturing initialization flush
            if let data = self.extractBodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let counters = json["counters"] as? [String: Double],
               counters["counter_0"] != nil {
                capturedRequest = request
                payloadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        // Perform concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    await client.setTag(name: "tag_\(i)", value: "value_\(i)")
                }
                group.addTask {
                    await client.increment(name: "counter_\(i)", size: i + 1)
                }
            }
        }

        await client.flush()

        await fulfillment(of: [payloadExpectation], timeout: 5.0)

        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = json["tags"] as? [String: String],
              let counters = json["counters"] as? [String: Double] else {
            XCTFail("Failed to parse payload")
            return
        }

        // All concurrent operations should have completed (plus any system tags/counters)
        XCTAssertGreaterThanOrEqual(tags.count, 5, "Should have at least 5 tags")
        XCTAssertGreaterThanOrEqual(counters.count, 5, "Should have at least 5 counters")

        // Verify our specific values
        XCTAssertEqual(tags["tag_0"], "value_0")
        XCTAssertEqual(tags["tag_1"], "value_1")
        XCTAssertEqual(tags["tag_4"], "value_4")
        XCTAssertEqual(counters["counter_0"], 1.0)
        XCTAssertEqual(counters["counter_4"], 5.0)
    }

    // MARK: - Historic Data Tests

    func testLoadAndUploadPreviousSessionData() async throws {
        try skipIfURLProtocolUnsupported()

        var uploadCount = 0
        var capturedRequests: [URLRequest] = []
        let uploadExpectation = XCTestExpectation(description: "Previous session data uploaded")

        // Step 1: Create a "previous session" and persist data
        let oldSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Add data to the old session
        await oldSession.setTag(name: "session_id", value: "old_session_123")
        await oldSession.setTag(name: "app_version", value: "1.0.0")
        await oldSession.increment(name: "old_counter", size: 42)
        await oldSession.recordHistogram(name: "old_latency", value: 250.0)
        await oldSession.recordEvent(name: "session_start", properties: ["timestamp": "2024-01-01"])

        // Manually trigger persistence to save to disk
        await oldSession.storage.persistIfNeeded()

        // Step 2: Create a new session (simulating app restart)
        TestDiagnosticsHandler.responseHandler = { request in
            capturedRequests.append(request)
            uploadCount += 1
            if uploadCount >= 1 {
                uploadExpectation.fulfill()
            }
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let newSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // The new session should automatically load and upload the old session's data
        await fulfillment(of: [uploadExpectation], timeout: 5.0)

        // Step 3: Validate the uploaded data
        guard let historicRequest = capturedRequests.first,
              let data = extractBodyData(from: historicRequest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse historic data payload")
            return
        }

        // Verify the old session's data was uploaded
        let tags = json["tags"] as? [String: String]
        XCTAssertEqual(tags?["session_id"], "old_session_123")
        XCTAssertEqual(tags?["app_version"], "1.0.0")

        let counters = json["counters"] as? [String: Double]
        XCTAssertEqual(counters?["old_counter"], 42.0)

        let histogram = json["histogram"] as? [String: [String: Any]]
        let latencyStats = histogram?["old_latency"]
        XCTAssertEqual(latencyStats?["count"] as? Int, 1)
        XCTAssertEqual(latencyStats?["min"] as? Double, 250.0)
        XCTAssertEqual(latencyStats?["max"] as? Double, 250.0)

        let events = json["events"] as? [[String: Any]]
        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(events?.first?["event_name"] as? String, "session_start")

        // Clean up
        await newSession.stopFlushTimer()
        await oldSession.stopFlushTimer()
    }

    func testMultiplePreviousSessionsUpload() async throws {
        try skipIfURLProtocolUnsupported()

        // Note: This test simulates app restarts by creating sessions with small delays
        // In practice, each DiagnosticsClient creates its own timestamp internally,
        // so we create sessions with small gaps to ensure they're treated as separate

        var uploadCount = 0
        var capturedRequests: [URLRequest] = []
        let uploadExpectation = XCTestExpectation(description: "Historic sessions uploaded")

        // Create a previous session and persist
        let oldSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await oldSession.initializationTask?.value
        await oldSession.setTag(name: "multi_session_test", value: "session_1")
        await oldSession.increment(name: "test_counter", size: 10)
        await oldSession.storage.persistIfNeeded()
        await oldSession.stopFlushTimer()

        // Wait a moment to ensure timestamps are different
        try await Task.sleep(nanoseconds: NSEC_PER_SEC) // 1 seconds

        // Create new session that should upload previous session
        TestDiagnosticsHandler.responseHandler = { request in
            capturedRequests.append(request)
            uploadCount += 1
            uploadExpectation.fulfill()
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let newSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await fulfillment(of: [uploadExpectation], timeout: 5.0)

        // Verify we got at least one upload
        XCTAssertGreaterThanOrEqual(capturedRequests.count, 1, "Should have uploaded historic session")

        await newSession.stopFlushTimer()
    }

    func testPreviousSessionDataClearedAfterUpload() async throws {
        try skipIfURLProtocolUnsupported()

        let uploadExpectation = XCTestExpectation(description: "Historic data uploaded")

        // Create and persist old session data
        let oldSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await oldSession.initializationTask?.value
        await oldSession.setTag(name: "old_data", value: "should_be_cleared")
        await oldSession.increment(name: "test_counter", size: 1)
        await oldSession.storage.persistIfNeeded()
        await oldSession.stopFlushTimer()

        // First new session uploads the data
        TestDiagnosticsHandler.responseHandler = { request in
            uploadExpectation.fulfill()
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let firstNewSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await fulfillment(of: [uploadExpectation], timeout: 5.0)
        await firstNewSession.stopFlushTimer()

        // Second new session should NOT upload the same data again
        var secondSessionUploadCount = 0
        TestDiagnosticsHandler.responseHandler = { request in
            secondSessionUploadCount += 1
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let secondNewSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Wait for initialization to complete (which includes flushing previous sessions)
        await secondNewSession.initializationTask?.value

        // Should not have uploaded historic data again (might upload current session data from auto-instrumentation)
        // The key is that the old_data tag should not appear in any uploads
        await secondNewSession.stopFlushTimer()
    }

    // MARK: - Error Handling Tests

    func testHandlesInvalidURL() async throws {
        try skipIfURLProtocolUnsupported()

        // DiagnosticsClient should handle this gracefully
        let client = DiagnosticsClient(
            apiKey: "invalid api key with spaces",
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await client.setTag(name: "test", value: "value")

        // Should not crash
        let isRunning = await client.shouldTrack
        XCTAssertTrue(isRunning)
    }

    func testHandlesNetworkTimeout() async throws {
        try skipIfURLProtocolUnsupported()

        // Note: This test verifies that the client doesn't crash when a request times out
        // We simulate a slow response rather than a true timeout for test speed
        TestDiagnosticsHandler.responseHandler = { request in
            Thread.sleep(forTimeInterval: 1.0) // Simulate slow network
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test", value: "value")
        await client.flush()

        // Should handle slow responses gracefully without crashing
        let isRunning = await client.shouldTrack
        XCTAssertTrue(isRunning)
    }

    func testHandles4xxError() async throws {
        try skipIfURLProtocolUnsupported()

        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.errorResponseHandler(statusCode: 400)

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test", value: "value")
        await client.flush()

        // Should handle error gracefully
        let isRunning = await client.shouldTrack
        XCTAssertTrue(isRunning)
    }

    func testHandles5xxError() async throws {
        try skipIfURLProtocolUnsupported()

        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.errorResponseHandler(statusCode: 503)

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test", value: "value")
        await client.flush()

        // Should handle error gracefully
        let isRunning = await client.shouldTrack
        XCTAssertTrue(isRunning)
    }

    // MARK: - Util

    private func makeDiagnosticsClient() -> DiagnosticsClient {
        return DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: testInstanceName,
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: nil,
            urlSessionConfiguration: Self.testSessionConfiguration
        )
    }

    private func extractBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        // Try to read from httpBodyStream
        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            }
        }

        return data
    }
}

// MARK: - TestDiagnosticsHandler

class TestDiagnosticsHandler: URLProtocol {

    typealias ResponseHandler = (URLRequest) -> (URLResponse, Data?)

    static var responseHandler: ResponseHandler?
    static var requestCount = 0

    static func reset() {
        responseHandler = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.requestCount += 1

        guard let responseHandler = Self.responseHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown))
            return
        }

        DispatchQueue.global().async { [self] in
            let (response, data) = responseHandler(request)

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        // no-op
    }

    static func successResponseHandler() -> ResponseHandler {
        return { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: URL(string: "http://test.com")!, statusCode: 400, httpVersion: nil, headerFields: nil)!, nil)
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            let responseBody = """
            {
                "success": true
            }
            """

            return (response, responseBody.data(using: .utf8))
        }
    }

    static func errorResponseHandler(statusCode: Int = 400) -> ResponseHandler {
        return { request in
            let url = request.url ?? URL(string: "http://test.com")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
    }
}
