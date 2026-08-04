//
//  Storage.swift
//  AmplitudeCore
//

import Foundation

enum Storage {
    static var rootDirectory: FileManager.SearchPathDirectory {
#if os(tvOS)
        .cachesDirectory
#else
        .applicationSupportDirectory
#endif
    }

    static func rootDirectoryURL(fileManager: FileManager = .default,
                                 createIfNeeded: Bool) throws -> URL {
        try fileManager.url(for: rootDirectory,
                            in: .userDomainMask,
                            appropriateFor: nil,
                            create: createIfNeeded)
    }
}
