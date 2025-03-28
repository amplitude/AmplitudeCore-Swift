//
//  RemoteConfigClient.swift
//  Amplitude-Swift
//
//  Created by Chris Leonavicius on 1/14/25.
//

import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
protocol RemoteConfigStorage: Sendable {
    func fetchConfig() async throws -> RemoteConfigClient.RemoteConfigInfo?
    func setConfig(_ config: RemoteConfigClient.RemoteConfigInfo?) async throws
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor RemoteConfigClient: NSObject {

    public enum DeliveryMode: Sendable {
        // Recieve all config updates as they occur
        case all

        // Waits for a remote response until the given timeout, then return a cached copy, if available.
        case waitForRemote(timeout: TimeInterval = 3)
    }

    public enum Source: Sendable {
        case cache
        case remote
    }

    public enum RemoteConfigError: Error {
        case notInCache
        case invalidServerURL
        case badResponse
        case preInit
    }

    struct Config {
        static let usServerURL = "https://sr-client-cfg.amplitude.com/config"
        static let euServerURL = "https://sr-client-cfg.eu.amplitude.com/config"
        static let maxRetries = 3
        static let minTimeBetweenFetches: TimeInterval = 5 * 60
        static let fetchedKeys = [
            "sessionReplay.sr_ios_privacy_config",
            "sessionReplay.sr_ios_sampling_config",
            "analyticsSDK.browserSDK",
        ]
    }

    private class CallbackInfo {
        let id: UUID
        let key: String?
        let deliveryMode: DeliveryMode
        let callback: RemoteConfigCallback

        var lastCallbackTime: Date?

        init(id: UUID,
             key: String?,
             deliveryMode: DeliveryMode,
             callback: @escaping RemoteConfigCallback) {
            self.id = id
            self.key = key
            self.deliveryMode = deliveryMode
            self.callback = callback
        }
    }

    struct RemoteConfigInfo: Sendable {
        let config: RemoteConfig
        let lastFetch: Date
    }

    public typealias RemoteConfig = [String: Sendable]
    public typealias RemoteConfigCallback = @Sendable (RemoteConfig?, Source, Date?) -> Void

    private let apiKey: String
    private let serverUrl: String
    private let urlSession: URLSession
    private let queue = DispatchQueue(label: "com.amplitude.sessionreplay.remoteconfig", target: .global())
    private let jsonDecoder = JSONDecoder()
    private let storage: RemoteConfigStorage
    private let logger: Logger

    private var fetchLocalTask: Task<RemoteConfigInfo, Error>
    private var fetchRemoteTask: Task<RemoteConfigInfo, Error>
    private var callbacks: [CallbackInfo] = []

    public init(apiKey: String,
                serverZone: ServerZone,
                instanceName: String? = nil,
                logger: Logger) {
        let serverURL: String
        switch serverZone {
        case .US:
            serverURL = Config.usServerURL
        case .EU:
            serverURL = Config.euServerURL
        }
        self.init(apiKey: apiKey,
                  serverUrl: serverURL,
                  logger: logger,
                  storage: RemoteConfigUserDefaultsStorage(instanceName: instanceName))
    }

    init(apiKey: String,
         serverUrl: String,
         logger: Logger = ConsoleLogger(),
         storage: RemoteConfigStorage = RemoteConfigUserDefaultsStorage(),
         urlSessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.apiKey = apiKey
        self.serverUrl = serverUrl
        self.logger = logger
        self.storage = storage
        self.urlSession = URLSession(configuration: urlSessionConfiguration)

        fetchLocalTask = Task {
            guard let config = try await storage.fetchConfig() else {
                throw RemoteConfigError.notInCache
            }
            return config
        }

        fetchRemoteTask = Task {
            throw RemoteConfigError.preInit
        }

        super.init()

        // Avoid self capture before super init
        fetchRemoteTask = Task {
            let config = try await fetch()
            try? await storage.setConfig(config)
            return config
        }
    }

    /**
     Subscribe for updates to remote config. Callback is guaranteed to be called at least once, whether we are able to fetch a config or not.

     - Parameters:
        - key: A String containing a series of period delimited keys to filter the returned config. Ie, {a: {b: {c: ...}}} would return {b: {c: ...} for "a" or {c: ...} for "a.b"
        - deliveryMode: How the initial callback is sent. See ``RemoteConfigClient/DeliveryMode`` for more details.
        - callback: A block that will be called when remote config is fetched.
     - Returns: A token that can be used to unsubscribe from updates
     */
    @discardableResult
    public nonisolated func subscribe(key: String? = nil,
                                      deliveryMode: DeliveryMode = .all,
                                      callback: @escaping RemoteConfigCallback) -> Any {
        let id = UUID()
        Task {
            await _subscribe(id: id, key: key, deliveryMode: deliveryMode, callback: callback)
        }
        return id
    }

    private func _subscribe(id: UUID,
                            key: String?,
                            deliveryMode: DeliveryMode,
                            callback: @escaping RemoteConfigCallback) {
        Task {
            let callbackInfo = CallbackInfo(id: id, key: key, deliveryMode: deliveryMode, callback: callback)
            callbacks.append(callbackInfo)

            switch callbackInfo.deliveryMode {
            case .all:
                Task {
                    await withThrowingTaskGroup(of: (configInfo: RemoteConfigInfo, source: Source).self) { [fetchLocalTask, fetchRemoteTask] taskGroup in
                        // send remote first, if it's already complete we can skip the cached response
                        taskGroup.addTask {
                            return (try await fetchRemoteTask.value, .remote)
                        }
                        await Task.yield()
                        taskGroup.addTask {
                            return (try await fetchLocalTask.value, .cache)
                        }
                        var didSendCallback = false
                        while let taskGroupResult = await taskGroup.nextResult() {
                            if case .success(let result) = taskGroupResult {
                                didSendCallback = true

                                sendCallback(callbackInfo, configInfo: result.configInfo, source: result.source)

                                // no need to send local callbacks if we already have remote
                                if case .remote = result.source {
                                    break
                                }
                            }
                        }

                        guard !didSendCallback else {
                            return
                        }

                        sendCallback(callbackInfo, configInfo: nil, source: .remote)
                    }
                }
            case .waitForRemote(timeout: let timeout):
                let fetchTask = Task {
                    let config = try await fetchRemoteTask.value
                    try Task.checkCancellation()
                    return config
                }

                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: UInt64(timeout * TimeInterval(NSEC_PER_SEC)))
                    try Task.checkCancellation()
                    fetchTask.cancel()
                }

                do {
                    let remoteConfig = try await fetchTask.value
                    timeoutTask.cancel()
                    sendCallback(callbackInfo, configInfo: remoteConfig, source: .remote)
                } catch {
                    // timeout or remote fetch error, try storage
                    if let localConfig = try? await fetchLocalTask.value {
                        sendCallback(callbackInfo, configInfo: localConfig, source: .cache)
                    } else {
                        sendCallback(callbackInfo, configInfo: nil, source: .remote)
                    }
                }
            }
        }
    }

    /**
     Removes a callback from receiving future updates.

     - Parameters:
     - token: the result of a subscribe call to unregister for future updates.
     */
    public nonisolated func unsubscribe(_ token: Any) {
        guard let uuid = token as? UUID else {
            return
        }
        Task {
            await _unsubscribe(id: uuid)
        }
    }

    private func _unsubscribe(id: UUID) {
        callbacks.removeAll { $0.id == id }
    }

    /**
     Requests that the Remote config client updates its configs.
     */
    public nonisolated func updateConfigs() {
        Task {
            try await _updateConfigs()
        }
    }

    private func _updateConfigs() async throws {
        // wait for any existing fetches to complete
        switch await fetchRemoteTask.result {
        case .success(let configInfo):
            guard configInfo.lastFetch.timeIntervalSinceNow < -Config.minTimeBetweenFetches else {
                logger.debug(message: "[RemoteConfigClient] Skipping updateConfigs: Too recent")
                return
            }
        case .failure:
            break
        }

        fetchRemoteTask = Task {
            let configInfo = try await fetch()
            try? await storage.setConfig(configInfo)
            return configInfo
        }

        if let updatedRemoteConfig = try? await fetchRemoteTask.value {
            for callback in callbacks {
                switch callback.deliveryMode {
                case .all:
                    break
                case .waitForRemote:
                    // Wait until the initial callback from subscribe is fired
                    guard callback.lastCallbackTime == nil else {
                        continue
                    }
                }

                sendCallback(callback, configInfo: updatedRemoteConfig, source: .remote)
            }
        }
    }

    private func sendCallback(_ callbackInfo: CallbackInfo, configInfo: RemoteConfigInfo?, source: Source) {
        callbackInfo.lastCallbackTime = Date()

        var filteredConfig: RemoteConfig?
        if let key = callbackInfo.key {
            filteredConfig = key.split(separator: ".").reduce(configInfo?.config) { config, currentKey in
                return config?[String(currentKey)] as? RemoteConfig
            }
        } else {
            filteredConfig = configInfo?.config
        }

        callbackInfo.callback(filteredConfig, source, configInfo?.lastFetch)
    }

    // MARK: - Fetch

    private func fetch(request: URLRequest? = nil, retries: Int = 3) async throws -> RemoteConfigInfo {
        let currentRequest = try request ?? makeRequest()
        let (data, response) = try await urlSession.data(for: currentRequest)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Sendable],
           let config = json["configs"] as? [String: Sendable] {
            return RemoteConfigInfo(config: config, lastFetch: Date())
        } else if retries > 0 {
            try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
            return try await fetch(request: currentRequest, retries: retries - 1)
        } else {
            throw RemoteConfigError.badResponse
        }
    }

    private func makeRequest() throws -> URLRequest {
        guard var urlComponents = URLComponents(string: serverUrl) else {
            throw RemoteConfigError.invalidServerURL
        }

        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "api_key", value: apiKey))

        for configKey in Config.fetchedKeys {
            queryItems.append(URLQueryItem(name: "config_keys", value: configKey))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw RemoteConfigError.invalidServerURL
        }

        return HttpUtil.makeJsonRequest(url: url)
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class RemoteConfigUserDefaultsStorage: RemoteConfigStorage, @unchecked Sendable {

    private struct Keys {
        static let config = "config"
        static let lastFetch = "lastFetch"
    }

    private let userDefaults: UserDefaults?

    init(instanceName: String? = nil) {
        var suiteName = "com.amplitude.remoteconfig.cache"
        if let instanceName {
            suiteName += "."
            suiteName += instanceName
        }
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    func fetchConfig() async throws -> RemoteConfigClient.RemoteConfigInfo? {
        guard let userDefaults,
              let config = userDefaults.object(forKey: Keys.config) as? RemoteConfigClient.RemoteConfig,
              let lastFetch = userDefaults.object(forKey: Keys.lastFetch) as? Date else {
            return nil
        }
        return RemoteConfigClient.RemoteConfigInfo(config: config, lastFetch: lastFetch)
    }

    func setConfig(_ configInfo: RemoteConfigClient.RemoteConfigInfo?) async throws {
        guard let userDefaults else {
            return
        }
        userDefaults.set(configInfo?.config, forKey: Keys.config)
        userDefaults.set(configInfo?.lastFetch, forKey: Keys.lastFetch)
    }
}
