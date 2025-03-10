//
//  HttpUtil.swift
//  Amplitude-Swift
//
//  Created by Chris Leonavicius on 1/15/25.
//

import Foundation

struct HttpUtil {

    static func makeJsonRequest(url: URL,
                                clientLibrary: String = "amplitude-swift",
                                apiVersion: Int = 2) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(String(describing: apiVersion), forHTTPHeaderField: "X-Client-Version")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Client-Bundle-Id")
        let version = Bundle(for: RemoteConfigClient.self).infoDictionary?["CFBundleVersion"] as? String ?? "<unknown>"
        request.setValue("\(clientLibrary)/\(version)", forHTTPHeaderField: "X-Client-Library")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        return request
    }
}
