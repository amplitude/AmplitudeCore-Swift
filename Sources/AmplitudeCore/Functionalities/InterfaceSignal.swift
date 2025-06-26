//
//  InterfaceSignal.swift
//  AmplitudeCore
//
//  Created by Jin Xu on 6/17/25.
//

import Foundation

@objcMembers
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public class InterfaceChangeSignal: NSObject {
    public let time: Date

    public init(time: Date) {
        self.time = time
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol InterfaceSignalProvider: AnyObject {
    var isProviding: Bool { get }

    func addInterfaceSignalReceiver(_ receiver: any InterfaceSignalReceiver)

    func removeInterfaceSignalReceiver(_ receiver: any InterfaceSignalReceiver)
}

@objc
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol InterfaceSignalReceiver: AnyObject, Sendable {
    func onInterfaceChanged(signal: InterfaceChangeSignal)

    func onStartProviding()

    func onStopProviding()
}
