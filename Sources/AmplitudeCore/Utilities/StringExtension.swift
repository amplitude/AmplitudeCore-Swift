//
//  StringExtension.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 11/21/25.
//

@_spi(Internal)
public enum VersionError: Error, Equatable {
    case invalidVersionString(String)
    case emptyVersionString
}

@_spi(Internal)
public extension String {

    /// compare versions, supports "x", "x.y", "x.y.z"
    /// - Throws: `VersionError` if either version string is invalid
    func isGreaterThanOrEqualToVersion(_ version: String) throws -> Bool {
        let selfComponents = try parseVersionComponents(self)
        let versionComponents = try parseVersionComponents(version)

        let maxLength = max(selfComponents.count, versionComponents.count)

        for i in 0..<maxLength {
            let selfValue = i < selfComponents.count ? selfComponents[i] : 0
            let versionValue = i < versionComponents.count ? versionComponents[i] : 0

            if selfValue > versionValue {
                return true
            } else if selfValue < versionValue {
                return false
            }
        }

        return true // Equal versions
    }

    private func parseVersionComponents(_ versionString: String) throws -> [Int] {
        // Check for empty string
        guard !versionString.isEmpty else {
            throw VersionError.emptyVersionString
        }

        // Check for leading or trailing dots
        if versionString.hasPrefix(".") || versionString.hasSuffix(".") {
            throw VersionError.invalidVersionString(versionString)
        }

        // Check for consecutive dots
        if versionString.contains("..") {
            throw VersionError.invalidVersionString(versionString)
        }

        let parts = versionString.split(separator: ".")

        // Parse components and validate all are numeric (without whitespace)
        var components: [Int] = []
        for part in parts {
            let partString = String(part)

            // Check for whitespace in the part
            if partString.contains(where: { $0.isWhitespace }) {
                throw VersionError.invalidVersionString(versionString)
            }

            // Try to parse as integer
            guard let value = Int(partString) else {
                throw VersionError.invalidVersionString(versionString)
            }
            components.append(value)
        }

        // Check that we have at least one component
        if components.isEmpty {
            throw VersionError.invalidVersionString(versionString)
        }

        return components
    }

}
