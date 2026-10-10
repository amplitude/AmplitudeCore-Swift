//
//  SemanticVersion.swift
//  AmplitudeCore
//
//  Created by Brian Giori on 9/11/23.
//  Ported from experiment-ios-client v1.20.3 (Sources/Experiment/SemanticVersion.swift).
//

import Foundation

struct SemanticVersion: Comparable {

    private static let MAJOR_MINOR_REGEX = "(\\d+)\\.(\\d+)"
    private static let PATCH_REGEX = "(\\d+)"
    private static let PRERELEASE_REGEX = "(-(([-\\w]+\\.?)*))?"
    private static let VERSION_PATTERN = "^\(MAJOR_MINOR_REGEX)(\\.\(PATCH_REGEX)\(PRERELEASE_REGEX))?$"

    let major: Int
    let minor: Int
    let patch: Int
    let preRelease: String?

    // NSRegularExpression is thread-safe, so one instance serves every evaluation.
    private static let regex = try? NSRegularExpression(pattern: VERSION_PATTERN)

    static func parse(version: String) -> SemanticVersion? {
        // NSRange counts UTF-16 units, not characters.
        guard let regex, let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..., in: version)) else {
            return nil
        }
        let captureGroups: [String?] = (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: version).map { String(version[$0]) }
        }
        // A component too large for an Int makes the value a non-version, which then compares as a string;
        // only an absent patch means 0.
        guard let major = captureGroups[1].flatMap({ Int($0) }), let minor = captureGroups[2].flatMap({ Int($0) }) else {
            return nil
        }
        var patch = 0
        if let patchText = captureGroups[4] {
            guard let value = Int(patchText) else {
                return nil
            }
            patch = value
        }
        return SemanticVersion(major: major, minor: minor, patch: patch, preRelease: captureGroups[5])
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }
        switch (lhs.preRelease, rhs.preRelease) {
        case let (lhsPreRelease?, rhsPreRelease?):
            return lhsPreRelease < rhsPreRelease
        case (.some, nil):
            // A pre-release precedes its release.
            return true
        default:
            return false
        }
    }
}
