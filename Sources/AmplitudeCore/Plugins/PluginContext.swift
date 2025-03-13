//
//  AnalyticsContext.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/10/25.
//

public protocol PluginContext {

    var apiKey: String { get }
    var serverZone: ServerZone { get }
    var remoteConfigClient: RemoteConfigClient { get }
    var logger: Logger { get }

    // TODO: Diagnostics, etc...
}
