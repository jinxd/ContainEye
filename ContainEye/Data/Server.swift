//
//  Server.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import Foundation
import NIO
@preconcurrency import Citadel
import KeychainAccess
import Foundation
import Blackbird

struct Server: BlackbirdModel {
    
    static let primaryKey: [BlackbirdColumnKeyPath] = [\.$id]

    @BlackbirdColumn var id: String
    @BlackbirdColumn var credentialKey: String
    @BlackbirdColumn var cpuUsage: Double?
    @BlackbirdColumn var memoryUsage: Double?
    @BlackbirdColumn var diskUsage: Double?
    @BlackbirdColumn var networkUpstream: Double?
    @BlackbirdColumn var networkDownstream: Double?
    @BlackbirdColumn var swapUsage: Double?
    @BlackbirdColumn var systemLoad: Double?
    @BlackbirdColumn var ioWait: Double?
    @BlackbirdColumn var stealTime: Double?
    @BlackbirdColumn var uptime: Date?
    @BlackbirdColumn var lastUpdate: Date?
    @BlackbirdColumn var isConnected: Bool

    var credential: Credential? {
        keychain().getCredential(for: credentialKey)
    }
    var containers: [Container] {
        get async throws {
            try await Container.read(from: SharedDatabase.db, matching: \.$serverId == id)
        }
    }

    init(credentialKey: String) {
        self.credentialKey = credentialKey
        self.id = credentialKey
        self.isConnected = false
    }
}

extension Server {
    var server: Server? {
        get async throws {
            try await Server.read(from: SharedDatabase.db, id: id)
        }
    }
    var db : Blackbird.Database {
        SharedDatabase.db
    }

    func connect() async throws {
        let _ = try await execute("echo hello")
        var server = self
        server.isConnected = true
        try await server.write(to: db)

        guard let credential else { return }

        await SSHClientActor.shared.onDisconnect(of: credential) {
            Task{
                var server = try await self.server
                server?.isConnected = false
                try? await server?.write(to: db)
            }
        }
    }

    func disconnect() async throws {
        guard let credential = try await server?.credential else { return }
        try await SSHClientActor.shared.disconnect(credential)
    }

    func fetchServerStats() async {
        async let cpuUsage = fetchMetric(command: "sar -u 1 3 | grep 'Average' | awk '{print (100 - $8) / 100}'")
        async let memoryUsage = fetchMetric(command: "free | grep Mem | awk '{print $3/$2}'")
        async let diskUsage = fetchMetric(command: "df / | grep / | awk '{ print $5 / 100 }'")
        async let networkUpstream = fetchMetric(command: "sar -n DEV 1 2 | grep Average | grep eth0 | awk '{print $5 * 1024}'")
        async let networkDownstream = fetchMetric(command: "sar -n DEV 1 2 | grep Average | grep eth0 | awk '{print $6 * 1024}'")
        async let swapUsage = fetchMetric(command: "free | grep Swap | awk '{print $3/$2}'")
        async let ioWait = fetchMetric(command: "sar -u 1 3 | grep 'Average' | awk '{print $5 / 100}'")
        async let stealTime = fetchMetric(command: "sar -u 1 3 | grep 'Average' | awk '{print $6 / 100}'")
        async let systemLoad = fetchMetric(command: "uptime | awk '{print $(NF-2) / 100}'")

        var newUptime = Date?.none
        let uptimeCommand = "date +%s -d \"$(uptime -s)\""
        let uptimeOutput = try? await execute(uptimeCommand)
        if let uptimeOutput,
           let timestamp = Double(uptimeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) {
            newUptime = Date(timeIntervalSince1970: timestamp)
        }
        //here await all the async lets first, before proceeding and before doing try? await server
        let (cpu, memory, disk, networkUpstreamResult, networkDownstreamResult, swap, io, steal, load) = await (cpuUsage, memoryUsage, diskUsage, networkUpstream, networkDownstream, swapUsage, ioWait, stealTime, systemLoad)

        if var server = try? await server {
            server.cpuUsage = cpu ?? server.cpuUsage
            server.memoryUsage = memory ?? server.memoryUsage
            server.diskUsage = disk ?? server.diskUsage
            server.networkUpstream = networkUpstreamResult ?? server.networkUpstream
            server.networkDownstream = networkDownstreamResult ?? server.networkDownstream
            server.swapUsage = swap ?? server.swapUsage
            server.ioWait = io ?? server.ioWait
            server.stealTime = steal ?? server.stealTime
            server.systemLoad = load ?? server.systemLoad
            server.lastUpdate = .now
            if let newUptime{
                server.uptime = newUptime
            }
            try? await server.write(to: db)
        }
    }

    func fetchDockerStats() async {
        do {
            let output = try await execute("""
    docker stats --no-stream --format "{{.ID}} {{.Name}} {{.CPUPerc}} {{.MemUsage}}" | while read id name cpu mem; do
        status=$(docker ps --filter "id=$id" --format "{{.Status}}")
        
        # Fetch total memory for the container using docker inspect
        totalMem=$(docker inspect --format '{{.HostConfig.Memory}}' $id)

        # Check if totalMem is empty or zero, fallback to a default value
        if [ -z "$totalMem" ] || [ "$totalMem" -eq 0 ]; then
            totalMem="N/A"
        fi
        
        # Output the stats with both used memory and total memory
        echo "$id $name $cpu $mem $status"
    done
""")
            let stopped = try await execute("""
    docker ps -a --filter "status=exited" --format "{{.ID}} {{.Names}} {{.Status}}" | awk '{id=$1; name=$2; status=$3; cpu="0"; mem="0 / 0"; totalMem="N/A"; print id, name, cpu, mem, status}'
""")
            let newContainers = try parseDockerStats(from: "\(output)\n\(stopped)")


            let containers = try await self.containers
            for newContainer in newContainers {
                if var existingContainer = try await Container.read(from: db, id: newContainer.id) {
                    existingContainer.name = newContainer.name
                    existingContainer.cpuUsage = newContainer.cpuUsage
                    existingContainer.memoryUsage = newContainer.memoryUsage
                    try await existingContainer.write(to: db)
                } else {
                    let container = Container(id: newContainer.id, name: newContainer.name, status: newContainer.status, cpuUsage: newContainer.cpuUsage, memoryUsage: newContainer.memoryUsage, serverId: id)
                    try await container.write(to: db)
                }
            }
            for container in containers.filter(
                {container in
                    !newContainers.contains(where: { $0.id == container.id })
                }) {
                try await container.delete(from: db)
            }
            for container in containers.filter({ $0.fetchDetailedUpdates }) {
                try await container.fetchDetails()
            }
        } catch {
        }
    }

    private func fetchMetric(command: String) async -> Double? {
        do {
            let output = try await execute(command)
            return try parseSingleValue(from: output, command: command)
        } catch {
            return nil
        }
    }

    private func parseSingleValue(from output: String, command: String = "") throws(ServerError) -> Double {
        let lines = output.split(whereSeparator: \.isNewline)
        for line in lines {
            let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            if let value = Double(cleanedLine) {
                return value
            }
        }
        throw ServerError.invalidStatsOutput("\(command) failed: \(output)")
    }

    private func parseDockerStats(from output: String) throws(ServerError) -> [(id: String, name: String, status: String, cpuUsage: Double, memoryUsage: Double)] {
        do {
            let lines = output.split(whereSeparator: \.isNewline)
            return try lines.map { line in
                var parts = line.split(separator: " ", omittingEmptySubsequences: true)

                // Ensure there are enough parts to parse
                guard parts.count >= 6 else {
                    throw ServerError.invalidStatsOutput("Malformed or incomplete container info: \(line)")
                }

                let id = String(parts[0])
                let name = String(parts[1])
                let cpuUsageString = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
                guard let cpuUsage = Double(cpuUsageString) else {
                    throw ServerError.invalidStatsOutput("Invalid CPU usage in line: \(line)")
                }

                // Memory usage parsing
                let memoryUsage = String(parts[3])

                let totalMemString = String(parts[5])


                let usedMemoryBytes = try parseMemoryUsage(memoryUsage)
                let totalMemoryBytes = try parseMemoryUsage(totalMemString)

                let memoryUsagePercentage = totalMemoryBytes.isZero ? 0 : (usedMemoryBytes / totalMemoryBytes)

                print(parts)
                parts.removeFirst(6)

                let status = String(parts.joined(separator: " "))

                return (id: id, name: name, status: status, cpuUsage: cpuUsage / 100, memoryUsage: memoryUsagePercentage)
            }
        } catch {
            throw error as! ServerError
        }
    }


    private func parseUsage(from usage: Substring) throws(ServerError) -> Double {
        if let value = Double(usage.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")) {
            return value
        }
        throw ServerError.invalidStatsOutput(String(usage))
    }


    private func parseMemoryUsage(_ memoryString: String) throws(ServerError) -> Double {
        let units = ["MiB": 1_048_576.0, "KiB": 1_024.0, "GiB": 1_073_741_824.0, "B": 1.0]

        // Loop over the units to check which one is present
        if memoryString == "0" || (memoryString.localizedCaseInsensitiveContains("N/A")) {
            return 0
        }
        for (unit, multiplier) in units {
            if memoryString.contains(unit) {
                let numericValue = memoryString.replacingOccurrences(of: unit, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(numericValue) {
                    return value * multiplier
                }
            }
        }
        // Handle the case where no valid unit is found
        throw .invalidStatsOutput("Couldn't parse memory usage from: \(memoryString)")
    }

    func execute(_ command: String) async throws -> String {
        if let credential {
            return try await SSHClientActor.shared.execute(command, on: credential)
        } else {return ""}
    }
}
