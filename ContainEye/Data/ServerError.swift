//
//  ServerError.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/18/25.
//

import Foundation


enum ServerError: Error, Hashable {
    case connectionFailed, invalidStatsOutput(_ output: String), notConnected, invalidServerResponse, cpuCommandFailed, otherError(_ error: NSError), noPasswordInKeychain
}
