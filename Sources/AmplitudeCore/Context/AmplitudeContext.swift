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

    private var remoteConfigSubscription: Any?

    @_spi(Internal)
    public let diagnosticsClient: CoreDiagnostics

    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error)) {
        let diagnosticsClient = DiagnosticsClient(apiKey: apiKey,
                                                  serverZone: serverZone,
                                                  instanceName: instanceName,
                                                  logger: logger)
        self.init(apiKey: apiKey,
                  instanceName: instanceName,
                  serverZone: serverZone,
                  logger: logger,
                  diagnosticsClient: diagnosticsClient)

    }

    @_spi(Internal)
    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error),
                diagnosticsClient: CoreDiagnostics) {
        self.apiKey = apiKey
        self.instanceName = instanceName
        self.serverZone = serverZone
        self.logger = logger
        let remoteConfigClient = RemoteConfigClient(apiKey: apiKey,
                                                    serverZone: serverZone,
                                                    instanceName: instanceName,
                                                    logger: logger)
        self.remoteConfigClient = remoteConfigClient
        self.diagnosticsClient = diagnosticsClient

        Task {
            if let diagnosticsClient = diagnosticsClient as? DiagnosticsClient {
                await diagnosticsClient.setRemoteConfigClient(remoteConfigClient)
            }
        }
    }

}
