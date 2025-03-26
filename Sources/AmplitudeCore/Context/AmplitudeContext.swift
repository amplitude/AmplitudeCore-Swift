//
//  AmplitudeContext.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/14/25.
//

public struct AmplitudeContext {

    public let apiKey: String
    public let serverZone: ServerZone
    public let remoteConfigClient: RemoteConfigClient
    public let logger: any Logger

    public init(apiKey: String,
                serverZone: ServerZone,
                remoteConfigClient: RemoteConfigClient,
                logger: (any Logger)? = nil) {
        self.apiKey = apiKey
        self.serverZone = serverZone
        self.remoteConfigClient = remoteConfigClient
        self.logger = logger ?? ConsoleLogger(logLevel: .ERROR)
    }
    // TODO: Diagnostics, etc...

}
