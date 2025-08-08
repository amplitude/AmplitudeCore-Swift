//
//  RemoteConfigTests.swift
//  Amplitude-Swift
//
//  Created by Chris Leonavicius on 1/16/25.
//

@testable import AmplitudeCore
import Foundation
import XCTest

final class RemoteConfigTests: XCTestCase {

    static let apiKey = "testApiKey"
    static let serverUrl = "http://www.amplitude.com"

    private static let testSessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestRemoteConfigHandler.self]
        return configuration
    }()

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testRequestsConfigAndUpdatesCache() async throws {
        let cachedConfig: RemoteConfigClient.RemoteConfig = ["cached": 1]
        let cachedConfigLastFetch = Date.distantPast
        let remoteConfig: RemoteConfigClient.RemoteConfig = ["remote": 1]
        TestRemoteConfigHandler.responseHandler = TestRemoteConfigHandler.successResponseHandler(remoteConfig)

        let storage = RemoteConfigInMemoryStorage()
        try await storage.setConfig(RemoteConfigClient.RemoteConfigInfo(config: cachedConfig,
                                                                        lastFetch: cachedConfigLastFetch))

        let remoteConfigClient = makeRemoteConfigClient(storage: storage)

        let didUpdateConfigExpectation = XCTestExpectation(description: "it did request config")
        didUpdateConfigExpectation.assertForOverFulfill = true
        didUpdateConfigExpectation.expectedFulfillmentCount = 2
        remoteConfigClient.subscribe { config, source, lastFetch in
            switch source {
            case .cache:
                XCTAssertEqual(config as? NSDictionary, cachedConfig as NSDictionary)
                XCTAssertEqual(lastFetch, cachedConfigLastFetch)
            case .remote:
                XCTAssertEqual(config as? NSDictionary, remoteConfig as NSDictionary)
                XCTAssertNotEqual(lastFetch, cachedConfigLastFetch)
            }

            didUpdateConfigExpectation.fulfill()
        }

        await fulfillment(of: [didUpdateConfigExpectation], timeout: 3)

        let storedConfigInfo = try await storage.fetchConfig()
        XCTAssertEqual(storedConfigInfo?.config as? NSDictionary, remoteConfig as NSDictionary)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testDoesNotUpdateCacheOnError() async throws {
        let didSendRemoteRequestExpectation = XCTestExpectation(description: "it did request config")
        didSendRemoteRequestExpectation.expectedFulfillmentCount = RemoteConfigClient.Config.maxRetries
        TestRemoteConfigHandler.responseHandler = { request in
            didSendRemoteRequestExpectation.fulfill()
            return TestRemoteConfigHandler.errorResponseHandler()(request)
        }

        let storage = RemoteConfigInMemoryStorage()

        let cachedConfigInfo = RemoteConfigClient.RemoteConfigInfo(config: ["bar": 123],
                                                                   lastFetch: Date.distantPast)
        try await storage.setConfig(cachedConfigInfo)

        let remoteConfigClient = makeRemoteConfigClient(storage: storage)

        let didUpdateConfigExpectation = XCTestExpectation(description: "it did request config")
        remoteConfigClient.subscribe { config, source, lastFetch in
            XCTAssertEqual(config as? NSDictionary, cachedConfigInfo.config as NSDictionary)
            XCTAssertEqual(source, .cache)
            XCTAssertEqual(lastFetch, cachedConfigInfo.lastFetch)

            didUpdateConfigExpectation.fulfill()
        }

        await fulfillment(of: [didUpdateConfigExpectation, didSendRemoteRequestExpectation], timeout: 3)

        let currentCachedConfigInfo = try await storage.fetchConfig()
        XCTAssertEqual(currentCachedConfigInfo?.config as? NSDictionary, cachedConfigInfo.config as NSDictionary)
        XCTAssertEqual(currentCachedConfigInfo?.lastFetch, cachedConfigInfo.lastFetch)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testReturnsNilOnErrorColdStart() async throws {
        let didSendRemoteRequestExpectation = XCTestExpectation(description: "it did request config")
        didSendRemoteRequestExpectation.expectedFulfillmentCount = RemoteConfigClient.Config.maxRetries
        TestRemoteConfigHandler.responseHandler = { request in
            didSendRemoteRequestExpectation.fulfill()
            return TestRemoteConfigHandler.errorResponseHandler()(request)
        }

        let storage = RemoteConfigInMemoryStorage()
        try await storage.setConfig(nil)

        let didUpdateConfigExpectation = XCTestExpectation(description: "it did request config")
        let remoteConfigClient = makeRemoteConfigClient(storage: storage)
        remoteConfigClient.subscribe { config, source, lastFetch in
            XCTAssertNil(config)
            XCTAssertNil(lastFetch)

            didUpdateConfigExpectation.fulfill()
        }
        await fulfillment(of: [didUpdateConfigExpectation, didSendRemoteRequestExpectation], timeout: 10)
    }

    // MARK: - Delivery Strategy tests

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testAllDeliveryStrategy() async throws {
        TestRemoteConfigHandler.responseHandler = TestRemoteConfigHandler.successResponseHandler()

        let didReceiveCachedResponseExpecation = XCTestExpectation(description: "it did request cached config")
        didReceiveCachedResponseExpecation.assertForOverFulfill = true

        let didReceiveRemoteResponseExpecation = XCTestExpectation(description: "it did request remote config")
        didReceiveRemoteResponseExpecation.assertForOverFulfill = true

        let storage = RemoteConfigInMemoryStorage()
        try await storage.setConfig(.init(config: ["cached": 1], lastFetch: Date.distantPast))

        let remoteConfigClient = makeRemoteConfigClient(storage: storage)

        remoteConfigClient.subscribe(deliveryMode: .all) { config, source, _ in
            switch source {
            case .cache:
                didReceiveCachedResponseExpecation.fulfill()
            case .remote:
                didReceiveRemoteResponseExpecation.fulfill()
            }
        }

        await fulfillment(of: [didReceiveCachedResponseExpecation, didReceiveRemoteResponseExpecation],
                          timeout: 3,
                          enforceOrder: true)

        // Future fetches should just return the successful remote response
        let subsequentFetchExpectation = XCTestExpectation(description: "subsequent fetch")
        remoteConfigClient.subscribe(deliveryMode: .all) { config, source, _ in
            switch source {
            case .cache:
                XCTFail()
            case .remote:
                subsequentFetchExpectation.fulfill()
            }
        }

        await fulfillment(of: [subsequentFetchExpectation], timeout: 3)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testWaitForRemoteDeliveryStrategySuccess() async throws {
        TestRemoteConfigHandler.responseHandler = TestRemoteConfigHandler.successResponseHandler()

        let didReceiveRemoteResponseExpecation = XCTestExpectation(description: "it did request remote config")
        didReceiveRemoteResponseExpecation.assertForOverFulfill = true

        let remoteConfigClient = makeRemoteConfigClient()
        remoteConfigClient.subscribe(deliveryMode: .waitForRemote()) { config, source, _ in
            switch source {
            case .cache:
                XCTFail()
            case .remote:
                didReceiveRemoteResponseExpecation.fulfill()
            }
        }

        await fulfillment(of: [didReceiveRemoteResponseExpecation], timeout: 3)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testWaitForRemoteDeliveryStrategyTimeout() async throws {
        let didSendRemoteRequestExpectation = XCTestExpectation(description: "it did request config")
        TestRemoteConfigHandler.responseHandler = { request in
            Thread.sleep(forTimeInterval: 2)
            didSendRemoteRequestExpectation.fulfill()
            return TestRemoteConfigHandler.successResponseHandler()(request)
        }

        let cachedRemoteConfigInfo = RemoteConfigClient.RemoteConfigInfo(config: ["cached": 1],
                                                                         lastFetch: Date.distantPast)

        let storage = RemoteConfigInMemoryStorage()
        try await storage.setConfig(cachedRemoteConfigInfo)

        let remoteConfigClient = makeRemoteConfigClient(storage: storage)

        let didReceiveLocalResponseExpecation = XCTestExpectation(description: "it did request remote config")
        didReceiveLocalResponseExpecation.assertForOverFulfill = true

        remoteConfigClient.subscribe(deliveryMode: .waitForRemote(timeout: 1)) { config, source, lastFetch in
            switch source {
            case .cache:
                XCTAssertEqual(config as? NSDictionary, cachedRemoteConfigInfo.config as NSDictionary)
                XCTAssertEqual(lastFetch, cachedRemoteConfigInfo.lastFetch)
                didReceiveLocalResponseExpecation.fulfill()
            case .remote:
                XCTFail()
            }
        }

        await fulfillment(of: [didReceiveLocalResponseExpecation, didSendRemoteRequestExpectation], timeout: 3)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testResponseContainsNull() async throws {
        let remoteConfig: RemoteConfigClient.RemoteConfig = [
            "remote": [
                "test1": NSNull(),
                "test2": [1, 2, NSNull()],
                "test3": [
                    "a": NSNull(),
                    "b": [NSNull(), 1, 2, "c"]
                ],
                "test4": true,
            ]
        ]
        TestRemoteConfigHandler.responseHandler = TestRemoteConfigHandler.successResponseHandler(remoteConfig)

        let normalizedRemoteConfig: RemoteConfigClient.RemoteConfig = [
            "remote": [
                "test2": [1, 2],
                "test3": [
                    "b": [1, 2, "c"],
                ],
                "test4": true,
            ]
        ]

        let storage = RemoteConfigUserDefaultsStorage()
        try await storage.setConfig(nil)

        let remoteConfigClient = makeRemoteConfigClient(storage: storage)

        let didUpdateConfigExpectation = XCTestExpectation(description: "it did request config")
        remoteConfigClient.subscribe { config, source, lastFetch in
            switch source {
            case .cache:
                break
            case .remote:
                XCTAssertEqual(config as? NSDictionary, normalizedRemoteConfig as NSDictionary)
                didUpdateConfigExpectation.fulfill()
            }
        }

        await fulfillment(of: [didUpdateConfigExpectation], timeout: 3)

        let storedConfigInfo = try await storage.fetchConfig()
        XCTAssertEqual(storedConfigInfo?.config as? NSDictionary, normalizedRemoteConfig as NSDictionary)
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func testValidJsonDataTypes() async throws {

        func verifyRemoteConfig(input: [String: Any], expected: [String: Any]) async throws {
            TestRemoteConfigHandler.responseHandler = TestRemoteConfigHandler.successResponseHandler(input)

            let storage = RemoteConfigUserDefaultsStorage()
            try await storage.setConfig(nil)

            let remoteConfigClient = makeRemoteConfigClient(storage: storage)

            let didUpdateConfigExpectation = XCTestExpectation(description: "it did request config")
            remoteConfigClient.subscribe { config, source, lastFetch in
                switch source {
                case .cache:
                    break
                case .remote:
                    XCTAssertEqual(config as? NSDictionary, expected as NSDictionary)
                    didUpdateConfigExpectation.fulfill()
                }
            }

            await fulfillment(of: [didUpdateConfigExpectation], timeout: 3)

            let storedConfigInfo = try await storage.fetchConfig()
            XCTAssertEqual(storedConfigInfo?.config as? NSDictionary, expected as NSDictionary)
        }

        // Minimal valid
        try await verifyRemoteConfig(input: [:], expected: [:])

        // Nested structures
        let nested: [String: Any] = [
            "user": [
                "id": 123,
                "name": "Alice",
                "profile": [
                    "age": 30,
                    "languages": ["Swift", "Objective-C", "Klingon"],
                ]
            ],
            "active": true,
        ]
        try await verifyRemoteConfig(input: nested, expected: nested)

        // Mixed numeric types
        let mixedNumbers: [String: Any] = [
            "int": 42,
            "double": 3.14159,
            "float": Float(2.71828),
            "big": 9_223_372_036_854_775_807, // Int64.max
        ]
        try await verifyRemoteConfig(input: mixedNumbers, expected: mixedNumbers)

        // Weird keys
        let weirdKeys: [String: Any] = [
            " spaces ": "value",
            "emoji😊": "smile",
            "quotes\"inside": "escaped",
            "backslash\\": "slash",
            "null\0char": "nullbyte",
        ]
        try await verifyRemoteConfig(input: weirdKeys, expected: weirdKeys)

        // Nulls and optionals
        let nulls: [String: Any] = [
            "present": "data",
            "missing": NSNull(),
        ]
        try await verifyRemoteConfig(input: nulls, expected: ["present": "data"])

        // Deep nesting
        let deepNest: [String: Any] = [
            "level1": [
                "level2": [
                    "level3": [
                        "level4": [
                            "value": "bottom",
                        ]
                    ]
                ]
            ]
        ]
        try await verifyRemoteConfig(input: deepNest, expected: deepNest)

        // Mixed arrays
        let mixedArray: [String: Any] = [
            "array": [1, "two", ["three": 3], true]
        ]
        try await verifyRemoteConfig(input: mixedArray, expected: mixedArray)

        // Unicode stress
        let unicode: [String: Any] = [
            "japanese": "こんにちは",
            "arabic": "مرحبا",
            "combining": "e\u{0301}", // é as e + accent
            "rightToLeft": "\u{202E}txet", // RTL override
        ]
        try await verifyRemoteConfig(input: unicode, expected: unicode)

        // Special number formats
        let numbersAsStrings: [String: Any] = [
            "hexString": "0x1A",
            "expNotation": 1.2e+10,
            "negativeZero": -0.0,
        ]
        try await verifyRemoteConfig(input: numbersAsStrings, expected: numbersAsStrings)
    }

    func testInvalidJsonDataTypes() async throws {

        func verifyRemoteConfig(input: String) async throws {
            TestRemoteConfigHandler.responseHandler = TestRemoteConfigHandler.rawResponseHandler(input)

            let storage = RemoteConfigUserDefaultsStorage()
            try await storage.setConfig(nil)

            let remoteConfigClient = makeRemoteConfigClient(storage: storage)

            let didUpdateConfigExpectation = XCTestExpectation(description: "it did request config")
            remoteConfigClient.subscribe { config, source, lastFetch in
                switch source {
                case .cache:
                    break
                case .remote:
                    XCTAssertNil(config)
                    didUpdateConfigExpectation.fulfill()
                }
            }

            await fulfillment(of: [didUpdateConfigExpectation], timeout: 3)

            let storedConfigInfo = try await storage.fetchConfig()
            XCTAssertNil(storedConfigInfo)
        }

        let empty = ""
        try await verifyRemoteConfig(input: empty)

        let emptyKey = "{\"\": 123}"
        try await verifyRemoteConfig(input: emptyKey)

        let missingQuotes = """
        {
          unquotedKey: "value"
        }
        """
        try await verifyRemoteConfig(input: missingQuotes)

        let singleQuotes = """
        {
          'key': 'value'
        }
        """
        try await verifyRemoteConfig(input: singleQuotes)

        let trailingComma = """
        {
          "a": 1,
        }
        """
        try await verifyRemoteConfig(input: trailingComma)

        let nanInfinity = """
        {
          "nan": NaN,
          "inf": Infinity
        }
        """
        try await verifyRemoteConfig(input: nanInfinity)

        let controlChars = """
        {
          "key": "value\u{0001}"
        }
        """
        try await verifyRemoteConfig(input: controlChars)

        let extraBrace = """
        {
          "key": "value"
        }}
        """
        try await verifyRemoteConfig(input: extraBrace)

        let danglingColon = """
        {
          "key":
        }
        """
        try await verifyRemoteConfig(input: danglingColon)

        let mixedTopLevel = """
        {
          "a": 1
        }
        [2, 3]
        """
        try await verifyRemoteConfig(input: mixedTopLevel)

        let badUnicodeEscape = """
        {
          "emoji": "\\uD83D"
        }
        """
        try await verifyRemoteConfig(input: badUnicodeEscape)
    }

    // MARK: - Util

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    private func makeRemoteConfigClient(storage: RemoteConfigStorage = RemoteConfigInMemoryStorage()) -> RemoteConfigClient {
        return RemoteConfigClient(apiKey: Self.apiKey,
                                  serverUrl: Self.serverUrl,
                                  storage: storage,
                                  urlSessionConfiguration: Self.testSessionConfiguration,
                                  maxRetryDelay: 0.1)
    }
}

// MARK: RemoteConfigInMemoryStorage

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class RemoteConfigInMemoryStorage: RemoteConfigStorage, @unchecked Sendable {

    private var remoteConfigInfo: RemoteConfigClient.RemoteConfigInfo?

    func fetchConfig() async throws -> RemoteConfigClient.RemoteConfigInfo? {
        return remoteConfigInfo
    }

    func setConfig(_ config: RemoteConfigClient.RemoteConfigInfo?) async throws {
        remoteConfigInfo = config
    }
}

// MARK: TestRemoteConfigHandler
// A basic echo response that returns {"config": true} for every requested config

class TestRemoteConfigHandler: URLProtocol {

    enum TestRemoteConfigHandlerError: Error {
        case invalidRequest
    }

    typealias ResponseHandler = (URLRequest) -> (URLResponse, Data?)

    static var responseHandler: ResponseHandler? = nil

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let responseHandler = Self.responseHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown))
            return
        }

        let baseUrl = request.url.flatMap {
            var components = URLComponents(url: $0, resolvingAgainstBaseURL: false)
            components?.queryItems = nil
            return components?.url?.absoluteString
        }
        XCTAssertEqual(baseUrl, "\(RemoteConfigTests.serverUrl)/\(RemoteConfigTests.apiKey)")

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
        //no-op
    }

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    static func successResponseHandler(_ config: RemoteConfigClient.RemoteConfig = ["config": true]) -> ResponseHandler {
        return { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, nil)
            }

            let response = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!

            let data = try? JSONSerialization.data(withJSONObject: ["configs": config])

            return (response, data)
        }
    }

    static func errorResponseHandler(statusCode: Int = 400) -> ResponseHandler {
        return { request in
            return (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, nil)
        }
    }

    static func rawResponseHandler(_ responseBody: String) -> ResponseHandler {
        return { request in
            guard let url = request.url else {
                return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, nil)
            }

            let response = HTTPURLResponse(url: url,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!

            return (response, responseBody.data(using: .utf8))
        }
    }
}
