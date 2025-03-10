//
//  PluginHost.swift
//  AmplitudeCore
//
//  Created by Chris Leonavicius on 3/10/25.
//

protocol PluginHost {

    @discardableResult
    func add(plugin: Plugin) -> Self

    @discardableResult
    func remove(plugin: Plugin) -> Self

    func plugin(name: String) -> Plugin?
}
