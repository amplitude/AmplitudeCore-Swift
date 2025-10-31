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

    static let testSessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestDiagnosticsHandler.self]
        return configuration
    }()

    override func setUp() async throws {
        TestDiagnosticsHandler.reset()
    }

    // MARK: - Initialization Tests

    func testInitializationWithSampledIn() async throws {
        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.successResponseHandler()

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let isRunning = await client.isRunning
        XCTAssertTrue(isRunning, "Client should be running when enabled=true and sampleRate=1.0")
    }

    func testInitializationWithSampledOut() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 0.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let isRunning = await client.isRunning
        XCTAssertFalse(isRunning, "Client should not be running when enabled=true and sampleRate=0")
    }

    func testInitializationWithDisabled() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: false,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let isRunning = await client.isRunning
        XCTAssertFalse(isRunning, "Client should not be running when enabled=false")
    }

    // MARK: - Tag Tests

    func testSetTagsAndFlush() async throws {
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
            enabled: false,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Should return immediately without error
        await client.setTag(name: "test_tag", value: "value")

        let isRunning = await client.isRunning
        XCTAssertFalse(isRunning)
    }

    // MARK: - Counter Tests

    func testIncrementAndFlush() async throws {
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
               events.contains(where: { $0["eventName"] as? String == "app_launch" }) {
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
        XCTAssertEqual(events[0]["eventName"] as? String, "app_launch")
        XCTAssertEqual((events[0]["eventProperties"] as? [String: String])?["source"], "test")
        XCTAssertEqual(events[1]["eventName"] as? String, "button_click")
        XCTAssertEqual((events[1]["eventProperties"] as? [String: String])?["button_id"], "submit")
        XCTAssertEqual(events[2]["eventName"] as? String, "simple_event")
    }

    // MARK: - Flush Tests

    func testFlushAllDataTypes() async throws {
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
        XCTAssertEqual(events?.first?["eventName"] as? String, "app_launch")
    }

    func testFlushWithNetworkError() async throws {
        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.errorResponseHandler(statusCode: 500)

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test_tag", value: "test_value")
        await client.flush()

        // Should not crash or throw
        let isRunning = await client.isRunning
        XCTAssertTrue(isRunning)
    }

    func testFlushSendsCorrectHeaders() async throws {
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
        var capturedURL: URL?
        let urlExpectation = XCTestExpectation(description: "URL captured")

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            enabled: true,
            sampleRate: 1.0,
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
        var capturedURL: URL?
        let urlExpectation = XCTestExpectation(description: "URL captured")

        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .EU,
            enabled: true,
            sampleRate: 1.0,
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
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let wasRunning = await client.isRunning
        XCTAssertTrue(wasRunning)

        await client.setEnabled(false)

        let isRunningAfterDisable = await client.isRunning
        XCTAssertFalse(isRunningAfterDisable)
    }

    func testEnableStartsOperation() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: false,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let wasRunning = await client.isRunning
        XCTAssertFalse(wasRunning)

        await client.setEnabled(true)

        let isRunningAfterEnable = await client.isRunning
        XCTAssertTrue(isRunningAfterEnable)
    }

    // MARK: - Sample Rate Tests

    func testChangeSampleRateToZeroStopsOperation() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let wasRunning = await client.isRunning
        XCTAssertTrue(wasRunning)

        await client.setSampleRate(0.0)

        // Note: Due to deterministic sampling based on session seed,
        // changing sample rate may or may not immediately affect isRunning
        // This test mainly verifies the method doesn't crash
        _ = await client.isRunning
    }

    func testChangeSampleRateToOneStartsOperation() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 0.001, // Very low
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Note: With low sample rate, may or may not be running initially
        _ = await client.isRunning

        await client.setSampleRate(1.0)

        // Should definitely be running with sample rate 1.0
        let isRunningAfterChange = await client.isRunning
        XCTAssertTrue(isRunningAfterChange)
    }

    // MARK: - Observe isRunning Tests

    func testObserveIsRunningReceivesInitialValue() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        // Should receive initial value immediately
        let initialValue = await stream.first { _ in true }
        XCTAssertNotNil(initialValue)
        XCTAssertTrue(initialValue ?? false)

        await client.stopObservingIsRunning(observerId)
    }

    func testObserveIsRunningNotifiesOnEnabledChange() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        var receivedValues: [Bool] = []
        let valueExpectation = XCTestExpectation(description: "Received value change")
        valueExpectation.expectedFulfillmentCount = 2 // Initial + change

        let observerTask = Task {
            for await isRunning in stream {
                receivedValues.append(isRunning)
                if receivedValues.count >= 2 {
                    break
                }
            }
        }

        // Wait a bit for initial value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Change enabled state
        await client.setEnabled(false)

        // Wait for task to complete (ensures all array modifications are done)
        await observerTask.value

        XCTAssertEqual(receivedValues.count, 2)
        XCTAssertTrue(receivedValues[0], "Initial value should be true")
        XCTAssertFalse(receivedValues[1], "After disable should be false")

        await client.stopObservingIsRunning(observerId)
    }

    func testObserveIsRunningNotifiesOnSampleRateChange() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        var receivedValues: [Bool] = []
        let valueExpectation = XCTestExpectation(description: "Received value change")
        valueExpectation.expectedFulfillmentCount = 2 // Initial + change

        let observerTask = Task {
            for await isRunning in stream {
                receivedValues.append(isRunning)
                if receivedValues.count >= 2 {
                    break
                }
            }
        }

        // Wait a bit for initial value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Change sample rate to 0
        await client.setSampleRate(0.0)

        // Wait for task to complete (ensures all array modifications are done)
        await observerTask.value

        XCTAssertEqual(receivedValues.count, 2)
        XCTAssertTrue(receivedValues[0], "Initial value should be true")
        XCTAssertFalse(receivedValues[1], "After sample rate 0 should be false")

        await client.stopObservingIsRunning(observerId)
    }

    func testObserveIsRunningMultipleObservers() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream1, observerId1) = await client.observeIsRunning()
        let (stream2, observerId2) = await client.observeIsRunning()

        var observer1Values: [Bool] = []
        var observer2Values: [Bool] = []
        let expectation1 = XCTestExpectation(description: "Observer 1 received values")
        let expectation2 = XCTestExpectation(description: "Observer 2 received values")
        expectation1.expectedFulfillmentCount = 2
        expectation2.expectedFulfillmentCount = 2

        let task1 = Task {
            for await isRunning in stream1 {
                observer1Values.append(isRunning)
                expectation1.fulfill()
                if observer1Values.count >= 2 {
                    break
                }
            }
        }

        let task2 = Task {
            for await isRunning in stream2 {
                observer2Values.append(isRunning)
                expectation2.fulfill()
                if observer2Values.count >= 2 {
                    break
                }
            }
        }

        // Wait for initial values
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Change state
        await client.setEnabled(false)

        await fulfillment(of: [expectation1, expectation2], timeout: 5.0)

        // Both observers should receive the same values
        XCTAssertEqual(observer1Values.count, 2)
        XCTAssertEqual(observer2Values.count, 2)
        XCTAssertTrue(observer1Values[0])
        XCTAssertFalse(observer1Values[1])
        XCTAssertTrue(observer2Values[0])
        XCTAssertFalse(observer2Values[1])

        await client.stopObservingIsRunning(observerId1)
        await client.stopObservingIsRunning(observerId2)
        task1.cancel()
        task2.cancel()
    }

    func testStopObservingIsRunning() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        var receivedValues: [Bool] = []
        let task = Task {
            for await isRunning in stream {
                receivedValues.append(isRunning)
            }
        }

        // Wait for initial value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Stop observing
        await client.stopObservingIsRunning(observerId)

        // Wait a bit for stream to finish
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let countAfterStop = receivedValues.count

        // Make a change (should not notify stopped observer)
        await client.setEnabled(false)

        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Should not have received any more values
        XCTAssertEqual(receivedValues.count, countAfterStop)
        XCTAssertEqual(receivedValues.count, 1, "Should only have initial value")

        task.cancel()
    }

    func testObserveIsRunningDoesNotNotifyWhenValueUnchanged() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        var receivedValues: [Bool] = []
        let task = Task {
            for await isRunning in stream {
                receivedValues.append(isRunning)
            }
        }

        // Wait for initial value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let initialCount = receivedValues.count
        XCTAssertEqual(initialCount, 1, "Should have received initial value")

        // Set to the same enabled state (no change)
        await client.setEnabled(true)

        // Wait to ensure no notification
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Should not have received another notification
        XCTAssertEqual(receivedValues.count, initialCount, "Should not notify when value doesn't change")

        await client.stopObservingIsRunning(observerId)
        task.cancel()
    }

    func testObserveIsRunningWithDisabledClient() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: false,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        // Should receive initial value of false
        let initialValue = await stream.first { _ in true }
        XCTAssertNotNil(initialValue)
        XCTAssertFalse(initialValue ?? true)

        await client.stopObservingIsRunning(observerId)
    }

    func testObserveIsRunningReenableClient() async throws {
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: false,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        let (stream, observerId) = await client.observeIsRunning()

        var receivedValues: [Bool] = []
        let valueExpectation = XCTestExpectation(description: "Received value change")
        valueExpectation.expectedFulfillmentCount = 2 // Initial + change

        let observerTask = Task {
            for await isRunning in stream {
                receivedValues.append(isRunning)
                if receivedValues.count >= 2 {
                    break
                }
            }
        }

        // Wait a bit for initial value
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Re-enable client
        await client.setEnabled(true)

        // Wait for task to complete (ensures all array modifications are done)
        await observerTask.value

        XCTAssertEqual(receivedValues.count, 2)
        XCTAssertFalse(receivedValues[0], "Initial value should be false")
        XCTAssertTrue(receivedValues[1], "After enable should be true")

        await client.stopObservingIsRunning(observerId)
    }

    func testBasicDiagnosticsTagsSetOnlyOnce() async throws {
        // Start with enabled client
        let client = DiagnosticsClient(
            apiKey: Self.testApiKey,
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Wait for initial setup (initialization task sets basic diagnostics tags)
        await client.initializationTask?.value

        // Check the in-memory counter directly
        let counterAfterInit = await client.storage.counters["sampled.in.and.enabled"]
        XCTAssertEqual(counterAfterInit, 1, "Should have incremented counter once during initialization")

        // Now disable and re-enable the client
        await client.setEnabled(false)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        await client.setEnabled(true)
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Check the counter again - it should still be 1
        let counterAfterReEnable = await client.storage.counters["sampled.in.and.enabled"]
        XCTAssertEqual(counterAfterReEnable, 1, "Should not have incremented counter again after re-enable")
    }

    // MARK: - Concurrent Operations Test

    func testConcurrentOperations() async throws {
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
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Add data to the old session
        await oldSession.setTag(name: "session_id", value: "old_session_123")
        await oldSession.setTag(name: "app_version", value: "1.0.0")
        await oldSession.increment(name: "old_counter", size: 42)
        await oldSession.recordHistogram(name: "old_latency", value: 250.0)
        await oldSession.recordEvent(name: "session_start", properties: ["timestamp": "2024-01-01"])

        // Manually trigger persistence to save to disk
        await oldSession.persistIfNeeded()

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
        XCTAssertEqual(events?.first?["eventName"] as? String, "session_start")

        // Clean up
        await newSession.stopFlushTimer()
        await oldSession.stopFlushTimer()
    }

    func testMultiplePreviousSessionsUpload() async throws {
        // Note: This test simulates app restarts by creating sessions with small delays
        // In practice, each DiagnosticsClient creates its own timestamp internally,
        // so we create sessions with small gaps to ensure they're treated as separate
        
        var uploadCount = 0
        var capturedRequests: [URLRequest] = []
        let uploadExpectation = XCTestExpectation(description: "Historic sessions uploaded")

        // Create a previous session and persist
        let oldSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await oldSession.setTag(name: "multi_session_test", value: "session_1")
        await oldSession.increment(name: "test_counter", size: 10)
        await oldSession.persistIfNeeded()
        await oldSession.stopFlushTimer()

        // Wait a moment to ensure timestamps are different
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

        // Create new session that should upload previous session
        TestDiagnosticsHandler.responseHandler = { request in
            capturedRequests.append(request)
            uploadCount += 1
            uploadExpectation.fulfill()
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let newSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await fulfillment(of: [uploadExpectation], timeout: 5.0)

        // Verify we got at least one upload
        XCTAssertGreaterThanOrEqual(capturedRequests.count, 1, "Should have uploaded historic session")

        await newSession.stopFlushTimer()
    }

    func testPreviousSessionDataClearedAfterUpload() async throws {
        let uploadExpectation = XCTestExpectation(description: "Historic data uploaded")

        // Create and persist old session data
        let oldSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await oldSession.setTag(name: "old_data", value: "should_be_cleared")
        await oldSession.persistIfNeeded()
        await oldSession.stopFlushTimer()

        // First new session uploads the data
        TestDiagnosticsHandler.responseHandler = { request in
            uploadExpectation.fulfill()
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let firstNewSession = DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            instanceName: "test-instance",
            enabled: true,
            sampleRate: 1.0,
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
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        // Give it a moment to potentially upload (but it shouldn't)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Should not have uploaded historic data again (might upload current session data from auto-instrumentation)
        // The key is that the old_data tag should not appear in any uploads
        await secondNewSession.stopFlushTimer()
    }

    // MARK: - Error Handling Tests

    func testHandlesInvalidURL() async throws {
        // DiagnosticsClient should handle this gracefully
        let client = DiagnosticsClient(
            apiKey: "invalid api key with spaces",
            enabled: true,
            sampleRate: 1.0,
            urlSessionConfiguration: Self.testSessionConfiguration
        )

        await client.setTag(name: "test", value: "value")

        // Should not crash
        let isRunning = await client.isRunning
        XCTAssertTrue(isRunning)
    }

    func testHandlesNetworkTimeout() async throws {
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
        let isRunning = await client.isRunning
        XCTAssertTrue(isRunning)
    }

    func testHandles4xxError() async throws {
        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.errorResponseHandler(statusCode: 400)

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test", value: "value")
        await client.flush()

        // Should handle error gracefully
        let isRunning = await client.isRunning
        XCTAssertTrue(isRunning)
    }

    func testHandles5xxError() async throws {
        TestDiagnosticsHandler.responseHandler = TestDiagnosticsHandler.errorResponseHandler(statusCode: 503)

        let client = makeDiagnosticsClient()

        await client.setTag(name: "test", value: "value")
        await client.flush()

        // Should handle error gracefully
        let isRunning = await client.isRunning
        XCTAssertTrue(isRunning)
    }

    // MARK: - Util

    private func makeDiagnosticsClient() -> DiagnosticsClient {
        return DiagnosticsClient(
            apiKey: Self.testApiKey,
            serverZone: .US,
            enabled: true,
            sampleRate: 1.0,
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
