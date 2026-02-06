//
//  Sample.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 4/16/24.
//

import Foundation

public class Sample {
    public static func isInSample(seed: String, sampleRate: Double) -> Bool {
        let hash = UInt64(Hash.xxhash32(seed))
        let absHashMultiply = hash * 31
        let absHashMod = absHashMultiply % 1_000_000
        let effectiveSampleRate = Double(absHashMod) / 1_000_000.0
        return effectiveSampleRate < Double(sampleRate)
    }
}

class Hash {
    static func fnv1a64(_ s: String) -> UInt64 {
        let offsetBasis: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        return s.utf8.reduce(offsetBasis) { hash, byte in
            (hash ^ UInt64(byte)) &* prime
        }
    }

    static func xxhash32(_ s: String, seed: UInt32 = 0) -> UInt32 {
        return XXHash32.hash(s, seed: seed)
    }

    enum XXHash32 {

        // Primes
        private static let P1: UInt32 = 0x9E3779B1
        private static let P2: UInt32 = 0x85EBCA77
        private static let P3: UInt32 = 0xC2B2AE3D
        private static let P4: UInt32 = 0x27D4EB2F
        private static let P5: UInt32 = 0x165667B1

        @inline(__always)
        private static func rotl(_ x: UInt32, _ r: UInt32) -> UInt32 {
            (x << r) | (x >> (32 - r))
        }

        @inline(__always)
        private static func round(_ acc: UInt32, _ input: UInt32) -> UInt32 {
            var a = acc &+ input &* P2
            a = rotl(a, 13)
            return a &* P1
        }

        @inline(__always)
        private static func avalanche(_ h: UInt32) -> UInt32 {
            var x = h
            x ^= x >> 15
            x &*= P2
            x ^= x >> 13
            x &*= P3
            x ^= x >> 16
            return x
        }

        static func hash(_ string: String, seed: UInt32 = 0) -> UInt32 {
            let bytes = Array(string.utf8)
            let len = bytes.count

            if len == 0 {
                return avalanche(seed &+ P5)
            }

            var index = 0
            var h: UInt32

            if len >= 16 {
                var v1 = seed &+ P1 &+ P2
                var v2 = seed &+ P2
                var v3 = seed
                var v4 = seed &- P1

                while index <= len - 16 {
                    v1 = round(v1, read32(bytes, index)); index += 4
                    v2 = round(v2, read32(bytes, index)); index += 4
                    v3 = round(v3, read32(bytes, index)); index += 4
                    v4 = round(v4, read32(bytes, index)); index += 4
                }

                h = rotl(v1, 1)
                  &+ rotl(v2, 7)
                  &+ rotl(v3, 12)
                  &+ rotl(v4, 18)
            } else {
                h = seed &+ P5
            }

            h &+= UInt32(len)

            // 4-byte chunks
            while index <= len - 4 {
                h &+= read32(bytes, index) &* P3
                h = rotl(h, 17) &* P4
                index += 4
            }

            // remaining bytes
            while index < len {
                h &+= UInt32(bytes[index]) &* P5
                h = rotl(h, 11) &* P1
                index += 1
            }

            return avalanche(h)
        }

        @inline(__always)
        private static func read32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
            UInt32(bytes[i])
            | UInt32(bytes[i + 1]) << 8
            | UInt32(bytes[i + 2]) << 16
            | UInt32(bytes[i + 3]) << 24
        }
    }
}
