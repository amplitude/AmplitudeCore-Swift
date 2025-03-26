//
//  PluginHost.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/10/25.
//

public protocol PluginHost {

    func plugin(name: String) -> (UniversalPlugin)?
}
