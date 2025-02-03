//
//  SharedDatabase.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/31/25.
//

import Foundation
import Blackbird

class SharedDatabase {
    static let db = {
        let path = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.nagel.ContainEye")!.appendingPathComponent("db.sqlite").path
        return try! Blackbird.Database(path: path)
    }()
}
