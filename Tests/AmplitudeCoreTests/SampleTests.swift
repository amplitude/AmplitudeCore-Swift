//
//  SampleTest.swift
//  AmplitudeSessionReplayTests
//
//  Created by Chris Leonavicius on 8/23/24.
//

@testable import AmplitudeCore
import XCTest

class SampleTests: XCTestCase {

    func testSample() {
        XCTAssertEqual(sample(sampleRate: 1.0), 1.0)
        XCTAssertEqual(sample(sampleRate: 0.0), 0.0)
        XCTAssertEqual(sample(sampleRate: 0.5), 0.5, accuracy: 0.05)
        XCTAssertEqual(sample(sampleRate: 0.1), 0.1, accuracy: 0.05)
        XCTAssertEqual(sample(sampleRate: 0.9), 0.9, accuracy: 0.05)
    }

    func sample(sessionCount: Int64 = 1000, sampleRate: Double) -> Double {
        let start: Int64 = 577782000
        var totalSampled = 0
        for sessionId in start..<(start + sessionCount) {
            totalSampled += Sample.isInSample(seed: String(sessionId), sampleRate: sampleRate) ? 1 : 0
        }
        return Double(totalSampled) / Double(sessionCount)
    }
}

class XXHash32Tests: XCTestCase {

    // Helper: format UInt32 as 8-char lowercase hex (like xxhsum / hexdigest)
    private func hex8(_ x: UInt32) -> String {
        String(format: "%08x", x)
    }

    func testVector_spammishRepetition_seed0() {
        let s = "Nobody inspects the spammish repetition"
        let h = Hash.XXHash32.hash(s, seed: 0)
        XCTAssertEqual(hex8(h), "e2293b2f")
    }

    func testVector_unsigned32SeedWarningString_seed0() {
        let s = "I want an unsigned 32-bit seed!"
        let h = Hash.XXHash32.hash(s, seed: 0)
        XCTAssertEqual(hex8(h), "f7a35af8")
    }

    func testVector_unsigned32SeedWarningString_seed1() {
        let s = "I want an unsigned 32-bit seed!"
        let h = Hash.XXHash32.hash(s, seed: 1)
        XCTAssertEqual(hex8(h), "d8d4b4ba")
    }

    func testDeterminism_sameInputSameOutput() {
        let s = "session-123"
        let a = Hash.XXHash32.hash(s, seed: 0)
        let b = Hash.XXHash32.hash(s, seed: 0)
        XCTAssertEqual(a, b)
    }

    func testApacheGetValueSemantics_unsignedLongRange() {
        // Match server logic
        // Apache Commons Codec XXHash32.getValue() returns a long representing an unsigned 32-bit hash.
        // So when we widen, it should be in [0, 2^32-1].
        let s = "anything"
        let h32 = Hash.XXHash32.hash(s, seed: 0)
        let value = Int64(UInt64(h32)) // "getValue()" style widening
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, Int64(UInt64(UInt32.max)))
    }
}
