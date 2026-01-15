//
//  DiagnosticsClient.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 10/22/25.
//

import Foundation

let US_SERVER_URL = "https://diagnostics.prod.us-west-2.amplitude.com/v1/capture"
let EU_SERVER_URL = "https://diagnostics.prod.eu-central-1.amplitude.com/v1/capture"

@usableFromInline let DEFAULT_SAMPLE_RATE: Double = 0
@usableFromInline let DEFAULT_FLUSH_INTERVAL: UInt64 = 300

@_spi(Internal)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor DiagnosticsClient: CoreDiagnostics {

    public typealias StateCallback = @Sendable () -> Void

    private let apiKey: String
    private let logger: CoreLogger
    let storage: DiagnosticsStorage
    private let urlSession: URLSession
    private let serverUrl: String
    private let startTimestamp: TimeInterval
    private let flushIntervalNanoSec: UInt64
    private(set) var shouldTrack: Bool
    private var enableCrashTracking: Bool = false

    private var remoteConfigClient: RemoteConfigClient?

    private var enabled: Bool
    private var sampleRate: Double
    private nonisolated(unsafe) var remoteConfigSubscription: Sendable?

    private var didSetBasicTags: Bool = false
    private var didRegisterCrashTracking: Bool = false
    private var didFlushPreviousSession = false

    var flushTask: Task<Void, Never>?

    private(set) nonisolated(unsafe) var initializationTask: Task<Void, Never>?

    public init(apiKey: String,
                serverZone: ServerZone = .US,
                instanceName: String,
                logger: CoreLogger = OSLogger(logLevel: .error),
                enabled: Bool = true,
                sampleRate: Double = DEFAULT_SAMPLE_RATE,
                crashCaptureEnabled: Bool = false,
                remoteConfigClient: RemoteConfigClient?,
                flushIntervalNanoSec: UInt64 = DEFAULT_FLUSH_INTERVAL * NSEC_PER_SEC,
                urlSessionConfiguration: URLSessionConfiguration = .ephemeral) {
        let startTimestamp = Date().timeIntervalSince1970
        self.apiKey = apiKey
        self.logger = logger
        self.startTimestamp = startTimestamp
        self.flushIntervalNanoSec = flushIntervalNanoSec
        self.serverUrl = serverZone == .EU ? EU_SERVER_URL : US_SERVER_URL
        self.urlSession = URLSession(configuration: urlSessionConfiguration)

        self.enabled = enabled
        let clampedSampleRate = max(0.0, min(1.0, sampleRate))
        self.sampleRate = clampedSampleRate
        let shouldTrack = enabled && Sample.isInSample(seed: String(startTimestamp), sampleRate: clampedSampleRate)
        self.shouldTrack = shouldTrack

        self.storage = DiagnosticsStorage(instanceName: instanceName,
                                          sessionStartAt: startTimestamp,
                                          logger: logger,
                                          shouldStore: shouldTrack)

        self.remoteConfigClient = remoteConfigClient
        remoteConfigSubscription = remoteConfigClient?.subscribe(key: Constants.RemoteConfig.Key.diagnostics) { [weak self] config, _, _ in
            guard let config else { return }

            Task {
                let enabled = config["enabled"] as? Bool
                let sampleRate = config["sampleRate"] as? Double

                var enableCrashTracking: Bool? = nil
                if let availabilities = config["availabilities"] as? [String: String],
                   let availableFrom = availabilities["CrashTracking"],
                   let available = try? AmplitudeContext.coreLibraryVersion.isGreaterThanOrEqualToVersion(availableFrom) {
                    enableCrashTracking = available
                }

                await self?.updateConfig(enabled: enabled, sampleRate: sampleRate, enableCrashTracking: enableCrashTracking)
            }
        }

        initializationTask = Task {
            await self.initializeTasksIfNeeded()
        }
    }

    public func setTag(name: String, value: String) async {
        await storage.setTag(name: name, value: value)
        startFlushTimerIfNeeded()
    }

    public func setTags(_ tags: [String: String]) async {
        await storage.setTags(tags)
        startFlushTimerIfNeeded()
    }

    public func increment(name: String, size: Int) async {
        await storage.increment(name: name, size: size)
        startFlushTimerIfNeeded()
    }

    public func recordHistogram(name: String, value: Double) async {
        await storage.recordHistogram(name: name, value: value)
        startFlushTimerIfNeeded()
    }

    public func recordEvent(name: String, properties: [String: any Sendable]? = nil) async {
        await storage.recordEvent(name: name, properties: properties)
        startFlushTimerIfNeeded()
    }

    public func flush() async {
        guard shouldTrack, await storage.didChanged else { return }
        let snapshot = await storage.dumpAndClearCurrentSession()
        await uploadSnapshot(snapshot)
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

    func updateConfig(enabled: Bool? = nil, sampleRate: Double? = nil, enableCrashTracking: Bool? = nil) async {
        if let enabled {
            self.enabled = enabled
        }
        if let sampleRate {
            let clampedRate = max(0.0, min(1.0, sampleRate))
            self.sampleRate = clampedRate
        }
        if let enableCrashTracking {
            self.enableCrashTracking = enableCrashTracking
        }

        shouldTrack = self.enabled && Sample.isInSample(seed: String(self.startTimestamp), sampleRate: self.sampleRate)
        await storage.setShouldStore(shouldTrack)
        await self.initializeTasksIfNeeded()
    }

    func initializeTasksIfNeeded() async {
        async let previous: () = self.flushPreviousSessions()
        async let basicTags: () = self.setupBasicDiagnosticsTags()
        async let crashCatch: () = self.setupCrashCatch()

        _ = await (previous, basicTags, crashCatch)
    }

    deinit {
        if let remoteConfigSubscription {
            remoteConfigClient?.unsubscribe(remoteConfigSubscription)
        }
        
        initializationTask?.cancel()
        flushTask?.cancel()
    }

    // MARK: - Flush Timer
    func startFlushTimerIfNeeded() {
        guard shouldTrack, flushTask == nil else { return }

        let flushInterval = self.flushIntervalNanoSec
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: flushInterval)
            guard let self else { return }
            await self.flush()
            await self.markFlushTimerFinished()
        }
    }

    func stopFlushTimer() {
        flushTask?.cancel()
        flushTask = nil
    }

    func waitForPendingFlushTask() async throws {
        await flushTask?.value
    }

    private func markFlushTimerFinished() {
        flushTask = nil
    }

    // MARK: - Initialization Tasks

    func flushPreviousSessions() async {
        guard enabled, !didFlushPreviousSession else { return }
        didFlushPreviousSession = true

        let historicSnapshots = await storage.loadAndClearPreviousSessions()

        for snapshot in historicSnapshots {
            await uploadSnapshot(snapshot)
        }
    }

    private func setupBasicDiagnosticsTags() async {
        guard !didSetBasicTags else { return }
        didSetBasicTags = true

        await increment(name: "sampled.in.and.enabled")

        var staticContext = [String: String]()

        let info = Bundle.main.infoDictionary
        staticContext["version_name"] = info?["CFBundleShortVersionString"] as? String ?? ""

        let device = await CoreDevice.current
        staticContext["device_manufacturer"] = await device.manufacturer
        staticContext["device_model"] = await device.model
        staticContext["os_name"] = await device.os_name
        staticContext["os_version"] = await device.os_version
        staticContext["platform"] = await device.platform

        staticContext["sdk.\(AmplitudeContext.coreLibraryName).version"] = AmplitudeContext.coreLibraryVersion

        await self.setTags(staticContext)
    }

    private func setupCrashCatch() async {
        guard enabled, enableCrashTracking, !didRegisterCrashTracking else { return }
        didRegisterCrashTracking = true

        CrashCatcher.register()

        if let crash = CrashCatcher.checkForPreviousCrash() {
            CrashCatcher.clearCrashReport()
            await increment(name: "analytics.crash")
            let eventProperties = ["report": crash]
            await recordEvent(name: "analytics.crash", properties: eventProperties)
        }
    }
}
