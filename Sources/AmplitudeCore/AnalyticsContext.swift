//
//  AnalyticsContext.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/10/25.
//

public protocol AnalyticsContext: AnyObject {

    var apiKey: String { get }
    var serverZone: ServerZone { get }
    //var remoteConfigClient: RemoteConfigClient { get }

    // TODO: Logging, Diagnostics, etc...
}
