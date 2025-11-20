//
//  DiagnosticsClient.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 10/22/25.
//

import Foundation

let US_SERVER_URL = "https://diagnostics.prod.us-west-2.amplitude.com/v1/capture"
let EU_SERVER_URL = "https://diagnostics.prod.eu-central-1.amplitude.com/v1/capture"

#if DEBUG
@usableFromInline let DEFAULT_SAMPLE_RATE: Double = 1.0
#else
@usableFromInline let DEFAULT_SAMPLE_RATE: Double = 0
#endif

@_spi(Internal)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor DiagnosticsClient: CoreDiagnostics {

    private let apiKey: String
    private let logger: CoreLogger
    internal let storage: DiagnosticsStorage
    private let urlSession: URLSession
    private let serverUrl: String
    private let startTimestamp: TimeInterval
    public private(set) var isRunning: Bool

    private var remoteConfigClient: RemoteConfigClient?

    private var enabled: Bool
    private var sampleRate: Double
    private nonisolated(unsafe) var remoteConfigSubscription: Sendable?

    var flushTask: Task<Void, Never>?
    
    private var isRunningContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private(set) var isRunningObserverTask: Task<Void, Never>?
    private var isRunningObserverId: UUID?
    private(set) nonisolated(unsafe) var initializationTask: Task<Void, Never>?

    public init(apiKey: String,
                serverZone: ServerZone = .US,
                instanceName: String,
                logger: CoreLogger = OSLogger(logLevel: .error),
                enabled: Bool = true,
                sampleRate: Double = DEFAULT_SAMPLE_RATE,
                remoteConfigClient: RemoteConfigClient?,
                urlSessionConfiguration: URLSessionConfiguration = .ephemeral) {
        let startTimestamp = Date().timeIntervalSince1970
        self.apiKey = apiKey
        self.logger = logger
        self.startTimestamp = startTimestamp
        self.serverUrl = serverZone == .EU ? EU_SERVER_URL : US_SERVER_URL
        self.urlSession = URLSession(configuration: urlSessionConfiguration)
        self.enabled = enabled
        self.sampleRate = sampleRate
        self.storage = DiagnosticsStorage(instanceName: instanceName,
                                          sessionStartAt: startTimestamp,
                                          logger: logger)
        let isRunning = enabled && Sample.isInSample(seed: String(startTimestamp), sampleRate: sampleRate)
        self.isRunning = isRunning
        self.remoteConfigClient = remoteConfigClient

        remoteConfigSubscription = remoteConfigClient?.subscribe(key: Constants.RemoteConfig.Key.diagnostics) { config, _, _ in
            guard let config else {
                return
            }

            Task { [weak self] in
                let enabled = config["enabled"] as? Bool
                let sampleRate = config["sample_rate"] as? Double
                await self?.updateConfig(enabled: enabled, sampleRate: sampleRate)
            }
        }

        initializationTask = Task { [weak self] in
            await self?.setupIsRunningObserver()
        }
    }

    private func setupIsRunningObserver() {
        let (stream, observerId) = observeIsRunning()
        isRunningObserverId = observerId
        isRunningObserverTask = Task { [weak self] in
            for await isRunning in stream {
                guard let self, isRunning else { continue }
                // Set basic diagnostics tags once and then unsubscribe

                async let flushOperation: Void = {
                    if await self.enabled {
                        await self.flushPreviousSessions()
                    }
                }()

                async let tagOperation: Void = await self.setBasicDiagnosticsTags()
                async let crashCheckOperation: Void = await self.setupCrashCatch()

                _ = await (flushOperation, tagOperation, crashCheckOperation)

                await self.cleanupIsRunningObserver()
                break
            }
        }
    }

    private func cleanupIsRunningObserver() {
        if let observerId = isRunningObserverId {
            stopObservingIsRunning(observerId)
            isRunningObserverId = nil
        }
        isRunningObserverTask?.cancel()
        isRunningObserverTask = nil
    }

    public func setTag(name: String, value: String) async {
        guard isRunning else { return }
        await storage.setTag(name: name, value: value)
        startFlushTimerIfNeeded()
    }

    public func setTags(_ tags: [String: String]) async {
        guard isRunning else { return }
        await storage.setTags(tags)
        startFlushTimerIfNeeded()
    }

    public func increment(name: String, size: Int) async {
        guard isRunning else { return }
        await storage.increment(name: name, size: size)
        startFlushTimerIfNeeded()
    }

    public func recordHistogram(name: String, value: Double) async {
        guard isRunning else { return }
        await storage.recordHistogram(name: name, value: value)
        startFlushTimerIfNeeded()
    }

    public func recordEvent(name: String, properties: [String: any Sendable]? = nil) async {
        guard isRunning else { return }
        await storage.recordEvent(name: name, properties: properties)
        startFlushTimerIfNeeded()
    }
    
    /// Observes changes to the `isRunning` state.
    /// - Returns: A tuple containing an AsyncStream that emits `Bool` values when `isRunning` changes,
    ///           and a UUID identifier that can be used to stop observing.
    /// - Note: The stream immediately yields the current `isRunning` value upon subscription.
    public func observeIsRunning() -> (stream: AsyncStream<Bool>, id: UUID) {
        let id = UUID()
        let currentValue = isRunning
        let stream = AsyncStream<Bool> { [weak self] continuation in
            // Send current value immediately
            continuation.yield(currentValue)
            // Store continuation for future updates
            Task {
                await self?.storeContinuation(continuation, for: id)
            }
        }
        return (stream, id)
    }
    
    /// Stops observing `isRunning` changes for the given subscription ID.
    /// - Parameter id: The UUID identifier returned from `observeIsRunning()`.
    public func stopObservingIsRunning(_ id: UUID) {
        isRunningContinuations[id]?.finish()
        isRunningContinuations.removeValue(forKey: id)
    }
    
    private func storeContinuation(_ continuation: AsyncStream<Bool>.Continuation, for id: UUID) {
        isRunningContinuations[id] = continuation
    }

    func flush() async {
        // Dump and clear data (keeps tags)
        let snapshot = await storage.dumpAndClear()
        await uploadSnapshot(snapshot)
    }

    func flushPreviousSessions() async {
        guard enabled else { return }
        // Load historic data from previous sessions and upload them
        let historicSnapshots = await storage.loadAndClearHistoricData()

        for snapshot in historicSnapshots {
            await uploadSnapshot(snapshot)
        }
    }

    func uploadSnapshot(_ snapshot: DiagnosticsSnapshot) async {
        let histogramResults = snapshot.histograms.mapValues {
            let avg = $0.count > 0 ? ($0.sum / Double($0.count) * 100).rounded() / 100 : 0.0
            return HistogramResult(count: $0.count, min: $0.min, max: $0.max, avg: avg)
        }
        let payload = DiagnosticsPayload(tags: snapshot.tags,
                                         counters: snapshot.counters,
                                         histogram: histogramResults,
                                         events: snapshot.events)

        guard let url = URL(string: self.serverUrl) else {
            self.logger.error(message: "DiagnosticsClient: Invalid server URL")
            return
        }

        var request = HttpUtil.makeJsonRequest(url: url)
        request.httpMethod = "POST"

        let bodyData = try? JSONEncoder().encode(payload)
        if let bodyData {
            request.httpBody = bodyData
            self.logger.debug(message: "DiagnosticsClient: Encoded payload: \(String(data: bodyData, encoding: .utf8) ?? "Failed to encode payload")")
        } else {
            self.logger.error(message: "DiagnosticsClient: Failed to encode payload")
        }

        request.setValue(self.apiKey, forHTTPHeaderField: "X-ApiKey")
        request.setValue(String(describing: self.sampleRate), forHTTPHeaderField: "X-Client-Sample-Rate")

        do {
            let (data, response) = try await self.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }
            guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
                let responseBody = String(data: data, encoding: .utf8)
                if let responseBody {
                    self.logger.error(message: "DiagnosticsClient: Failed to upload diagnostics: \(httpResponse.statusCode): \(responseBody)")
                } else {
                    self.logger.error(message: "DiagnosticsClient: Failed to upload diagnostics: \(httpResponse.statusCode)")
                }
                return
            }
            self.logger.debug(message: "DiagnosticsClient: Uploaded diagnostics")
        } catch {
            self.logger.error(message: "DiagnosticsClient: Failed to upload diagnostics: \(error)")
        }
    }

    func startFlushTimerIfNeeded() {
        guard flushTask == nil else { return }

        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300 * NSEC_PER_SEC) // 5 min
            guard let self else { return }
            await self.flush()
            await self.markFlushTimerFinished()
        }
    }

    func stopFlushTimer() {
        flushTask?.cancel()
        flushTask = nil
    }

    private func markFlushTimerFinished() {
        flushTask = nil
    }

    func persistIfNeeded() async {
        await storage.persistIfNeeded()
    }

    func updateConfig(enabled: Bool? = nil, sampleRate: Double? = nil) {
        if let enabled {
            self.enabled = enabled
        }
        if let sampleRate {
            let clampedRate = max(0.0, min(1.0, sampleRate))
            self.sampleRate = clampedRate
        }

        updateIsRunning()
    }

    private func updateIsRunning() {
        let oldValue = isRunning
        isRunning = enabled && Sample.isInSample(seed: String(self.startTimestamp), sampleRate: sampleRate)

        // Notify observers if value changed
        if oldValue != isRunning {
            for continuation in isRunningContinuations.values {
                continuation.yield(isRunning)
            }
        }
    }

    deinit {
        if let remoteConfigSubscription {
            remoteConfigClient?.unsubscribe(remoteConfigSubscription)
        }
        
        // Cancel initialization task
        initializationTask?.cancel()
        
        // Clean up isRunning observer
        isRunningObserverTask?.cancel()
        
        // Clean up all isRunning observers
        for continuation in isRunningContinuations.values {
            continuation.finish()
        }
        
        // Cancel flush task
        flushTask?.cancel()
    }

    private func setBasicDiagnosticsTags() async {
        await increment(name: "sampled.in.and.enabled")

        var staticContext = [String: String]()

        let info = Bundle.main.infoDictionary
        staticContext["version_name"] = info?["CFBundleShortVersionString"] as? String ?? ""

        let device = await CoreDevice.current
        staticContext["device_manufacturer"] = await device.manufacturer
        staticContext["device_model"] = await device.model
        staticContext["idfv"] = await device.identifierForVendor
        staticContext["os_name"] = await device.os_name
        staticContext["os_version"] = await device.os_version
        staticContext["platform"] = await device.platform

        staticContext["sdk.\(AmplitudeContext.coreLibraryName).version"] = AmplitudeContext.coreLibraryVersion

        await self.setTags(staticContext)
    }

    private func setupCrashCatch() async {
        CrashCatcher.register()

        if let crash = CrashCatcher.checkForPreviousCrash() {
            CrashCatcher.clearCrashReport()
            await increment(name: "analytics.crash")
            let eventProperties = ["report": crash]
            await recordEvent(name: "analytics.crash", properties: eventProperties)
        }
    }
}
