//
//  Sample.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 4/16/24.
//

import Foundation

class Sample {
    static func isInSample(seed: String, sampleRate: Float) -> Bool {
        // generate java string style hash code
        let hash = Hash.javaStringHash(seed)

        // Convert to UInt64 to avoid abs(Int64.min) undefined behavior
        let magnitude = UInt64(bitPattern: hash)
        let scaledHash = (magnitude &* 31) % 100_000
        return Float(scaledHash) / 100_000 < sampleRate
    }
}

class Hash {
    static func javaStringHash(_ s: String) -> Int64 {
        return s.utf16.reduce(0) { hash, code in
            (hash << 5) &- hash &+ Int64(code)
        }
    }

    static func fnv1a64(_ s: String) -> UInt64 {
        let offsetBasis: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        return s.utf8.reduce(offsetBasis) { hash, byte in
            (hash ^ UInt64(byte)) &* prime
        }
    }
}
