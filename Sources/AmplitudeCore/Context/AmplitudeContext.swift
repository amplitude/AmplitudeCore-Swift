//
//  AmplitudeContext.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/14/25.
//

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AmplitudeContext {

    public let apiKey: String
    public let instanceName: String
    public let serverZone: ServerZone
    public let remoteConfigClient: RemoteConfigClient
    public let logger: CoreLogger

    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error)) {
        self.init(apiKey: apiKey,
                  instanceName: instanceName,
                  serverZone: serverZone,
                  serverUrl: nil,
                  logger: logger)
    }

    @_spi(Internal)
    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                serverUrl: String? = nil,
                logger: CoreLogger = OSLogger(logLevel: .error)) {

        self.apiKey = apiKey
        self.instanceName = instanceName
        self.serverZone = serverZone
        self.logger = logger
        if let serverUrl {
            remoteConfigClient = RemoteConfigClient(apiKey: apiKey,
                                                    serverUrl: serverUrl,
                                                    instanceName: instanceName,
                                                    logger: logger)
        } else {
            remoteConfigClient = RemoteConfigClient(apiKey: apiKey,
                                                    serverZone: serverZone,
                                                    instanceName: instanceName,
                                                    logger: logger)
        }
    }

    // TODO: Diagnostics, etc...

}
