@_spi(Internal) @testable import AmplitudeCore
import Foundation
import XCTest

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class RemoteConfigPersistedThrottleTests: XCTestCase {
    private let httpClient = TestRemoteConfigHandler()
    private var instanceName: String!

    override func setUp() {
        super.setUp()
        instanceName = "persisted-throttle-\(UUID().uuidString)"
    }

    override func tearDown() {
        for key in [RemoteConfigTests.apiKey, "other-key"] {
            for zone in [ServerZone.US, .EU] {
                let suite = "com.amplitude.remoteconfig.cache.\(instanceName!).\(zone.rawValue).\(Data(key.utf8).base64EncodedString())"
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
        }
        let legacySuite = "com.amplitude.remoteconfig.cache.\(instanceName!)"
        UserDefaults(suiteName: legacySuite)?.removePersistentDomain(forName: legacySuite)
        super.tearDown()
    }

    func testNewClientReusesPersistedFetchForBothDeliveryModes() async throws {
        httpClient.responseHandler = TestRemoteConfigHandler.successResponseHandler()
        let first = makeClient(storage: makeStorage())
        await expectConfig(from: first, mode: .waitForRemote(), source: .remote)
        XCTAssertEqual(httpClient.requestCount, 1)

        let unexpectedRequest = XCTestExpectation(description: "fresh persisted cache skips network")
        unexpectedRequest.isInverted = true
        httpClient.responseHandler = { request in
            unexpectedRequest.fulfill()
            return await TestRemoteConfigHandler.successResponseHandler()(request)
        }

        // Separate storage and client instances must recover freshness from disk.
        let second = makeClient(storage: makeStorage())
        await expectConfig(from: second, mode: .all, source: .cache)
        await expectConfig(from: second, mode: .waitForRemote(), source: .cache)
        first.updateConfigs()
        second.updateConfigs()
        await fulfillment(of: [unexpectedRequest], timeout: 0.1)
        XCTAssertEqual(httpClient.requestCount, 1)
    }

    func testPersistedCooldownExpiresAtFifteenMinutesAndRefreshReachesSubscribers() async throws {
        let dateProvider = TestDateProvider()
        let cached = RemoteConfigClient.RemoteConfigInfo(config: ["config": true], lastFetch: dateProvider.getDate())
        try await makeStorage().setConfig(cached)
        let client = makeClient(storage: makeStorage(), dateProvider: dateProvider)
        let cacheDelivery = XCTestExpectation(description: "initial cached config")
        cacheDelivery.assertForOverFulfill = true
        let remoteDelivery = XCTestExpectation(description: "refresh after expiry")
        remoteDelivery.assertForOverFulfill = true
        client.subscribe(deliveryMode: .waitForRemote()) { config, source, timestamp in
            XCTAssertEqual(config as? NSDictionary, ["config": true] as NSDictionary)
            switch source {
            case .cache:
                XCTAssertEqual(timestamp, cached.lastFetch)
                cacheDelivery.fulfill()
            case .remote:
                XCTAssertEqual(timestamp, dateProvider.getDate())
                remoteDelivery.fulfill()
            }
        }
        await fulfillment(of: [cacheDelivery], timeout: 3)

        let earlyRequest = XCTestExpectation(description: "no fetch before fifteen minutes")
        earlyRequest.isInverted = true
        httpClient.responseHandler = { request in
            earlyRequest.fulfill()
            return await TestRemoteConfigHandler.successResponseHandler()(request)
        }
        dateProvider.advance(by: 899)
        client.updateConfigs()
        await fulfillment(of: [earlyRequest], timeout: 0.1)
        XCTAssertEqual(httpClient.requestCount, 0)

        httpClient.responseHandler = TestRemoteConfigHandler.successResponseHandler()
        dateProvider.advance(by: 1)
        client.updateConfigs()
        await fulfillment(of: [remoteDelivery], timeout: 3)
        XCTAssertEqual(httpClient.requestCount, 1)
        let persisted = try await makeStorage().fetchConfig()
        XCTAssertEqual(persisted?.lastFetch, dateProvider.getDate())
    }

    func testStalePastAndFutureTimestampsAllowFetching() async throws {
        let dateProvider = TestDateProvider()
        httpClient.responseHandler = TestRemoteConfigHandler.successResponseHandler()
        for offset in [-1_200.0, 1_200.0] {
            let storage = RemoteConfigInMemoryStorage()
            try await storage.setConfig(.init(config: ["old": true], lastFetch: dateProvider.getDate().addingTimeInterval(offset)))
            let client = makeClient(storage: storage, dateProvider: dateProvider)
            await expectConfig(from: client, mode: .waitForRemote(), source: .remote)
            let persisted = try await storage.fetchConfig()
            XCTAssertEqual(persisted?.lastFetch, dateProvider.getDate())
        }
        XCTAssertEqual(httpClient.requestCount, 2)
    }

    func testRecentFutureTimestampRemainsThrottled() async throws {
        let dateProvider = TestDateProvider()
        let storage = RemoteConfigInMemoryStorage()
        try await storage.setConfig(.init(config: ["config": true], lastFetch: dateProvider.getDate().addingTimeInterval(600)))
        let client = makeClient(storage: storage, dateProvider: dateProvider)
        await expectConfig(from: client, mode: .waitForRemote(), source: .cache)
        XCTAssertEqual(httpClient.requestCount, 0)
    }

    func testStorageFailureStillFetchesAndKeepsInMemoryThrottle() async throws {
        httpClient.responseHandler = TestRemoteConfigHandler.successResponseHandler()
        let client = makeClient(storage: FailingStorage())
        await expectConfig(from: client, mode: .waitForRemote(), source: .remote)

        let unexpectedRequest = XCTestExpectation(description: "successful fetch remains throttled when persistence fails")
        unexpectedRequest.isInverted = true
        httpClient.responseHandler = { request in
            unexpectedRequest.fulfill()
            return await TestRemoteConfigHandler.successResponseHandler()(request)
        }
        client.updateConfigs()
        await fulfillment(of: [unexpectedRequest], timeout: 0.1)
        XCTAssertEqual(httpClient.requestCount, 1)
    }

    func testPersistedCacheIsScopedToProjectAndServerZone() async throws {
        let cached = RemoteConfigClient.RemoteConfigInfo(config: ["config": true], lastFetch: Date())
        let legacy = RemoteConfigUserDefaultsStorage(instanceName: instanceName)
        try await legacy.setConfig(cached)
        let unknownOwner = try await makeStorage().fetchConfig()
        XCTAssertNil(unknownOwner, "Legacy caches cannot identify their project or server zone")

        try await makeStorage().setConfig(cached)
        let sameProject = try await makeStorage().fetchConfig()
        XCTAssertEqual(sameProject?.lastFetch, cached.lastFetch)

        let otherProject = RemoteConfigUserDefaultsStorage(instanceName: instanceName, apiKey: "other-key", serverZone: .US)
        let otherZone = RemoteConfigUserDefaultsStorage(instanceName: instanceName, apiKey: RemoteConfigTests.apiKey, serverZone: .EU)
        let projectConfig = try await otherProject.fetchConfig()
        let zoneConfig = try await otherZone.fetchConfig()
        XCTAssertNil(projectConfig)
        XCTAssertNil(zoneConfig)
    }

    private func makeStorage() -> RemoteConfigUserDefaultsStorage {
        return RemoteConfigUserDefaultsStorage(instanceName: instanceName, apiKey: RemoteConfigTests.apiKey, serverZone: .US)
    }

    private func makeClient(storage: RemoteConfigStorage, dateProvider: DateProvider = DateProvider()) -> RemoteConfigClient {
        return RemoteConfigClient(apiKey: RemoteConfigTests.apiKey,
                                  serverUrl: RemoteConfigTests.serverUrl,
                                  storage: storage,
                                  maxRetryDelay: 0.1,
                                  dateProvider: dateProvider,
                                  httpClient: httpClient)
    }

    private func expectConfig(from client: RemoteConfigClient, mode: RemoteConfigClient.DeliveryMode,
                              source: RemoteConfigClient.Source) async {
        let delivery = XCTestExpectation(description: "received config with expected source")
        delivery.assertForOverFulfill = true
        client.subscribe(deliveryMode: mode) { config, deliveredSource, timestamp in
            XCTAssertEqual(deliveredSource, source)
            XCTAssertEqual(config as? NSDictionary, ["config": true] as NSDictionary)
            XCTAssertNotNil(timestamp)
            delivery.fulfill()
        }
        await fulfillment(of: [delivery], timeout: 3)
    }

    private final class TestDateProvider: DateProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_700_000_000)

        override func getDate() -> Date { lock.withLock { date } }

        func advance(by interval: TimeInterval) {
            lock.withLock { date.addTimeInterval(interval) }
        }
    }

    private struct FailingStorage: RemoteConfigStorage {
        func fetchConfig() async throws -> RemoteConfigClient.RemoteConfigInfo? {
            throw RemoteConfigClient.RemoteConfigError.notInCache
        }

        func setConfig(_ config: RemoteConfigClient.RemoteConfigInfo?) async throws {
            throw RemoteConfigClient.RemoteConfigError.badResponse
        }
    }
}
