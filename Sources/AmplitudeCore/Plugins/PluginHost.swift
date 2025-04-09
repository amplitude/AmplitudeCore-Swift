//
//  PluginHost.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/10/25.
//

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol PluginHost {

    func plugin(name: String) -> (UniversalPlugin)?
}
