//
//  URL+constants.swift
//  ContainEye
//
//  Created by Hannes Nagel on 4/5/25.
//

import Foundation

extension URL {
    static var servers: URL {
        URL(string: "https://hannesnagel.com/containeye/servers-management")!
    }
    static var automatedTests: URL {
        URL(string: "https://hannesnagel.com/containeye/automated-tests")!
    }
}
