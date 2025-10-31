//
//  Sample.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 4/16/24.
//

import Foundation

class Sample {

    static func isSessionInSample(seed: String, sampleRate: Float) -> Bool {
        // generate hash code
        let hash: Int64 = seed.utf16.reduce(0) { hash, code in
            return (hash << 5) &- hash &+ Int64(code)
        }

        // Convert to UInt64 to avoid abs(Int64.min) undefined behavior
        // This gives us the magnitude without sign issues
        let magnitude = UInt64(bitPattern: hash)
        let scaledHash = (magnitude &* 31) % 1_000_000
        return Float(scaledHash) / 1_000_000 < sampleRate
    }
}
