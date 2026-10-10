//
//  Murmur3Tests.swift
//  AmplitudeCoreTests
//
//  Created by Brian Giori on 9/11/23.
//  Ported from experiment-ios-client v1.20.3 (Tests/ExperimentTests/Murmur3Tests.swift).
//

import XCTest
import Foundation
@_spi(Internal) @testable import AmplitudeCore

let MURMUR_SEED: UInt32 = 0x7f3a21ea

class Murmur3Tests: XCTestCase {

    func testMurmur3HashSimple() {
        let input = "brian"
        let result = Hash.murmur3x86_32(input, seed: MURMUR_SEED)
        XCTAssertEqual(result, 3948467465)
    }

    func testMurmur3EnglishWords() {
        let inputs = ENGLISH_WORDS.split(separator: "\n")
        let outputs = MURMUR3_X86_32.split(separator: "\n")
        for i in 0..<inputs.count {
            let input = String(inputs[i])
            let output = UInt32(outputs[i])
            let result = Hash.murmur3x86_32(input, seed: MURMUR_SEED)
            XCTAssertEqual(result, output)
        }
    }

    func testUnicodeStrings() {
        XCTAssertEqual(Hash.murmur3x86_32("My hovercraft is full of eels."), 2953494853)
        XCTAssertEqual(Hash.murmur3x86_32("My 🚀 is full of 🦎."), 1818098979)
        XCTAssertEqual(Hash.murmur3x86_32("吉 星 高 照"), 3435142074)
    }
}
