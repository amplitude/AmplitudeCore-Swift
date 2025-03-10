//
//  IngestionMetadata.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 1/29/25.
//

public struct IngestionMetadata: Codable {
    public var sourceName: String?
    public var sourceVersion: String?

    enum CodingKeys: String, CodingKey {
        case sourceName = "source_name"
        case sourceVersion = "source_version"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourceName = try values.decodeIfPresent(String.self, forKey: .sourceName)
        sourceVersion = try values.decodeIfPresent(String.self, forKey: .sourceVersion)
    }

    public init(sourceName: String? = nil, sourceVersion: String? = nil) {
        self.sourceName = sourceName
        self.sourceVersion = sourceVersion
    }
}
