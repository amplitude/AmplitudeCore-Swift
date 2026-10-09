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

    static func parse(version: String?) -> SemanticVersion? {
        guard let version else {
            return nil
        }
        guard let regex = try? NSRegularExpression(pattern: VERSION_PATTERN) else {
            return nil
        }
        let matches = regex.matches(in: version, range: NSRange(0..<version.count))
        guard let match = matches.first else {
            return nil
        }
        var captureGroups: [String?] = []
        for rangeIndex in 0..<match.numberOfRanges {
            let matchRange = match.range(at: rangeIndex)
            if let substringRange = Range(matchRange, in: version) {
                captureGroups.append(String(version[substringRange]))
            } else {
                captureGroups.append(nil)
            }
        }
        guard let major = Int(string: captureGroups[1]), let minor = Int(string: captureGroups[2]) else {
            return nil
        }
        let patch = Int(string: captureGroups[4]) ?? 0
        let preRelease = captureGroups[5]
        return SemanticVersion(major: major, minor: minor, patch: patch, preRelease: preRelease)
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

private extension Int {
    init?(string: String?) {
        guard let string else {
            return nil
        }
        self.init(string)
    }
}
