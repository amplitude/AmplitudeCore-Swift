//
//  Murmur3.swift
//  AmplitudeCore
//
//  Created by Brian Giori on 9/11/23.
//  Adapted from experiment-ios-client v1.20.3 (Sources/Experiment/Murmur3.swift).
//

extension Hash {

    /// MurmurHash3 x86 32-bit of the string's UTF-8 bytes, which experiment-core uses to bucket.
    static func murmur3x86_32(_ s: String, seed: UInt32 = 0) -> UInt32 {
        return Murmur3x86_32.hash(s, seed: seed)
    }

    enum Murmur3x86_32 {

        private static let C1: UInt32 = 0xcc9e2d51
        private static let C2: UInt32 = 0x1b873593
        private static let M: UInt32 = 5
        private static let N: UInt32 = 0xe6546b64

        @inline(__always)
        private static func rotl(_ x: UInt32, _ r: UInt32) -> UInt32 {
            (x << r) | (x >> (32 - r))
        }

        @inline(__always)
        private static func scramble(_ k: UInt32) -> UInt32 {
            rotl(k &* C1, 15) &* C2
        }

        @inline(__always)
        private static func fmix(_ h: UInt32) -> UInt32 {
            var x = h
            x ^= x >> 16
            x &*= 0x85ebca6b
            x ^= x >> 13
            x &*= 0xc2b2ae35
            x ^= x >> 16
            return x
        }

        static func hash(_ string: String, seed: UInt32 = 0) -> UInt32 {
            let bytes = Array(string.utf8)
            let len = bytes.count
            var h = seed
            var index = 0

            // 4-byte blocks
            while index <= len - 4 {
                h ^= scramble(read32(bytes, index))
                h = rotl(h, 13) &* M &+ N
                index += 4
            }

            // remaining bytes, little-endian
            var k: UInt32 = 0
            var shift: UInt32 = 0
            while index < len {
                k |= UInt32(bytes[index]) << shift
                shift += 8
                index += 1
            }
            if shift > 0 {
                h ^= scramble(k)
            }

            h ^= UInt32(len)
            return fmix(h)
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
