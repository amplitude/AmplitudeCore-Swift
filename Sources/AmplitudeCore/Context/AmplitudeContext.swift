//
//  AmplitudeContext.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/14/25.
//
import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct AmplitudeContext {

    public static var coreLibraryName: String { Constants.SDK_LIBRARY }
    public static var coreLibraryVersion: String { Constants.SDK_VERSION }

    public let apiKey: String
    public let instanceName: String
    public let serverZone: ServerZone
    public let remoteConfigClient: RemoteConfigClient
    public let logger: CoreLogger

    @_spi(Internal)
    public let diagnosticsClient: CoreDiagnostics

    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error)) {
        self.init(apiKey: apiKey,
                  instanceName: instanceName,
                  serverZone: serverZone,
                  logger: logger,
                  remoteConfigClient: nil,
                  diagnosticsClient: nil)
    }

    @_spi(Internal)
    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error),
                remoteConfigClient: RemoteConfigClient?,
                diagnosticsClient: CoreDiagnostics?) {
        self.apiKey = apiKey
        self.instanceName = instanceName
        self.serverZone = serverZone
        self.logger = logger
        self.remoteConfigClient = remoteConfigClient ?? RemoteConfigClient(apiKey: apiKey,
                                                                           serverZone: serverZone,
                                                                           instanceName: instanceName,
                                                                           logger: logger)
        self.diagnosticsClient = diagnosticsClient ?? DiagnosticsClient(apiKey: apiKey,
                                                                        serverZone: serverZone,
                                                                        instanceName: instanceName,
                                                                        logger: logger,
                                                                        remoteConfigClient: self.remoteConfigClient)
    }

}
