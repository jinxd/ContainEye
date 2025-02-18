//
//  DataStreamerError.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/17/25.
//

import Foundation

enum DataStreamerError: Error , Hashable {
    case failedToConnect(to: String, error: String)
}
