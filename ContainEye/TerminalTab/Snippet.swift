//
//  Snippet.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/17/25.
//

import Foundation
import Blackbird

struct Snippet: BlackbirdModel{
    @BlackbirdColumn var id: String = UUID().uuidString
    @BlackbirdColumn var command: String
    @BlackbirdColumn var comment: String
    @BlackbirdColumn var lastUse: Date

    static let primaryKey: [BlackbirdColumnKeyPath] = [ \.$id ]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [ \.$comment, \.$lastUse, \.$command ]
    ]
}
