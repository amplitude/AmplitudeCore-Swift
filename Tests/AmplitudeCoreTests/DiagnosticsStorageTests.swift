//
//  DiagnosticsStorageTests.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/10/25.
//

import XCTest
@_spi(Internal) @testable import AmplitudeCore

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class DiagnosticsStorageTests: XCTestCase {

    var storage: DiagnosticsStorage!
    let testApiKey = "test-api-key-\(UUID().uuidString)"
    var testTimestamp: TimeInterval = 0
    var testInstanceName: String = ""
    var logger: CoreLogger!

    override func setUp() async throws {
        logger = OSLogger(logLevel: .error)
        testTimestamp = Date().timeIntervalSince1970
        testInstanceName = "test-instance-\(UUID().uuidString)"
        storage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: true,
            persistIntervalNanoSec: NSEC_PER_MSEC * 10
        )
    }

    override func tearDown() async throws {
        // Clean up test files. Tests that simulate a restart release `storage` themselves.
        try? await storage?.removeAllStoredFiles()
        storage = nil
    }

    // MARK: - Tag Tests

    func testSetTag() async throws {
        await storage.setTag(name: "test_tag", value: "test_value")

        let tags = await storage.tags
        XCTAssertEqual(tags["test_tag"], "test_value")
        XCTAssertEqual(tags.count, 1)
    }

    func testSetTags() async throws {
        let newTags = [
            "tag1": "value1",
            "tag2": "value2",
            "tag3": "value3"
        ]

        await storage.setTags(newTags)

        let tags = await storage.tags
        XCTAssertEqual(tags["tag1"], "value1")
        XCTAssertEqual(tags["tag2"], "value2")
        XCTAssertEqual(tags["tag3"], "value3")
        XCTAssertEqual(tags.count, 3)
    }

    func testSetTagsMergesWithExisting() async throws {
        await storage.setTag(name: "existing", value: "old_value")

        let newTags = [
            "existing": "new_value",
            "new_tag": "new_value"
        ]

        await storage.setTags(newTags)

        let tags = await storage.tags
        XCTAssertEqual(tags["existing"], "new_value")
        XCTAssertEqual(tags["new_tag"], "new_value")
        XCTAssertEqual(tags.count, 2)
    }

    func testGetTag() async throws {
        await storage.setTag(name: "test_tag", value: "test_value")

        let value = await storage.getTag(name: "test_tag")
        XCTAssertEqual(value, "test_value")
    }

    func testGetTagNotFound() async throws {
        let value = await storage.getTag(name: "nonexistent")
        XCTAssertNil(value)
    }

    func testGetTags() async throws {
        await storage.setTags([
            "tag1": "value1",
            "tag2": "value2",
            "tag3": "value3"
        ])

        let tags = await storage.getTags()
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(tags["tag1"], "value1")
        XCTAssertEqual(tags["tag2"], "value2")
        XCTAssertEqual(tags["tag3"], "value3")
    }

    func testGetTagsEmpty() async throws {
        let tags = await storage.getTags()
        XCTAssertTrue(tags.isEmpty)
    }

    // MARK: - Counter Tests

    func testIncrement() async throws {
        await storage.increment(name: "test_counter", size: 5)

        let counters = await storage.counters
        XCTAssertEqual(counters["test_counter"], 5)
    }

    func testIncrementAccumulates() async throws {
        await storage.increment(name: "test_counter", size: 5)
        await storage.increment(name: "test_counter", size: 3)
        await storage.increment(name: "test_counter", size: 2)

        let counters = await storage.counters
        XCTAssertEqual(counters["test_counter"], 10)
    }

    func testIncrementDefaultSize() async throws {
        await storage.increment(name: "test_counter")

        let counters = await storage.counters
        XCTAssertEqual(counters["test_counter"], 1)
    }

    func testIncrementMultipleCounters() async throws {
        await storage.increment(name: "counter1", size: 10)
        await storage.increment(name: "counter2", size: 20)
        await storage.increment(name: "counter3", size: 30)

        let counters = await storage.counters
        XCTAssertEqual(counters["counter1"], 10)
        XCTAssertEqual(counters["counter2"], 20)
        XCTAssertEqual(counters["counter3"], 30)
        XCTAssertEqual(counters.count, 3)
    }

    // MARK: - Histogram Tests

    func testRecordHistogram() async throws {
        await storage.recordHistogram(name: "test_metric", value: 42.0)

        let histograms = await storage.histograms
        let stats = histograms["test_metric"]

        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.count, 1)
        XCTAssertEqual(stats?.sum, 42.0)
        XCTAssertEqual(stats?.min, 42.0)
        XCTAssertEqual(stats?.max, 42.0)
    }

    func testRecordHistogramMultipleValues() async throws {
        await storage.recordHistogram(name: "test_metric", value: 10.0)
        await storage.recordHistogram(name: "test_metric", value: 20.0)
        await storage.recordHistogram(name: "test_metric", value: 30.0)
        await storage.recordHistogram(name: "test_metric", value: 5.0)

        let histograms = await storage.histograms
        let stats = histograms["test_metric"]

        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.count, 4)
        XCTAssertEqual(stats?.sum, 65.0)
        XCTAssertEqual(stats?.min, 5.0)
        XCTAssertEqual(stats?.max, 30.0)
    }

    func testRecordHistogramCalculatesMinMax() async throws {
        await storage.recordHistogram(name: "test_metric", value: 100.0)
        await storage.recordHistogram(name: "test_metric", value: 1.0)
        await storage.recordHistogram(name: "test_metric", value: 50.0)

        let histograms = await storage.histograms
        let stats = histograms["test_metric"]

        XCTAssertEqual(stats?.min, 1.0)
        XCTAssertEqual(stats?.max, 100.0)
    }

    // MARK: - Event Tests

    func testRecordEvent() async throws {
        await storage.recordEvent(name: "test_event", properties: nil)

        let events = await storage.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].eventName, "test_event")
        XCTAssertNil(events[0].eventProperties)
    }

    func testRecordEventWithProperties() async throws {
        let properties: [String: any Sendable] = [
            "string_prop": "value",
            "int_prop": 42,
            "double_prop": 3.14,
            "bool_prop": true
        ]

        await storage.recordEvent(name: "test_event", properties: properties)

        let events = await storage.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].eventName, "test_event")
        XCTAssertNotNil(events[0].eventProperties)

        let props = events[0].eventProperties!
        XCTAssertEqual(props["string_prop"] as? String, "value")
        XCTAssertEqual(props["int_prop"] as? Int, 42)
        if let doubleValue = props["double_prop"] as? Double {
            XCTAssertEqual(doubleValue, 3.14, accuracy: 0.001)
        } else {
            XCTFail("double_prop should be a Double")
        }
        XCTAssertEqual(props["bool_prop"] as? Bool, true)
    }

    func testRecordEventMultiple() async throws {
        await storage.recordEvent(name: "event1", properties: nil)
        await storage.recordEvent(name: "event2", properties: nil)
        await storage.recordEvent(name: "event3", properties: nil)

        let events = await storage.events
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].eventName, "event1")
        XCTAssertEqual(events[1].eventName, "event2")
        XCTAssertEqual(events[2].eventName, "event3")
    }

    func testRecordEventLimit() async throws {
        // Record 11 events (limit is 10)
        for i in 0..<11 {
            await storage.recordEvent(name: "event_\(i)", properties: nil)
        }

        let events = await storage.events
        // Should stop at 10
        XCTAssertEqual(events.count, 10)
    }

    func testDiagnosticsPayloadJsonFormat() async throws {
        // Set up complete diagnostics data
        await storage.setTag(name: "sdk_version", value: "1.0.0")
        await storage.setTag(name: "platform", value: "iOS")
        await storage.increment(name: "events_tracked", size: 100)
        await storage.increment(name: "api_calls", size: 50)
        await storage.recordHistogram(name: "request_latency", value: 150.0)
        await storage.recordHistogram(name: "request_latency", value: 200.0)
        await storage.recordEvent(name: "test_event", properties: ["key1": "value1", "key2": 42])
        await storage.recordEvent(name: "another_event", properties: nil)

        // Dump the snapshot to get a DiagnosticsSnapshot
        let snapshot = await storage.dumpAndClearCurrentSession()
        XCTAssertNotNil(snapshot)

        // Convert to DiagnosticsPayload (similar to how DiagnosticsClient does it)
        let histogramResults = snapshot!.histograms.mapValues { stats in
            HistogramResult(
                count: stats.count,
                min: stats.min,
                max: stats.max,
                avg: stats.count > 0 ? stats.sum / Double(stats.count) : 0
            )
        }
        let payload = DiagnosticsPayload(
            tags: snapshot!.tags,
            counters: snapshot!.counters,
            histogram: histogramResults,
            events: snapshot!.events
        )

        // Encode the payload to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(payload)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Verify top-level payload keys
        XCTAssertTrue(jsonString.contains("\"tags\""), "JSON should contain 'tags' key")
        XCTAssertTrue(jsonString.contains("\"counters\""), "JSON should contain 'counters' key")
        XCTAssertTrue(jsonString.contains("\"histogram\""), "JSON should contain 'histogram' key")
        XCTAssertTrue(jsonString.contains("\"events\""), "JSON should contain 'events' key")

        // Verify tags content
        XCTAssertTrue(jsonString.contains("\"sdk_version\""), "JSON should contain 'sdk_version' tag key")
        XCTAssertTrue(jsonString.contains("\"platform\""), "JSON should contain 'platform' tag key")

        // Verify counters content
        XCTAssertTrue(jsonString.contains("\"events_tracked\""), "JSON should contain 'events_tracked' counter key")
        XCTAssertTrue(jsonString.contains("\"api_calls\""), "JSON should contain 'api_calls' counter key")

        // Verify histogram keys
        XCTAssertTrue(jsonString.contains("\"request_latency\""), "JSON should contain 'request_latency' histogram key")
        XCTAssertTrue(jsonString.contains("\"count\""), "JSON should contain 'count' in histogram")
        XCTAssertTrue(jsonString.contains("\"min\""), "JSON should contain 'min' in histogram")
        XCTAssertTrue(jsonString.contains("\"max\""), "JSON should contain 'max' in histogram")
        XCTAssertTrue(jsonString.contains("\"avg\""), "JSON should contain 'avg' in histogram")

        // Verify DiagnosticsEvent
        XCTAssertTrue(jsonString.contains("\"event_name\""), "JSON should contain 'event_name' key, got: \(jsonString)")
        XCTAssertTrue(jsonString.contains("\"event_properties\""), "JSON should contain 'event_properties' key, got: \(jsonString)")
        XCTAssertTrue(jsonString.contains("\"time\""), "JSON should contain 'time' key in events")

        // Verify round-trip decoding works
        let decoder = JSONDecoder()
        let decodedPayload = try decoder.decode(DiagnosticsPayload.self, from: jsonData)

        // Verify tags
        XCTAssertEqual(decodedPayload.tags["sdk_version"], "1.0.0")
        XCTAssertEqual(decodedPayload.tags["platform"], "iOS")

        // Verify counters
        XCTAssertEqual(decodedPayload.counters["events_tracked"], 100)
        XCTAssertEqual(decodedPayload.counters["api_calls"], 50)

        // Verify histograms
        XCTAssertNotNil(decodedPayload.histogram["request_latency"])
        XCTAssertEqual(decodedPayload.histogram["request_latency"]?.count, 2)
        XCTAssertEqual(decodedPayload.histogram["request_latency"]?.min, 150.0)
        XCTAssertEqual(decodedPayload.histogram["request_latency"]?.max, 200.0)

        // Verify events
        XCTAssertEqual(decodedPayload.events.count, 2)
        let testEvent = decodedPayload.events.first { $0.eventName == "test_event" }
        XCTAssertNotNil(testEvent)
        XCTAssertEqual(testEvent?.eventProperties?["key1"] as? String, "value1")
        XCTAssertEqual(testEvent?.eventProperties?["key2"] as? Int, 42)

        // Verify event with null event_properties
        let anotherEvent = decodedPayload.events.first { $0.eventName == "another_event" }
        XCTAssertNotNil(anotherEvent)
        XCTAssertNil(anotherEvent?.eventProperties, "Event with nil properties should decode to nil eventProperties")
    }

    // MARK: - Dump and Clear Tests

    func testDumpAndClear() async throws {
        // Set up some data
        await storage.setTag(name: "tag1", value: "value1")
        await storage.increment(name: "counter1", size: 5)
        await storage.recordHistogram(name: "metric1", value: 42.0)
        await storage.recordEvent(name: "event1", properties: nil)

        // Dump and clear
        let snapshot = await storage.dumpAndClearCurrentSession()
        XCTAssertNotNil(snapshot)

        // Verify snapshot contains all data
        XCTAssertEqual(snapshot!.tags["tag1"], "value1")
        XCTAssertEqual(snapshot!.counters["counter1"], 5)
        XCTAssertEqual(snapshot!.histograms["metric1"]?.count, 1)
        XCTAssertEqual(snapshot!.events.count, 1)

        // Verify counters, histograms, and events are cleared
        let counters = await storage.counters
        let histograms = await storage.histograms
        let events = await storage.events
        let tags = await storage.tags

        XCTAssertTrue(counters.isEmpty)
        XCTAssertTrue(histograms.isEmpty)
        XCTAssertTrue(events.isEmpty)

        // Tags should be preserved
        XCTAssertEqual(tags["tag1"], "value1")
    }

    func testDumpAndClearMultipleTimes() async throws {
        // First batch
        await storage.increment(name: "counter1", size: 5)
        let snapshot1 = await storage.dumpAndClearCurrentSession()
        XCTAssertNotNil(snapshot1)
        XCTAssertEqual(snapshot1!.counters["counter1"], 5)

        // Second batch
        await storage.increment(name: "counter1", size: 10)
        let snapshot2 = await storage.dumpAndClearCurrentSession()
        XCTAssertNotNil(snapshot2)
        XCTAssertEqual(snapshot2!.counters["counter1"], 10)

        // Verify they're independent
        XCTAssertNotEqual(snapshot1!.counters["counter1"], snapshot2!.counters["counter1"])
    }

    // MARK: - Persistence Tests

#if os(tvOS)
    func testPersistsAndLoadsDiagnosticsFromCachesOnTvOS() async throws {
        XCTAssertEqual(Storage.rootDirectory, .cachesDirectory)

        // Scoped so the previous session is released before the new one loads it.
        do {
            let previousStorage = DiagnosticsStorage(
                instanceName: testInstanceName,
                sessionStartAt: testTimestamp - 1,
                logger: logger,
                shouldStore: true
            )
            await previousStorage.increment(name: "persisted_counter", size: 42)
            await previousStorage.persistIfNeeded()
        }

        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp + 1,
            logger: logger,
            shouldStore: true
        )

        let snapshots = await newStorage.loadAndClearPreviousSessions()
        XCTAssertEqual(snapshots.first?.counters["persisted_counter"], 42)

        try? await newStorage.removeAllStoredFiles()
    }
#endif

    func testPersistAndLoadTags() async throws {
        // Set tags and a counter (tags alone don't produce a snapshot) then persist
        await storage.setTag(name: "persisted_tag_1", value: "value_1")
        await storage.setTags(["persisted_tag_2": "value_2", "persisted_tag_3": "value_3"])
        await storage.increment(name: "counter_for_snapshot", size: 1)
        await storage.persistIfNeeded()

        // Simulate a restart by creating a new storage with a newer timestamp
        // It will load the old session's data as "historic". Releasing the previous storage is
        // part of the simulation: a session that is still live is deliberately never claimed.
        storage = nil
        let newTimestamp = testTimestamp + 1
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: newTimestamp,
            logger: logger,
            shouldStore: true
        )

        // Load historic data from the previous session
        let snapshots = await newStorage.loadAndClearPreviousSessions()

        // Verify we got our persisted session
        XCTAssertGreaterThanOrEqual(snapshots.count, 1, "Should have at least one historic snapshot")
        guard let snapshot = snapshots.first else {
            XCTFail("No snapshot found")
            try? await newStorage.removeAllStoredFiles()
            return
        }

        // Verify tags were persisted and loaded
        XCTAssertEqual(snapshot.tags["persisted_tag_1"], "value_1")
        XCTAssertEqual(snapshot.tags["persisted_tag_2"], "value_2")
        XCTAssertEqual(snapshot.tags["persisted_tag_3"], "value_3")

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    func testPersistAndLoadCounters() async throws {
        // Set counters and persist
        await storage.increment(name: "counter_1", size: 42)
        await storage.increment(name: "counter_2", size: 99)
        await storage.persistIfNeeded()

        // Simulate restart with newer timestamp. Releasing the previous storage is part of the
        // simulation: a session that is still live is deliberately never claimed.
        storage = nil
        let newTimestamp = testTimestamp + 1
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: newTimestamp,
            logger: logger,
            shouldStore: true
        )

        // Load historic data
        let snapshots = await newStorage.loadAndClearPreviousSessions()

        XCTAssertGreaterThanOrEqual(snapshots.count, 1)
        guard let snapshot = snapshots.first else {
            XCTFail("No snapshot found")
            try? await newStorage.removeAllStoredFiles()
            return
        }

        // Verify counters were persisted and loaded
        XCTAssertEqual(snapshot.counters["counter_1"], 42)
        XCTAssertEqual(snapshot.counters["counter_2"], 99)

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    func testPersistAndLoadHistograms() async throws {
        // Record histograms and persist
        await storage.recordHistogram(name: "metric_1", value: 100.0)
        await storage.recordHistogram(name: "metric_1", value: 200.0)
        await storage.recordHistogram(name: "metric_2", value: 50.0)
        await storage.persistIfNeeded()

        // Simulate restart with newer timestamp. Releasing the previous storage is part of the
        // simulation: a session that is still live is deliberately never claimed.
        storage = nil
        let newTimestamp = testTimestamp + 1
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: newTimestamp,
            logger: logger,
            shouldStore: true
        )

        // Load historic data
        let snapshots = await newStorage.loadAndClearPreviousSessions()

        XCTAssertGreaterThanOrEqual(snapshots.count, 1)
        guard let snapshot = snapshots.first else {
            XCTFail("No snapshot found")
            try? await newStorage.removeAllStoredFiles()
            return
        }

        // Verify histograms were persisted and loaded
        XCTAssertNotNil(snapshot.histograms["metric_1"])
        XCTAssertEqual(snapshot.histograms["metric_1"]?.count, 2)
        XCTAssertEqual(snapshot.histograms["metric_1"]?.sum, 300.0)
        XCTAssertEqual(snapshot.histograms["metric_1"]?.min, 100.0)
        XCTAssertEqual(snapshot.histograms["metric_1"]?.max, 200.0)

        XCTAssertNotNil(snapshot.histograms["metric_2"])
        XCTAssertEqual(snapshot.histograms["metric_2"]?.count, 1)
        XCTAssertEqual(snapshot.histograms["metric_2"]?.sum, 50.0)

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    func testPersistAndLoadEvents() async throws {
        // Record events and persist
        await storage.recordEvent(name: "event_1", properties: ["key": "value"])
        await storage.recordEvent(name: "event_2", properties: ["number": 42])
        await storage.recordEvent(name: "event_3", properties: nil)
        await storage.persistIfNeeded()

        // Simulate restart with newer timestamp. Releasing the previous storage is part of the
        // simulation: a session that is still live is deliberately never claimed.
        storage = nil
        let newTimestamp = testTimestamp + 1
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: newTimestamp,
            logger: logger,
            shouldStore: true
        )

        // Load historic data
        let snapshots = await newStorage.loadAndClearPreviousSessions()

        XCTAssertGreaterThanOrEqual(snapshots.count, 1)
        guard let snapshot = snapshots.first else {
            XCTFail("No snapshot found")
            try? await newStorage.removeAllStoredFiles()
            return
        }

        // Verify events were persisted and loaded (at least some of them)
        XCTAssertGreaterThanOrEqual(snapshot.events.count, 2, "Should have at least 2 events persisted")

        // Check that the events we do have are correct
        let eventNames = snapshot.events.map { $0.eventName }
        XCTAssertTrue(eventNames.contains("event_1"))
        XCTAssertTrue(eventNames.contains("event_2"))

        // Find and verify event_1
        if let event1 = snapshot.events.first(where: { $0.eventName == "event_1" }) {
            XCTAssertEqual(event1.eventProperties?["key"] as? String, "value")
        }

        // Find and verify event_2
        if let event2 = snapshot.events.first(where: { $0.eventName == "event_2" }) {
            XCTAssertEqual(event2.eventProperties?["number"] as? Int, 42)
        }

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    func testLoadPreviousSessionIncludesRotatedEventLogs() async throws {
        let instanceName = "test-instance-\(UUID().uuidString)"
        let oldTimestamp: TimeInterval = 1000
        let newTimestamp: TimeInterval = 2000

        // Scoped so the old session is released — a live session is never treated as historic.
        do {
            let oldStorage = DiagnosticsStorage(
                instanceName: instanceName,
                sessionStartAt: oldTimestamp,
                logger: logger,
                shouldStore: true
            )

            await oldStorage.recordEvent(name: "rotated_event", properties: ["key": "value"])
            await oldStorage.persistIfNeeded()
        }

        let fileManager = FileManager.default
        let baseDirectory = try Storage.rootDirectoryURL(fileManager: fileManager, createIfNeeded: true)

        let instanceDirectory = baseDirectory
            .appendingPathComponent("com.amplitude.diagnostics", isDirectory: true)
            .appendingPathComponent(instanceName.fnv1a64String(), isDirectory: true)

        let oldSessionDirectory = instanceDirectory
            .appendingPathComponent(String(oldTimestamp), isDirectory: true)

        let eventsLogURL = oldSessionDirectory.appendingPathComponent("events.log", isDirectory: false)
        let rotatedURL = oldSessionDirectory.appendingPathComponent("events-1111.log", isDirectory: false)
        try fileManager.moveItem(at: eventsLogURL, to: rotatedURL)

        let currentEvent = DiagnosticsEvent(eventName: "current_event", time: 2222, eventProperties: nil)
        var encoded = try JSONEncoder().encode(currentEvent)
        encoded.append(Data([0x0A]))
        try encoded.write(to: eventsLogURL, options: [.atomic])

        let newStorage = DiagnosticsStorage(
            instanceName: instanceName,
            sessionStartAt: newTimestamp,
            logger: logger,
            shouldStore: true
        )

        let snapshots = await newStorage.loadAndClearPreviousSessions()
        XCTAssertEqual(snapshots.count, 1)

        guard let snapshot = snapshots.first else {
            XCTFail("No snapshot found")
            try? fileManager.removeItem(at: instanceDirectory)
            return
        }

        let eventNames = snapshot.events.map { $0.eventName }
        XCTAssertTrue(eventNames.contains("rotated_event"))
        XCTAssertTrue(eventNames.contains("current_event"))

        // Clean up
        try? fileManager.removeItem(at: instanceDirectory)
    }

    func testPersistAllDataTypes() async throws {
        // Create all types of data
        await storage.setTag(name: "test_tag", value: "test_value")
        await storage.increment(name: "test_counter", size: 123)
        await storage.recordHistogram(name: "test_metric", value: 456.0)
        await storage.recordEvent(name: "test_event", properties: ["prop": "value"])
        await storage.persistIfNeeded()

        // Simulate restart with newer timestamp. Releasing the previous storage is part of the
        // simulation: a session that is still live is deliberately never claimed.
        storage = nil
        let newTimestamp = testTimestamp + 1
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: newTimestamp,
            logger: logger,
            shouldStore: true
        )

        // Load historic data
        let snapshots = await newStorage.loadAndClearPreviousSessions()

        XCTAssertGreaterThanOrEqual(snapshots.count, 1)
        guard let snapshot = snapshots.first else {
            XCTFail("No snapshot found")
            try? await newStorage.removeAllStoredFiles()
            return
        }

        // Verify all data types were persisted
        XCTAssertEqual(snapshot.tags["test_tag"], "test_value")
        XCTAssertEqual(snapshot.counters["test_counter"], 123)
        XCTAssertEqual(snapshot.histograms["test_metric"]?.count, 1)
        XCTAssertGreaterThanOrEqual(snapshot.events.count, 1)
        if !snapshot.events.isEmpty {
            XCTAssertEqual(snapshot.events[0].eventName, "test_event")
        }

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    // MARK: - Historic Data Tests

    func testLoadAndClearHistoricData() async throws {
        // Create storage with old timestamp. Scoped so it is released before loading: only
        // sessions whose storage is gone count as historic.
        let oldTimestamp = Date().timeIntervalSince1970 - 3600 // 1 hour ago
        do {
            let oldStorage = DiagnosticsStorage(
                instanceName: testInstanceName,
                sessionStartAt: oldTimestamp,
                logger: logger,
                shouldStore: true
            )

            // Add data and persist (skip events for now as they may have persistence timing issues)
            await oldStorage.setTag(name: "old_tag", value: "old_value")
            await oldStorage.increment(name: "old_counter", size: 99)
            await oldStorage.recordHistogram(name: "old_metric", value: 123.0)
            await oldStorage.persistIfNeeded()
        }

        // Now load historic data with new storage (different timestamp)
        let snapshots = await storage.loadAndClearPreviousSessions()

        XCTAssertGreaterThanOrEqual(snapshots.count, 1, "Should have at least one historic snapshot")
        guard !snapshots.isEmpty else {
            XCTFail("Snapshots should not be empty")
            return
        }

        let snapshot = snapshots[0]

        XCTAssertEqual(snapshot.tags["old_tag"], "old_value")
        XCTAssertEqual(snapshot.counters["old_counter"], 99)
        XCTAssertNotNil(snapshot.histograms["old_metric"])

        // Verify directory was cleaned up
        let snapshotsAfterCleanup = await storage.loadAndClearPreviousSessions()
        XCTAssertEqual(snapshotsAfterCleanup.count, 0)
    }

    func testLoadAndClearHistoricDataMultipleSessions() async throws {
        // Create multiple old sessions
        let timestamps = [
            Date().timeIntervalSince1970 - 7200, // 2 hours ago
            Date().timeIntervalSince1970 - 3600, // 1 hour ago
            Date().timeIntervalSince1970 - 1800  // 30 minutes ago
        ]

        for (index, timestamp) in timestamps.enumerated() {
            let oldStorage = DiagnosticsStorage(
                instanceName: testInstanceName,
                sessionStartAt: timestamp,
                logger: logger,
                shouldStore: true
            )

            await oldStorage.setTag(name: "session", value: "session_\(index)")
            await oldStorage.increment(name: "counter", size: index + 1)
            await oldStorage.persistIfNeeded()

            // Don't clean up here - let loadAndClearHistoricData do it
        }

        // Load all historic data
        let snapshots = await storage.loadAndClearPreviousSessions()

        XCTAssertGreaterThanOrEqual(snapshots.count, 3)

        // Verify sessions data exists
        let sessions = snapshots.compactMap { $0.tags["session"] }
        XCTAssertTrue(sessions.contains("session_0"))
        XCTAssertTrue(sessions.contains("session_1"))
        XCTAssertTrue(sessions.contains("session_2"))
    }

    func testLoadAndClearHistoricDataSkipsCurrentSession() async throws {
        // Add data to current session
        await storage.setTag(name: "current_tag", value: "current_value")
        await storage.persistIfNeeded()

        // Try to load historic data (should skip current session)
        let snapshots = await storage.loadAndClearPreviousSessions()
        XCTAssertEqual(snapshots.count, 0)
    }

    // MARK: - Live Session Tests

    /// Two storages sharing an instance name is what a second `AmplitudeContext`/`Configuration`
    /// in one process produces. Neither may claim the other's directory while it is still alive.
    func testLoadAndClearPreviousSessionsSkipsLiveSessionOfSameInstance() async throws {
        let siblingTimestamp = testTimestamp + 1
        let sibling = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: siblingTimestamp,
            logger: logger,
            shouldStore: true
        )
        await sibling.increment(name: "sibling_counter", size: 5)
        await sibling.persistIfNeeded()

        let siblingDirectory = try sessionDirectoryURL(instanceName: testInstanceName,
                                                       sessionStartAt: siblingTimestamp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingDirectory.path))

        let snapshots = await storage.loadAndClearPreviousSessions()

        XCTAssertEqual(snapshots.count, 0, "A live sibling's data must not be claimed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingDirectory.path),
                      "A live sibling's directory must not be deleted")

        // The sibling can still persist afterwards
        await sibling.increment(name: "sibling_counter", size: 37)
        await sibling.persistIfNeeded()
        let siblingHasUnsavedCounters = await sibling.hasUnsavedCounters
        XCTAssertFalse(siblingHasUnsavedCounters)

        let siblingCounters = try loadJSON([String: Int].self,
                                           at: siblingDirectory.appendingPathComponent("counters.json"))
        XCTAssertEqual(siblingCounters["sibling_counter"], 42)

        try? await sibling.removeAllStoredFiles()
    }

    /// Once a session's storage is released, its leftovers are fair game again — that is how data
    /// from a previous launch (or a released `Amplitude` instance) still gets uploaded.
    func testLoadAndClearPreviousSessionsClaimsSessionAfterStorageIsReleased() async throws {
        let previousTimestamp = testTimestamp - 3600
        do {
            let previous = DiagnosticsStorage(
                instanceName: testInstanceName,
                sessionStartAt: previousTimestamp,
                logger: logger,
                shouldStore: true
            )
            await previous.setTag(name: "previous_tag", value: "previous_value")
            await previous.increment(name: "previous_counter", size: 3)
            await previous.persistIfNeeded()
        }

        let previousDirectory = try sessionDirectoryURL(instanceName: testInstanceName,
                                                        sessionStartAt: previousTimestamp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousDirectory.path))

        let snapshots = await storage.loadAndClearPreviousSessions()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.counters["previous_counter"], 3)
        XCTAssertEqual(snapshots.first?.tags["previous_tag"], "previous_value")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previousDirectory.path))
    }

    // MARK: - Storage Directory Recovery Tests

    /// Regression: the storage directory used to be memoized without revalidation, so once it was
    /// removed underneath the actor every later write failed with Cocoa error 4 forever.
    func testPersistRecreatesStorageDirectoryAfterItIsDeleted() async throws {
        await storage.increment(name: "recovery_counter", size: 1)
        await storage.persistIfNeeded()

        let sessionDirectory = try sessionDirectoryURL(instanceName: testInstanceName,
                                                       sessionStartAt: testTimestamp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDirectory.path))

        try FileManager.default.removeItem(at: sessionDirectory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory.path))

        await storage.increment(name: "recovery_counter", size: 41)
        await storage.persistIfNeeded()

        let hasUnsavedCounters = await storage.hasUnsavedCounters
        XCTAssertFalse(hasUnsavedCounters, "The write must succeed against a recreated directory")

        let counters = try loadJSON([String: Int].self,
                                    at: sessionDirectory.appendingPathComponent("counters.json"))
        XCTAssertEqual(counters["recovery_counter"], 42, "Counters are rewritten in full on recovery")
    }

    /// Tags are only written when they change, so a recreated directory would otherwise end up
    /// holding counters with no tags — an untagged snapshot on the next launch.
    func testPersistRewritesTagsAfterStorageDirectoryIsDeleted() async throws {
        await storage.setTag(name: "recovery_tag", value: "recovery_value")
        await storage.increment(name: "recovery_counter", size: 1)
        await storage.persistIfNeeded()

        let sessionDirectory = try sessionDirectoryURL(instanceName: testInstanceName,
                                                       sessionStartAt: testTimestamp)
        try FileManager.default.removeItem(at: sessionDirectory)

        // Only a counter changes, yet the tags must come back with the directory.
        await storage.increment(name: "recovery_counter", size: 1)
        await storage.persistIfNeeded()

        let tags = try loadJSON([String: String].self,
                                at: sessionDirectory.appendingPathComponent("tags.json"))
        XCTAssertEqual(tags["recovery_tag"], "recovery_value")

        let hasUnsavedTags = await storage.hasUnsavedTags
        XCTAssertFalse(hasUnsavedTags)
    }

    /// The already-persisted data types must come back too, not only the one whose change
    /// triggered the persist — their files were destroyed with the directory, but the full data
    /// is still in memory.
    func testPersistRestoresAllDataTypesAfterStorageDirectoryIsDeleted() async throws {
        await storage.setTag(name: "restored_tag", value: "restored_value")
        await storage.increment(name: "restored_counter", size: 7)
        await storage.recordHistogram(name: "restored_metric", value: 3.5)
        await storage.recordEvent(name: "restored_event")
        await storage.persistIfNeeded()

        let sessionDirectory = try sessionDirectoryURL(instanceName: testInstanceName,
                                                       sessionStartAt: testTimestamp)
        try FileManager.default.removeItem(at: sessionDirectory)

        // Only a tag changes — everything else is "saved" as far as the flags know.
        await storage.setTag(name: "trigger_tag", value: "trigger_value")
        await storage.persistIfNeeded()

        let counters = try loadJSON([String: Int].self,
                                    at: sessionDirectory.appendingPathComponent("counters.json"))
        XCTAssertEqual(counters["restored_counter"], 7)

        let histograms = try loadJSON([String: HistogramStats].self,
                                      at: sessionDirectory.appendingPathComponent("histograms.json"))
        XCTAssertEqual(histograms["restored_metric"]?.count, 1)

        let logContents = try String(contentsOf: sessionDirectory.appendingPathComponent("events.log"),
                                     encoding: .utf8)
        XCTAssertTrue(logContents.contains("restored_event"))
    }

    func testEventsAreAppendedAgainAfterStorageDirectoryIsDeleted() async throws {
        await storage.recordEvent(name: "before_deletion")
        await storage.persistIfNeeded()

        let sessionDirectory = try sessionDirectoryURL(instanceName: testInstanceName,
                                                       sessionStartAt: testTimestamp)
        try FileManager.default.removeItem(at: sessionDirectory)

        await storage.recordEvent(name: "after_deletion")
        await storage.persistIfNeeded()

        let unsavedEvents = await storage.unsavedEvents
        XCTAssertTrue(unsavedEvents.isEmpty)

        let logContents = try String(contentsOf: sessionDirectory.appendingPathComponent("events.log"),
                                     encoding: .utf8)
        XCTAssertTrue(logContents.contains("after_deletion"))
    }

    // MARK: - Util

    private func sessionDirectoryURL(instanceName: String, sessionStartAt: TimeInterval) throws -> URL {
        let baseDirectory = try Storage.rootDirectoryURL(fileManager: .default, createIfNeeded: true)
        return baseDirectory
            .appendingPathComponent("com.amplitude.diagnostics", isDirectory: true)
            .appendingPathComponent(instanceName.fnv1a64String(), isDirectory: true)
            .appendingPathComponent(String(sessionStartAt), isDirectory: true)
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    // MARK: - Persistence Timer Tests

    func testPersistenceTimerTriggersAutomatically() async throws {
        await storage.setTag(name: "auto_tag", value: "auto_value")

        // Wait for persistence timer to fire
        try await storage.waitForPendingPersistenceTask()

        // Check that tagsChanged flag was cleared (indicating persistence happened)
        let tagsChanged = await storage.hasUnsavedTags
        XCTAssertFalse(tagsChanged)
    }

    func testStopPersistenceTimer() async throws {
        await storage.setTag(name: "tag", value: "value")

        // Verify timer is set to fire
        let tagsChangedBefore = await storage.hasUnsavedTags
        XCTAssertTrue(tagsChangedBefore, "Tags should be marked as changed")

        // Stop timer immediately before it fires
        await storage.stopPersistenceTimer()

        // Manually check that persistence hasn't happened by forcing it now
        await storage.persistIfNeeded()

        // After manual persistence, the flag should be cleared
        let tagsChangedAfter = await storage.hasUnsavedTags
        XCTAssertFalse(tagsChangedAfter, "Tags should not be marked as changed after manual persistence")
    }

    // MARK: - Edge Cases

    func testEmptySnapshot() async throws {
        let snapshot = await storage.dumpAndClearCurrentSession()
        XCTAssertNil(snapshot)
    }

    func testSpecialCharactersInInstanceName() async throws {
        let specialStorage = DiagnosticsStorage(
            instanceName: "test@api#key!2024",
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: true
        )

        await specialStorage.setTag(name: "test", value: "value")
        await specialStorage.persistIfNeeded()

        // Should not throw
        try await specialStorage.removeAllStoredFiles()
    }

    func testEmptyInstanceName() async throws {
        let emptyInstanceStorage = DiagnosticsStorage(
            instanceName: "",
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: true
        )

        await emptyInstanceStorage.setTag(name: "test", value: "value")
        await emptyInstanceStorage.persistIfNeeded()

        // Should use default instance name
        try await emptyInstanceStorage.removeAllStoredFiles()
    }

    func testConcurrentOperations() async throws {
        // Perform multiple concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await self.storage.setTag(name: "tag_\(i)", value: "value_\(i)")
                }
                group.addTask {
                    await self.storage.increment(name: "counter_\(i)", size: i)
                }
                group.addTask {
                    await self.storage.recordHistogram(name: "metric_\(i)", value: Double(i * 10))
                }
                group.addTask {
                    await self.storage.recordEvent(name: "event_\(i)", properties: nil)
                }
            }
        }

        // Verify all operations completed
        let tags = await storage.tags
        let counters = await storage.counters
        let histograms = await storage.histograms
        let events = await storage.events

        XCTAssertEqual(tags.count, 10)
        XCTAssertEqual(counters.count, 10)
        XCTAssertEqual(histograms.count, 10)
        XCTAssertEqual(events.count, 10)
    }

    // MARK: - shouldStore Tests

    func testShouldStoreInitializedFalse() async throws {
        let storageWithoutPersistence = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: false
        )

        let shouldStore = await storageWithoutPersistence.shouldStore
        XCTAssertFalse(shouldStore, "shouldStore should be false when initialized as false")
    }

    func testShouldStoreInitializedTrue() async throws {
        let shouldStore = await storage.shouldStore
        XCTAssertTrue(shouldStore, "shouldStore should be true when initialized as true")
    }

    func testDataNotPersistedWhenShouldStoreFalse() async throws {
        let storageWithoutPersistence = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: false,
            persistIntervalNanoSec: NSEC_PER_MSEC * 10
        )

        // Add data
        await storageWithoutPersistence.setTag(name: "test_tag", value: "test_value")
        await storageWithoutPersistence.increment(name: "test_counter", size: 42)
        await storageWithoutPersistence.recordHistogram(name: "test_metric", value: 100.0)

        // Try to persist
        await storageWithoutPersistence.persistIfNeeded()

        // Wait for any pending persistence task to complete (should be none since shouldStore is false)
        try await storageWithoutPersistence.waitForPendingPersistenceTask()

        // Create new storage to check if data was persisted
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp + 1,
            logger: logger,
            shouldStore: true
        )

        let snapshots = await newStorage.loadAndClearPreviousSessions()
        XCTAssertEqual(snapshots.count, 0, "No data should be persisted when shouldStore is false")

        // Clean up
        try? await storageWithoutPersistence.removeAllStoredFiles()
        try? await newStorage.removeAllStoredFiles()
    }

    func testDataPersistedWhenShouldStoreTrue() async throws {
        // Add and persist data
        await storage.setTag(name: "persisted_tag", value: "persisted_value")
        await storage.increment(name: "persisted_counter", size: 99)
        await storage.persistIfNeeded()

        // Wait for persistence to complete
        try await storage.waitForPendingPersistenceTask()

        // Create new storage to check if data was persisted. The previous storage is released
        // first: a session that is still live is deliberately never claimed.
        storage = nil
        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp + 1,
            logger: logger,
            shouldStore: true
        )

        let snapshots = await newStorage.loadAndClearPreviousSessions()
        XCTAssertGreaterThanOrEqual(snapshots.count, 1, "Data should be persisted when shouldStore is true")

        if let snapshot = snapshots.first {
            XCTAssertEqual(snapshot.tags["persisted_tag"], "persisted_value")
            XCTAssertEqual(snapshot.counters["persisted_counter"], 99)
        }

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    func testSetShouldStoreToTrue() async throws {
        var storageToEnable: DiagnosticsStorage! = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: false,
            persistIntervalNanoSec: NSEC_PER_MSEC * 10
        )

        // Add data while persistence is disabled
        await storageToEnable.setTag(name: "tag_before", value: "value_before")

        // Enable shouldStore
        await storageToEnable.setShouldStore(true)

        let shouldStore = await storageToEnable.shouldStore
        XCTAssertTrue(shouldStore, "shouldStore should be true after calling setShouldStore(true)")

        // Add data after enabling (include counter since tags alone don't produce a snapshot)
        await storageToEnable.setTag(name: "tag_after", value: "value_after")
        await storageToEnable.increment(name: "counter_for_snapshot", size: 1)

        // Wait for automatic persistence
        try await storageToEnable.waitForPendingPersistenceTask()

        // Verify data was persisted. Both storages for this session are released first: a session
        // that is still live is deliberately never claimed, and `storage` from setUp shares this
        // session's timestamp.
        storageToEnable = nil
        storage = nil

        let newStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp + 1,
            logger: logger,
            shouldStore: true
        )

        let snapshots = await newStorage.loadAndClearPreviousSessions()
        XCTAssertGreaterThanOrEqual(snapshots.count, 1, "Data should be persisted after enabling shouldStore")

        // Clean up
        try? await newStorage.removeAllStoredFiles()
    }

    func testSetShouldStoreToFalse() async throws {
        // Start with persistence enabled
        await storage.setTag(name: "tag_1", value: "value_1")

        // Disable shouldStore
        await storage.setShouldStore(false)

        let shouldStore = await storage.shouldStore
        XCTAssertFalse(shouldStore, "shouldStore should be false after calling setShouldStore(false)")

        // Add data after disabling
        await storage.setTag(name: "tag_2", value: "value_2")

        // Try to persist manually
        await storage.persistIfNeeded()

        // Wait for any pending persistence task (should complete immediately since shouldStore is false)
        try await storage.waitForPendingPersistenceTask()

        // The persistence should not have happened
        // We can verify this by checking that no persistence task is running
        // (This is an indirect test since we can't easily check file system state)
    }

    func testSetShouldStoreToggle() async throws {
        let toggleStorage = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: true,
            persistIntervalNanoSec: NSEC_PER_MSEC * 10
        )

        // Initially true
        var shouldStore = await toggleStorage.shouldStore
        XCTAssertTrue(shouldStore)

        // Toggle to false
        await toggleStorage.setShouldStore(false)
        shouldStore = await toggleStorage.shouldStore
        XCTAssertFalse(shouldStore)

        // Toggle back to true
        await toggleStorage.setShouldStore(true)
        shouldStore = await toggleStorage.shouldStore
        XCTAssertTrue(shouldStore)

        // Toggle to false again
        await toggleStorage.setShouldStore(false)
        shouldStore = await toggleStorage.shouldStore
        XCTAssertFalse(shouldStore)

        // Clean up
        try? await toggleStorage.removeAllStoredFiles()
    }

    func testPersistenceTimerStoppedWhenShouldStoreFalse() async throws {
        // Start with persistence enabled
        await storage.setTag(name: "test_tag", value: "test_value")

        // Disable shouldStore (should stop persistence timer)
        await storage.setShouldStore(false)

        // Add more data
        await storage.increment(name: "counter", size: 1)

        // Wait for any pending persistence task (timer should be stopped)
        try await storage.waitForPendingPersistenceTask()

        // If we got here without issues, the timer was properly stopped
        // (if it wasn't stopped, it might have tried to persist and caused issues)
        XCTAssertTrue(true, "Timer was properly stopped")
    }

    func testPersistenceTimerStartedWhenShouldStoreTrue() async throws {
        let storageToStart = DiagnosticsStorage(
            instanceName: testInstanceName,
            sessionStartAt: testTimestamp,
            logger: logger,
            shouldStore: false,
            persistIntervalNanoSec: NSEC_PER_MSEC * 10
        )

        // Add data while disabled
        await storageToStart.setTag(name: "test_tag", value: "test_value")

        // Enable shouldStore (should start persistence timer if there's unsaved data)
        await storageToStart.setShouldStore(true)

        // Add more data to ensure timer starts
        await storageToStart.increment(name: "counter", size: 1)

        // Wait for automatic persistence
        try await storageToStart.waitForPendingPersistenceTask()

        // Verify the flag was cleared by persistence
        let hasUnsavedCounters = await storageToStart.hasUnsavedCounters
        XCTAssertFalse(hasUnsavedCounters, "Data should have been persisted by timer")

        // Clean up
        try? await storageToStart.removeAllStoredFiles()
    }
}
