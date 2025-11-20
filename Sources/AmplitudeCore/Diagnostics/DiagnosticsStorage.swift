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
    private let persistIntervalNanoSeconds: UInt64

    // In-memory state
    var tags: [String: String] = [:]
    var counters: [String: Int] = [:]
    var histograms: [String: HistogramStats] = [:]
    var events: [DiagnosticsEvent] = []

    var isLoaded: Bool = false

    var tagsChanged = false
    var countersChanged = false
    var histogramsChanged = false
    var addedEvents: [DiagnosticsEvent] = []

    private var persistenceTask: Task<Void, Never>?

    private static let storagePrefix: String = "com.amplitude.diagnostics"
    private static let maxEventsLogBytes: Int = 256 * 1024
    private static let newlineData = Data([0x0A])
    static private let maxEventCount: Int = 10

    private let sanitizedInstance: String

    init(instanceName: String, sessionStartAt: TimeInterval, logger: CoreLogger, persistIntervalNanoSeconds: UInt64 = NSEC_PER_SEC) {
        self.instanceName = instanceName
        self.logger = logger
        self.sessionStartAt = sessionStartAt
        self.sanitizedInstance = Self.sanitize(instanceName)
        self.persistIntervalNanoSeconds = persistIntervalNanoSeconds
    }

    // MARK: - Public API for data manipulation

    func setTag(name: String, value: String) {
        tags[name] = value
        tagsChanged = true
        startPersistenceTimerIfNeeded()
    }

    func setTags(_ newTags: [String: String]) {
        tags.merge(newTags, uniquingKeysWith: { _, new in new })
        tagsChanged = true
        startPersistenceTimerIfNeeded()
    }

    func increment(name: String, size: Int = 1) {
        counters[name] = (counters[name] ?? 0) + size
        countersChanged = true
        startPersistenceTimerIfNeeded()
    }

    func recordHistogram(name: String, value: Double) {
        var stats = histograms[name] ?? HistogramStats()
        stats.count += 1
        stats.sum += value
        stats.min = min(stats.min, value)
        stats.max = max(stats.max, value)
        histograms[name] = stats
        histogramsChanged = true
        startPersistenceTimerIfNeeded()
    }

    func recordEvent(name: String, properties: [String: any Sendable]? = nil) {
        guard addedEvents.count < Self.maxEventCount else {
            logger.debug(message: "DiagnosticsStorage: Event limit reached")
            return
        }
        let event = DiagnosticsEvent(eventName: name,
                                     time: Date().timeIntervalSince1970,
                                     eventProperties: properties)
        events.append(event)
        addedEvents.append(event)
        startPersistenceTimerIfNeeded()
    }

    /// Dumps all diagnostic data and clears counters, histograms, and events (keeping tags)
    /// - Returns: Tuple containing all current diagnostic data
    func dumpAndClear() -> DiagnosticsSnapshot {
        // Create snapshot of current data
        let snapshot = DiagnosticsSnapshot(tags: tags, counters: counters, histograms: histograms, events: events)

        // Clear in-memory data (keep tags)
        counters.removeAll()
        histograms.removeAll()
        events.removeAll()
        addedEvents.removeAll()

        // Reset change flags
        countersChanged = false
        histogramsChanged = false

        // Remove files (keep tags file)
        do {
            let directory = try storageDirectory()
            let fileManager = FileManager.default

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

            // Also remove rotated event log files
            let contents = (try? fileManager.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: [])) ?? []
            for url in contents {
                let name = url.lastPathComponent
                if name.hasPrefix("events-") && name.hasSuffix(".log") {
                    try? fileManager.removeItem(at: url)
                }
            }
        } catch {
            logger.error(message: "DiagnosticsStorage: Failed to remove files during dump: \(error)")
        }

        return snapshot
    }

    /// Loads all historic diagnostic data from filesystem and clears those folders
    /// - Returns: Array of diagnostic snapshots from previous sessions
    func loadAndClearHistoricData() -> [DiagnosticsSnapshot] {
        var snapshots: [DiagnosticsSnapshot] = []

        do {
            let fileManager = FileManager.default
            let baseDirectory = try fileManager.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true)

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

                // Skip if it's the current timestamp
                if sessionStartAt == currentSessionStartAt {
                    continue
                }

                if let snapshot = loadSnapshot(from: sessionDir) {
                    snapshots.append(snapshot)
                }

                // Remove the directory after loading
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

        // Load events from log file
        var events: [DiagnosticsEvent] = []
        let eventsURL = eventsFileURL(in: directory)
        if let eventsData = try? String(contentsOf: eventsURL, encoding: .utf8) {
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

        // Only return snapshot if we loaded at least something
        if !tags.isEmpty || !counters.isEmpty || !histograms.isEmpty || !events.isEmpty {
            return DiagnosticsSnapshot(tags: tags, counters: counters, histograms: histograms, events: events)
        }

        return nil
    }

    // MARK: - Persistence

    func persistIfNeeded() {
        if tagsChanged {
            do {
                let directory = try storageDirectory()
                try persist(tags: tags, in: directory)
                tagsChanged = false
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to write tags: \(error)")
            }
        }

        if countersChanged {
            do {
                let directory = try storageDirectory()
                try persist(counters: counters, in: directory)
                countersChanged = false
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to write counters: \(error)")
            }
        }

        if histogramsChanged {
            do {
                let directory = try storageDirectory()
                try persist(histograms: histograms, in: directory)
                histogramsChanged = false
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to write histograms: \(error)")
            }
        }

        if !addedEvents.isEmpty {
            do {
                let directory = try storageDirectory()
                let logUrl = eventsFileURL(in: directory)
                try prepareEventsLog(at: logUrl, in: directory)
                try append(events: addedEvents, to: logUrl)
                addedEvents.removeAll()
            } catch {
                logger.error(message: "DiagnosticsStorage: Failed to add events: \(error)")
            }
        }
    }

    func removeAll() throws {
        let directory = try storageDirectory()
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: nil,
                                                             options: [])) ?? []
        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix("tags") ||
               name.hasPrefix("counters") ||
               name.hasPrefix("histograms") ||
               name.hasPrefix("events") {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func storageDirectory() throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = try fileManager.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true)
        let storageDirectory = baseDirectory
            .appendingPathComponent(Self.storagePrefix, isDirectory: true)
            .appendingPathComponent(sanitizedInstance, isDirectory: true)
            .appendingPathComponent(String(sessionStartAt), isDirectory: true)

        try fileManager.createDirectory(at: storageDirectory,
                                        withIntermediateDirectories: true,
                                        attributes: nil)
        return storageDirectory
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
            let timestamp = Int(Date().timeIntervalSince1970)
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

    private static func sanitize(_ value: String) -> String {
        let hash = Hash.fnv1a64(value)
        return String(format: "%016llx", hash)
    }

    // MARK: - Persistence Timer

    private func startPersistenceTimerIfNeeded() {
        guard persistenceTask == nil else { return }
        
        let interval = persistIntervalNanoSeconds
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            
            await self?.persistIfNeeded()
            await self?.markPersistenceTimerFinished()
        }
    }

    public func stopPersistenceTimer() {
        persistenceTask?.cancel()
        persistenceTask = nil
    }

    private func markPersistenceTimerFinished() {
        persistenceTask = nil
    }
    
    deinit {
        // Cancel any pending persistence task
        persistenceTask?.cancel()
    }
}
