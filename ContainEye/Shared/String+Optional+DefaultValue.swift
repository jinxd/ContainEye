//
//  String+Optional+DefaultValue.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/10/25.
//

import Foundation


extension Optional<String> {
    var nonOptional: String {
        get {
            self ?? ""
        } set {
            self = newValue
        }
    }
}
