//
//  SharedDatabase.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/31/25.
//

import Foundation
import Blackbird

enum SharedDatabase {
    private static let appGroupIdentifier = "group.com.nagel.ContainEye"

    static let db: Blackbird.Database = {
        let fileManager = FileManager.default
        let candidateDirectories: [URL] = [
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier),
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ContainEye", isDirectory: true),
            fileManager.temporaryDirectory.appendingPathComponent("ContainEye", isDirectory: true)
        ].compactMap { $0 }

        for directory in candidateDirectories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let path = directory.appendingPathComponent("db.sqlite", isDirectory: false).path
                return try Blackbird.Database(path: path)
            } catch {
                continue
            }
        }

        fatalError("Unable to initialize SharedDatabase at any writable location")
    }()
}
