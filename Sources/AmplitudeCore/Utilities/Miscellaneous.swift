//
//  Sample.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 4/16/24.
//

import Foundation

class Sample {
    static func isInSample(seed: String, sampleRate: Double) -> Bool {
        let hash = Hash.javaStyleHash64(seed)
        let scaledHash = (hash &* 31) % 100_000
        return scaledHash < UInt64(sampleRate * 100_000)
    }
}

class Hash {
    static func javaStyleHash64(_ s: String) -> UInt64 {
        let hash = s.utf16.reduce(0) { hash, code in
            (hash << 5) &- hash &+ Int64(code)
        }
        // Convert to UInt64 to avoid abs(Int64.min) undefined behavior
        return UInt64(bitPattern: hash)
    }

    static func fnv1a64(_ s: String) -> UInt64 {
        let offsetBasis: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        return s.utf8.reduce(offsetBasis) { hash, byte in
            (hash ^ UInt64(byte)) &* prime
        }
    }
}
