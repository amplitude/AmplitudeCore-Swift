//
//  Selectable.swift
//  AmplitudeCore
//
//  Created by Brian Giori on 9/11/23.
//  Ported from experiment-ios-client v1.20.3 (Sources/Experiment/Selectable.swift).
//

import Foundation

protocol Selectable {
    func select(selector: String) -> Any?
}

extension NSDictionary: Selectable {
    func select(selector: String) -> Any? {
        return self[selector]
    }
}

extension Dictionary: Selectable where Key == String {
    func select(selector: String) -> Any? {
        return (self as NSDictionary).select(selector: selector)
    }
}

extension Selectable {
    func select(selector: [String]) -> Any? {
        guard let lastSelector = selector.last else {
            return nil
        }
        var selectable: Selectable = self
        for selectorElement in selector.dropLast() {
            guard let value = selectable.select(selector: selectorElement) as? Selectable else {
                return nil
            }
            selectable = value
        }
        let result = selectable.select(selector: lastSelector)
        return result is NSNull ? nil : result
    }
}
