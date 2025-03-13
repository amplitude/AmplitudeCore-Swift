//
//  PluginHost.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/10/25.
//

protocol PluginHost {

    func plugin(name: String) -> (UniversalPlugin)?
}
