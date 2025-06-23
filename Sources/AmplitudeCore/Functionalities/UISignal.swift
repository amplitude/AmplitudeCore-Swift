//
//  UISignal.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 6/17/25.
//

import Foundation

@objcMembers
public class UIChangeSignal: NSObject {
    public let timestamp: TimeInterval

    public init(timestamp: TimeInterval) {
        self.timestamp = timestamp
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol UISignalProvider: AnyObject {
    var isProviding: Bool { get }

    func addUISignalReceiver(_ receiver: any UISignalReceiver)

    func removeUISignalReceiver(_ receiver: any UISignalReceiver)
}

@objc
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol UISignalReceiver: AnyObject, Sendable {
    func onUIChanged(signal: UIChangeSignal)

    func onStartProviding()

    func onStopProviding()
}
