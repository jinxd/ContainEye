//
//  Credential.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import Foundation

struct Credential: Codable {
    var key: String
    var label: String
    var host: String
    var port: Int32
    var username: String
    var password: String
}
