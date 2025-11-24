//
//  DiagnosticsRemoteConfigTests.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/13/25.
//

import XCTest
@_spi(Internal) @testable import AmplitudeCore

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class DiagnosticsRemoteConfigTests: XCTestCase {

    static let testApiKey = "test-diagnostics-remote-config-key"

    override func setUp() {
        super.setUp()
        // Reset remote config storage before each test
        TestRemoteConfigStorage.shared.reset()
    }

    /// Helper to skip tests that require URLProtocol on watchOS (where it doesn't work)
    private func skipIfURLProtocolUnsupported() throws {
        #if os(watchOS)
        throw XCTSkip("URLProtocol-based network mocking is unreliable on watchOS")
        #endif
    }

    // MARK: - Enable/Disable Tests

    func testDiagnosticsTurnsOnFromRemoteConfig() async throws {
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "enabled": true,
                    "sampleRate": 1.0
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        // Create client with diagnostics initially disabled
        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: false,
            sampleRate: 1.0,
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Initially disabled
        let wasRunning = await diagnosticsClient.shouldTrack
        XCTAssertFalse(wasRunning, "Should be disabled initially (enabled=false)")

        // Wait for remote config to be fetched and applied
        let expectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [expectation], timeout: 3.0)

        // Give it time for the subscription callback to execute
        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2) // 0.5 seconds

        // Should now be enabled from remote config
        let isRunningAfter = await diagnosticsClient.shouldTrack
        XCTAssertTrue(isRunningAfter, "Should be enabled after remote config (enabled=true, sampleRate=1.0)")
    }

    func testDiagnosticsTurnsOffFromRemoteConfig() async throws {
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "enabled": false
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        // Create client with diagnostics initially enabled
        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Initially enabled
        let wasRunning = await diagnosticsClient.shouldTrack
        XCTAssertTrue(wasRunning, "Should be enabled initially")

        // Wait for remote config to be fetched and applied
        let expectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [expectation], timeout: 3.0)

        // Give it time for the subscription callback to execute
        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2) // 0.5 seconds

        // Should now be disabled from remote config
        let isRunningAfter = await diagnosticsClient.shouldTrack
        XCTAssertFalse(isRunningAfter, "Should be disabled after remote config (enabled=false)")
    }

    // MARK: - Sample Rate Tests

    func testSampleRateChangesFromRemoteConfig() async throws {
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "enabled": true,
                    "sampleRate": 1.0
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        // Create client with enabled but we'll check if remote config applies
        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: true,
            sampleRate: 0,
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Wait for remote config to be fetched and applied
        let expectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [expectation], timeout: 3.0)

        // Give it time for the subscription callback to execute
        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2) // 0.5 seconds

        // Should remain running (was already running, remote confirms it)
        let isRunningAfter = await diagnosticsClient.shouldTrack
        XCTAssertTrue(isRunningAfter, "Should be running with sample rate 1.0")
    }

    func testPartialRemoteConfigEnabled() async throws {
        // Remote config only specifies enabled, not sampleRate
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "enabled": true
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        // Create client with diagnostics disabled but good sample rate
        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: false,
            sampleRate: 1.0, // Good sample rate locally
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Wait for remote config
        let expectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [expectation], timeout: 3.0)

        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2)

        // Should be enabled now (enabled=true from remote, sampleRate stays 1.0 from local)
        let isRunningAfter = await diagnosticsClient.shouldTrack
        XCTAssertTrue(isRunningAfter, "Should be enabled with local sample rate")
    }

    func testPartialRemoteConfigSampleRate() async throws {
        // Remote config only specifies sampleRate, not enabled
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "sampleRate": 1.0
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        // Create client with diagnostics enabled and we'll verify remote sample rate applies
        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: true,
            sampleRate: 0,
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Wait for remote config
        let expectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [expectation], timeout: 3.0)

        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 2)

        // Should remain running (enabled=true local, sampleRate=1.0 from remote)
        let isRunningAfter = await diagnosticsClient.shouldTrack
        XCTAssertTrue(isRunningAfter, "Should be running with remote sample rate 1.0")
    }

    func testRemoteConfigWithInvalidTypes() async throws {
        // Remote config with wrong data types
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "enabled": "true", // String instead of Bool
                    "sampleRate": "0.5" // String instead of Double
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Wait for remote config
        let expectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [expectation], timeout: 3.0)

        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 10)

        // Should ignore invalid types and keep local config
        let isRunningAfter = await diagnosticsClient.shouldTrack
        XCTAssertTrue(isRunningAfter, "Should maintain local settings with invalid remote config")
    }

    func testRemoteConfigSetsSDKVersionTag() async throws {
        try skipIfURLProtocolUnsupported()

        var capturedRequest: URLRequest?
        let uploadExpectation = XCTestExpectation(description: "Data uploaded")

        TestDiagnosticsHandler.responseHandler = { request in
            capturedRequest = request
            uploadExpectation.fulfill()
            return TestDiagnosticsHandler.successResponseHandler()(request)
        }

        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "diagnostics": [
                "iosSDK": [
                    "sampleRate": [
                        "enabled": true,
                        "sampleRate": 1.0
                    ]
                ]
            ]
        ]
        TestRemoteConfigStorage.shared.setNextConfig(remoteConfig)

        let remoteConfigClient = makeRemoteConfigClient()

        let diagnosticsClient = DiagnosticsClient(
            apiKey: Self.testApiKey,
            instanceName: "$default_instance",
            enabled: true,
            sampleRate: 1.0,
            remoteConfigClient: remoteConfigClient,
            urlSessionConfiguration: TestDiagnosticsHandler.testSessionConfiguration
        )

        // Wait for remote config
        let configExpectation = remoteConfigClient.didFetchRemoteExpectation
        await fulfillment(of: [configExpectation], timeout: 3.0)

        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 5) // 0.2 seconds for tag to be set

        // Flush to upload
        await diagnosticsClient.flush()

        await fulfillment(of: [uploadExpectation], timeout: 5.0)

        // Verify SDK version tag was set
        guard let request = capturedRequest,
              let data = extractBodyData(from: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tags = json["tags"] as? [String: String] else {
            XCTFail("Failed to parse payload")
            return
        }

        // Should have SDK version tag
        let expectedTagKey = "sdk.\(AmplitudeContext.coreLibraryName).version"
        XCTAssertNotNil(tags[expectedTagKey], "Should have SDK version tag")
        XCTAssertEqual(tags[expectedTagKey], AmplitudeContext.coreLibraryVersion)
    }

    // MARK: - Util

    private func makeRemoteConfigClient() -> RemoteConfigClient {
        return RemoteConfigClient(
            apiKey: Self.testApiKey,
            serverUrl: "http://test.amplitude.com",
            storage: TestRemoteConfigStorage.shared,
            urlSessionConfiguration: TestRemoteConfigUrlProtocol.testSessionConfiguration,
            maxRetryDelay: 0.1
        )
    }

    private func extractBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

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

// MARK: - TestRemoteConfigStorage

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class TestRemoteConfigStorage: RemoteConfigStorage, @unchecked Sendable {

    static let shared = TestRemoteConfigStorage()

    private var remoteConfigInfo: RemoteConfigClient.RemoteConfigInfo?
    private var nextConfigs: [RemoteConfigClient.RemoteConfig] = []

    func reset() {
        remoteConfigInfo = nil
        nextConfigs.removeAll()
    }

    func setNextConfig(_ config: RemoteConfigClient.RemoteConfig) {
        nextConfigs.append(config)
    }

    func fetchConfig() async throws -> RemoteConfigClient.RemoteConfigInfo? {
        return remoteConfigInfo
    }

    func setConfig(_ config: RemoteConfigClient.RemoteConfigInfo?) async throws {
        remoteConfigInfo = config
    }

    func getNextConfig() -> RemoteConfigClient.RemoteConfig? {
        guard !nextConfigs.isEmpty else { return nil }
        return nextConfigs.removeFirst()
    }
}

// MARK: - TestRemoteConfigUrlProtocol

class TestRemoteConfigUrlProtocol: URLProtocol {

    static let testSessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestRemoteConfigUrlProtocol.self]
        return configuration
    }()

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown))
            return
        }

        let config = TestRemoteConfigStorage.shared.getNextConfig() ?? [:]

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        let data = try? JSONSerialization.data(withJSONObject: ["configs": config])

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) { [self] in
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
}

// MARK: - RemoteConfigClient Extension for Testing

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension RemoteConfigClient {

    private final class SubscriptionHolder: @unchecked Sendable {
        var subscription: Any?
    }

    nonisolated var didFetchRemoteExpectation: XCTestExpectation {
        let expectation = XCTestExpectation(description: "didFetchRemote")

        let subscriptionHolder = SubscriptionHolder()
        subscriptionHolder.subscription = subscribe { [weak self] _, source, _ in
            guard source == .remote else {
                return
            }
            if let subscription = subscriptionHolder.subscription {
                Task {
                    self?.unsubscribe(subscription)
                }
            }
            expectation.fulfill()
        }

        return expectation
    }
}

// MARK: - TestDiagnosticsHandler Extension

extension TestDiagnosticsHandler {
    static let testSessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestDiagnosticsHandler.self]
        return configuration
    }()
}

