//
//  Plan.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

public struct Plan: Codable {
    public var branch: String?
    public var source: String?
    public var version: String?
    public var versionId: String?

    public init(branch: String? = nil,
                source: String? = nil,
                version: String? = nil,
                versionId: String? = nil) {
        self.branch = branch
        self.source = source
        self.version = version
        self.versionId = versionId
    }
}
