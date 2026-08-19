//
//  DiagnosticsStorage.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 10/27/25.
//

import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
actor DiagnosticsStorage {

    let instanceName: String
    let logger: CoreLogger
    let sessionStartAt: TimeInterval
    private let persistIntervalNanoSec: UInt64

    var tags: [String: String] = [:]
    var counters: [String: Int] = [:]
    var histograms: [String: HistogramStats] = [:]
    var events: [DiagnosticsEvent] = []

    var hasUnsavedTags = false
    var hasUnsavedCounters = false
    var hasUnsavedHistograms = false
    var unsavedEvents: [DiagnosticsEvent] = []

    var shouldStore: Bool = false

    private var persistenceTask: Task<Void, Never>?

    private static let storagePrefix: String = "com.amplitude.diagnostics"
    private static let maxEventsLogBytes: Int = 256 * 1024
    private static let newlineData = Data([0x0A])
    private static let maxEventCount: Int = 10

    private let sanitizedInstance: String
    private var storageDirectory: URL?

    private let liveSessionKey: String

    /// Session directories owned by a `DiagnosticsStorage` that is still alive in this process,
    /// reference counted so storages sharing a session key don't unregister each other.
    ///
    /// Several storages can share one instance name: every `AmplitudeContext` — and in
    /// Amplitude-Swift, every `Configuration` — builds its own `DiagnosticsClient`, each with a
    /// distinct `sessionStartAt`. Without this registry, `loadAndClearPreviousSessions()` cannot
    /// tell a sibling's *live* directory from a leftover of a previous launch, and deletes it.
    private nonisolated(unsafe) static var liveSessions: [String: Int] = [:]
    private static let liveSessionsLock = NSLock()

    init(instanceName: String, sessionStartAt: TimeInterval, logger: CoreLogger, shouldStore: Bool, persistIntervalNanoSec: UInt64 = NSEC_PER_SEC) {
        self.instanceName = instanceName
        self.logger = logger
        self.sessionStartAt = sessionStartAt
        let sanitizedInstance = instanceName.fnv1a64String()
        self.sanitizedInstance = sanitizedInstance
        self.persistIntervalNanoSec = persistIntervalNanoSec
        self.shouldStore = shouldStore
        // Registered up front rather than when the directory is first written, so a sibling
        // created in between can never observe this session as dead.
        self.liveSessionKey = Self.sessionKey(instance: sanitizedInstance,
                                              sessionStartAt: String(sessionStartAt))
        Self.registerLiveSession(liveSessionKey)
    }

    private static func sessionKey(instance: String, sessionStartAt: String) -> String {
        "\(instance)/\(sessionStartAt)"
    }

    private static func registerLiveSession(_ key: String) {
        liveSessionsLock.lock()
        defer { liveSessionsLock.unlock() }
        liveSessions[key, default: 0] += 1
    }

    private static func unregisterLiveSession(_ key: String) {
        liveSessionsLock.lock()
        defer { liveSessionsLock.unlock() }
        guard let count = liveSessions[key] else { return }
        if count <= 1 {
            liveSessions.removeValue(forKey: key)
        } else {
            liveSessions[key] = count - 1
        }
    }

    private static func isLiveSession(_ key: String) -> Bool {
        liveSessionsLock.lock()
        defer { liveSessionsLock.unlock() }
        return liveSessions[key] != nil
    }

    func setShouldStore(_ shouldStore: Bool) {
        self.shouldStore = shouldStore
        if shouldStore {
            startPersistenceTimerIfNeeded()
        } else {
            stopPersistenceTimer()
            try? removeAllStoredFiles()
        }
    }

    var hasUnsavedData: Bool {
        hasUnsavedTags || hasUnsavedCounters || hasUnsavedHistograms || !unsavedEvents.isEmpty
    }

    var didChanged: Bool {
        !(counters.isEmpty && histograms.isEmpty && events.isEmpty)
    }

    func setTag(name: String, value: String) {
        tags[name] = value
        hasUnsavedTags = true
        startPersistenceTimerIfNeeded()
    }

    func setTags(_ newTags: [String: String]) {
        tags.merge(newTags, uniquingKeysWith: { _, new in new })
        hasUnsavedTags = true
        startPersistenceTimerIfNeeded()
    }

    func getTag(name: String) -> String? {
        tags[name]
    }

    func getTags() -> [String: String] {
        tags
    }

    func increment(name: String, size: Int = 1) {
        counters[name] = (counters[name] ?? 0) + size
        hasUnsavedCounters = true
        startPersistenceTimerIfNeeded()
    }

    func recordHistogram(name: String, value: Double) {
        var stats = histograms[name] ?? HistogramStats()
        stats.count += 1
        stats.sum += value
        stats.min = min(stats.min, value)
        stats.max = max(stats.max, value)
        histograms[name] = stats
        hasUnsavedHistograms = true
        startPersistenceTimerIfNeeded()
    }

    func recordEvent(name: String, properties: [String: any Sendable]? = nil) {
        guard events.count < Self.maxEventCount else {
            logger.debug(message: "DiagnosticsStorage: Event limit reached")
            return
        }
        let event = DiagnosticsEvent(eventName: name,
                                     time: Date().timeIntervalSince1970,
                                     eventProperties: properties)
        events.append(event)
        unsavedEvents.append(event)
        startPersistenceTimerIfNeeded()
    }

    /// Dumps all diagnostic data and clears counters, histograms, and events (keeping tags)
    /// - Returns: Tuple containing all current diagnostic data
    func dumpAndClearCurrentSession() -> DiagnosticsSnapshot? {
        guard didChanged else { return nil }
        let snapshot = DiagnosticsSnapshot(tags: tags, counters: counters, histograms: histograms, events: events)

        // Clear in-memory data (keep tags)
        counters.removeAll()
        histograms.removeAll()
        events.removeAll()
        unsavedEvents.removeAll()
        hasUnsavedCounters = false
        hasUnsavedHistograms = false

        // Remove files (keep tags file)
        do {
            try removeFiles(includeTags: false)
        } catch {
            logger.error(message: "DiagnosticsStorage: Failed to remove files during dump: \(error)")
        }

        return snapshot
    }

    /// Loads all historic diagnostic data from filesystem and clears those folders
    /// - Returns: Array of diagnostic snapshots from previous sessions
    func loadAndClearPreviousSessions() -> [DiagnosticsSnapshot] {
        var snapshots: [DiagnosticsSnapshot] = []

        do {
            let fileManager = FileManager.default
            let baseDirectory = try Storage.rootDirectoryURL(fileManager: fileManager, createIfNeeded: true)

            let instanceDirectory = baseDirectory
                .appendingPathComponent(Self.storagePrefix, isDirectory: true)
                .appendingPathComponent(sanitizedInstance, isDirectory: true)

            guard fileManager.fileExists(atPath: instanceDirectory.path) else {
                return snapshots
            }

            let sessionDirs = try fileManager.contentsOfDirectory(
                at: instanceDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let currentSessionStartAt = String(sessionStartAt)

            for sessionDir in sessionDirs {
                guard let resourceValues = try? sessionDir.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    continue
                }

                let sessionStartAt = sessionDir.lastPathComponent

                // Skip the current session, and any session still owned by a live storage in this
                // process. Claiming a live sibling's directory would upload data it is still
                // holding in memory (double counting it on the next flush) and leave the sibling
                // writing into a directory that no longer exists.
                if sessionStartAt == currentSessionStartAt
                    || Self.isLiveSession(Self.sessionKey(instance: sanitizedInstance,
                                                          sessionStartAt: sessionStartAt)) {
                    continue
                }

                if let snapshot = loadSnapshot(from: sessionDir) {
                    snapshots.append(snapshot)
                }

                try? fileManager.removeItem(at: sessionDir)
            }

        } catch {
            logger.error(message: "DiagnosticsStorage: Failed to load historic data: \(error)")
        }

        return snapshots
    }

    /// Loads a single snapshot from a directory
    private func loadSnapshot(from directory: URL) -> DiagnosticsSnapshot? {
        let decoder = JSONDecoder()

        // Load tags
        var tags: [String: String] = [:]
        let tagsURL = tagsFileURL(in: directory)
        if let tagsData = try? Data(contentsOf: tagsURL),
           let loadedTags = try? decoder.decode([String: String].self, from: tagsData) {
            tags = loadedTags
        }

        // Load counters
        var counters: [String: Int] = [:]
        let countersURL = countersFileURL(in: directory)
        if let countersData = try? Data(contentsOf: countersURL),
           let loadedCounters = try? decoder.decode([String: Int].self, from: countersData) {
            counters = loadedCounters
        }

        // Load histograms
        var histograms: [String: HistogramStats] = [:]
        let histogramsURL = histogramsFileURL(in: directory)
        if let histogramsData = try? Data(contentsOf: histogramsURL),
           let loadedHistograms = try? decoder.decode([String: HistogramStats].self, from: histogramsData) {
            histograms = loadedHistograms
        }

        // Load events from log files
        var events: [DiagnosticsEvent] = []
        for url in eventLogFileURLs(in: directory) {
            guard let eventsData = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            let lines = eventsData.components(separatedBy: "\n")
            for line in lines {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let event = try? decoder.decode(DiagnosticsEvent.self, from: lineData) else {
                    continue
                }
                events.append(event)
            }
        }

        if !counters.isEmpty || !histograms.isEmpty || !events.isEmpty {
            return DiagnosticsSnapshot(tags: tags, counters: counters, histograms: histograms, events: events)
        }

        return nil
    }

    private func eventLogFileURLs(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        let currentEventsURL = eventsFileURL(in: directory)

        let contents = (try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []

        let rotatedLogs = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("events-") && name.hasSuffix(".log")
        }

        var ordered: [URL] = rotatedLogs
        if fileManager.fileExists(atPath: currentEventsURL.path) {
            ordered.append(currentEventsURL)
        }
        return ordered
    }

    // MARK: - Persistence

    func persistIfNeeded() {
        guard shouldStore, hasUnsavedData else { return }

        // Resolved once per pass: it revalidates the directory, so doing it per file would both
        // repeat the stat and let a mid-pass recreation miss the writes that already ran.
        let directory: URL
        do {
            directory = try createStorageDirectoryIfNeeded()
        } catch {
            logger.error(message: "DiagnosticsStorage: Failed to create storage directory: \(error)")
            return
        }

        if hasUnsavedTags {
            do {
                try persist(tags: tags, in: directory)
                hasUnsavedTags = false
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to write tags: \(error)")
            }
        }

        if hasUnsavedCounters {
            do {
                try persist(counters: counters, in: directory)
                hasUnsavedCounters = false
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to write counters: \(error)")
            }
        }

        if hasUnsavedHistograms {
            do {
                try persist(histograms: histograms, in: directory)
                hasUnsavedHistograms = false
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to write histograms: \(error)")
            }
        }

        if !unsavedEvents.isEmpty {
            do {
                let logUrl = eventsFileURL(in: directory)
                try prepareEventsLog(at: logUrl, in: directory)
                try append(events: unsavedEvents, to: logUrl)
                unsavedEvents.removeAll()
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to add events: \(error)")
            }
        }
    }

    func removeAllStoredFiles() throws {
        try removeFiles(includeTags: true)
    }

    private func removeFiles(includeTags: Bool) throws {
        guard let directory = storageDirectory else { return }
        let fileManager = FileManager.default

        // Remove specific files
        if includeTags {
            let tagsURL = tagsFileURL(in: directory)
            if fileManager.fileExists(atPath: tagsURL.path) {
                try fileManager.removeItem(at: tagsURL)
            }
        }

        let countersURL = countersFileURL(in: directory)
        if fileManager.fileExists(atPath: countersURL.path) {
            try fileManager.removeItem(at: countersURL)
        }

        let histogramsURL = histogramsFileURL(in: directory)
        if fileManager.fileExists(atPath: histogramsURL.path) {
            try fileManager.removeItem(at: histogramsURL)
        }

        let eventsURL = eventsFileURL(in: directory)
        if fileManager.fileExists(atPath: eventsURL.path) {
            try fileManager.removeItem(at: eventsURL)
        }

        // Remove rotated event log files
        let contents = (try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: nil,
                                                             options: [])) ?? []
        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix("events-") && name.hasSuffix(".log") {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func createStorageDirectoryIfNeeded() throws -> URL {
        let fileManager = FileManager.default

        if let storageDirectory {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: storageDirectory.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return storageDirectory
            }

            // The directory went away underneath us — another instance sharing this instance name
            // claimed it, the OS purged it (tvOS stores under Caches), or the host app cleared
            // Application Support. Without dropping the cached URL every later write fails with
            // Cocoa error 4 ("The folder ... doesn't exist") for the rest of the process lifetime.
            logger.debug(message: "DiagnosticsStorage: Storage directory is gone, recreating it")
            self.storageDirectory = nil
            // The directory's contents went with it, but everything it held is still in memory
            // (persists write full maps, and `events` retains the whole session). Re-arm it all
            // so the recreated directory is reconstructed in full, not just the deltas that
            // happened to be unsaved.
            hasUnsavedTags = hasUnsavedTags || !tags.isEmpty
            hasUnsavedCounters = hasUnsavedCounters || !counters.isEmpty
            hasUnsavedHistograms = hasUnsavedHistograms || !histograms.isEmpty
            unsavedEvents = events
        }

        let baseDirectory = try Storage.rootDirectoryURL(fileManager: fileManager, createIfNeeded: true)
        let directory = baseDirectory
            .appendingPathComponent(Self.storagePrefix, isDirectory: true)
            .appendingPathComponent(sanitizedInstance, isDirectory: true)
            .appendingPathComponent(String(sessionStartAt), isDirectory: true)

        try fileManager.createDirectory(at: directory,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
        storageDirectory = directory
        return directory
    }

    private func tagsFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("tags.json", isDirectory: false)
    }

    private func countersFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("counters.json", isDirectory: false)
    }

    private func histogramsFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("histograms.json", isDirectory: false)
    }

    private func eventsFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("events.log", isDirectory: false)
    }

    private func persist(tags: [String: String], in directory: URL) throws {
        let url = tagsFileURL(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(tags)
        try data.write(to: url, options: [.atomic])
    }

    private func persist(counters: [String: Int], in directory: URL) throws {
        let url = countersFileURL(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(counters)
        try data.write(to: url, options: [.atomic])
    }

    private func persist(histograms: [String: HistogramStats], in directory: URL) throws {
        let url = histogramsFileURL(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(histograms)
        try data.write(to: url, options: [.atomic])
    }

    private func prepareEventsLog(at url: URL, in directory: URL) throws {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
            return
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue >= Self.maxEventsLogBytes {
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let rotatedName = "events-\(timestamp).log"
            let rotatedURL = directory.appendingPathComponent(rotatedName, isDirectory: false)
            try fileManager.moveItem(at: url, to: rotatedURL)
            fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        }
    }

    private func append(events: [DiagnosticsEvent], to url: URL) throws {
        let encoder = JSONEncoder()

        var encodedEvents: [Data] = []
        encodedEvents.reserveCapacity(events.count)

        for event in events {
            var data = try encoder.encode(event)
            data.append(Self.newlineData)
            encodedEvents.append(data)
        }

        let fileHandle = try FileHandle(forWritingTo: url)
        defer {
            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                try? fileHandle.close()
            } else {
                fileHandle.closeFile()
            }
        }

        if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
            try fileHandle.seekToEnd()
        } else {
            fileHandle.seekToEndOfFile()
        }

        // Write all pre-encoded data
        for data in encodedEvents {
            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                try fileHandle.write(contentsOf: data)
            } else {
                fileHandle.write(data)
            }
        }

        if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
            try fileHandle.synchronize()
        } else {
            fileHandle.synchronizeFile()
        }
    }

    // MARK: - Persistence Timer

    private func startPersistenceTimerIfNeeded() {
        guard shouldStore, hasUnsavedData, persistenceTask == nil else { return }

        let interval = persistIntervalNanoSec
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled else { return }

            await self?.markPersistenceTimerFinished()
            await self?.persistIfNeeded()
        }
    }

    func stopPersistenceTimer() {
        persistenceTask?.cancel()
        persistenceTask = nil
    }

    private func markPersistenceTimerFinished() {
        persistenceTask = nil
    }

    func waitForPendingPersistenceTask() async throws {
        await persistenceTask?.value
    }

    deinit {
        // Cancel any pending persistence task
        persistenceTask?.cancel()
        // This session is over: a later instance may now claim whatever it left on disk.
        Self.unregisterLiveSession(liveSessionKey)
    }
}
