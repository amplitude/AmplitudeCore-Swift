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
    public let httpClient: (any HttpClient)?
    public let logger: CoreLogger

    @_spi(Internal)
    public let diagnosticsClient: CoreDiagnostics

    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error),
                httpClient: (any HttpClient)? = nil) {
        self.init(apiKey: apiKey,
                  instanceName: instanceName,
                  serverZone: serverZone,
                  logger: logger,
                  remoteConfigClient: nil,
                  diagnosticsClient: nil,
                  httpClient: httpClient)
    }

    // 1.5.x signature, kept for binary compatibility with prebuilt Session Replay and Guides & Surveys binaries.
    @available(*, deprecated, message: "Use init(apiKey:instanceName:serverZone:logger:httpClient:)")
    @_disfavoredOverload
    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error)) {
        self.init(apiKey: apiKey,
                  instanceName: instanceName,
                  serverZone: serverZone,
                  logger: logger,
                  httpClient: nil)
    }

    // 1.5.x signature, kept for binary compatibility with prebuilt Session Replay and Guides & Surveys binaries.
    @_spi(Internal)
    @available(*, deprecated, message: "Use init(apiKey:instanceName:serverZone:logger:remoteConfigClient:diagnosticsClient:httpClient:)")
    @_disfavoredOverload
    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error),
                remoteConfigClient: RemoteConfigClient?,
                diagnosticsClient: CoreDiagnostics?) {
        self.init(apiKey: apiKey,
                  instanceName: instanceName,
                  serverZone: serverZone,
                  logger: logger,
                  remoteConfigClient: remoteConfigClient,
                  diagnosticsClient: diagnosticsClient,
                  httpClient: nil)
    }

    @_spi(Internal)
    public init(apiKey: String,
                instanceName: String = "$default_instance",
                serverZone: ServerZone = .US,
                logger: CoreLogger = OSLogger(logLevel: .error),
                remoteConfigClient: RemoteConfigClient?,
                diagnosticsClient: CoreDiagnostics?,
                httpClient: (any HttpClient)? = nil) {
        self.apiKey = apiKey
        self.instanceName = instanceName
        self.serverZone = serverZone
        self.logger = logger
        self.httpClient = httpClient
        self.remoteConfigClient = remoteConfigClient ?? RemoteConfigClient(apiKey: apiKey,
                                                                           serverZone: serverZone,
                                                                           instanceName: instanceName,
                                                                           logger: logger,
                                                                           httpClient: httpClient)
        self.diagnosticsClient = diagnosticsClient ?? DiagnosticsClient(apiKey: apiKey,
                                                                        serverZone: serverZone,
                                                                        instanceName: instanceName,
                                                                        logger: logger,
                                                                        remoteConfigClient: self.remoteConfigClient,
                                                                        httpClient: httpClient ?? URLSessionHttpClient())
    }

}
