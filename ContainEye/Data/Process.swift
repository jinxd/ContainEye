//
//  Process.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/25/25.
//


import Foundation
import NIO
@preconcurrency import Citadel
import Foundation
import Blackbird

struct Process: BlackbirdModel, Identifiable, Hashable, Codable {
    static let primaryKey: [BlackbirdColumnKeyPath] = [\.$id]

    @BlackbirdColumn var id: String = UUID().uuidString
    @BlackbirdColumn var serverId: String
    @BlackbirdColumn var pid: Int
    @BlackbirdColumn var command: String
    @BlackbirdColumn var user: String
    @BlackbirdColumn var cpuUsage: Double
    @BlackbirdColumn var memoryUsage: Double
}

extension Server {
    func fetchProcesses() async {
        // Check if this is a macOS server
        let isMacOS = self.isMacOS ?? false

        let command: String

        if isMacOS {
            // macOS uses BSD-style ps which doesn't support --no-headers or --sort
            let sortCommand: String
            switch processSortOrder ?? .cpuReversed {
            case .pid: sortCommand = "sort -n -k1,1"
            case .pidReversed: sortCommand = "sort -rn -k1,1"
            case .command: sortCommand = "sort -k5"
            case .commandReversed: sortCommand = "sort -r -k5"
            case .user: sortCommand = "sort -k2,2"
            case .userReversed: sortCommand = "sort -r -k2,2"
            case .memory: sortCommand = "sort -n -k4,4"
            case .memoryReversed: sortCommand = "sort -rn -k4,4"
            case .cpu: sortCommand = "sort -n -k3,3"
            case .cpuReversed: sortCommand = "sort -rn -k3,3"
            }

            command = "ps -eo pid,user,%cpu,%mem,command | tail -n +2 | awk '{print $1, $2, $3, $4, substr($0, index($0,$5))}' | \(sortCommand) | head -n 50"
        } else {
            // Linux uses GNU ps with --no-headers and --sort
            let sortFlag: String
            switch processSortOrder ?? .cpuReversed {
            case .pid: sortFlag = "pid"
            case .pidReversed: sortFlag = "-pid"
            case .command: sortFlag = "command"
            case .commandReversed: sortFlag = "-command"
            case .user: sortFlag = "user"
            case .userReversed: sortFlag = "-user"
            case .memory: sortFlag = "%mem"
            case .memoryReversed: sortFlag = "-%mem"
            case .cpu: sortFlag = "%cpu"
            case .cpuReversed: sortFlag = "-%cpu"
            }

            command = "ps -eo pid,user,%cpu,%mem,command --no-headers --sort=\(sortFlag) | awk '{print $1, $2, $3, $4, substr($0, index($0,$5))}' | head -n 50"
        }

        guard let output = try? await execute(command) else { return }

        let processList = output
            .split(separator: "\n")
            .compactMap { line -> Process? in
                let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).map{String($0)}
                guard parts.count == 5,
                      let pid = Int(parts[0]),
                      let cpuUsage = Double(parts[2]),
                      let memoryUsage = Double(parts[3]) else { return nil }

                return Process(
                    serverId: id, pid: pid,
                    command: String(parts[4]),
                    user: String(parts[1]),
                    cpuUsage: cpuUsage,
                    memoryUsage: memoryUsage
                )
            }

        try? await db.transaction({ core in
            try? Process.deleteIsolated(from: db, core: core, matching: .all)
            for process in processList {
                try? process.writeIsolated(to: db, core: core)
            }
        })
    }
}


