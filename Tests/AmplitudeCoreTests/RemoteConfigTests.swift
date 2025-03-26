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
        makeRemoteConfigClient(storage: storage).subscribe { config, source, lastFetch in
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

        makeRemoteConfigClient().subscribe(deliveryMode: .waitForRemote()) { config, source, _ in
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

    // MARK: - Util

    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    private func makeRemoteConfigClient(storage: RemoteConfigStorage = RemoteConfigInMemoryStorage()) -> RemoteConfigClient {
        return RemoteConfigClient(apiKey: "",
                                  serverUrl: "http://www.amplitude.com",
                                  storage: storage,
                                  urlSessionConfiguration: Self.testSessionConfiguration)
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
}
