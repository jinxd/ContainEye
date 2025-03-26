//
//  Container.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import SwiftUI
import Blackbird

struct Container: BlackbirdModel, Identifiable, Equatable, Hashable {
    @BlackbirdColumn var id: String
    @BlackbirdColumn var name: String
    @BlackbirdColumn var status: String
    @BlackbirdColumn var cpuUsage: Double
    @BlackbirdColumn var memoryUsage: Double
    @BlackbirdColumn var serverId: String
    @BlackbirdColumn var cmd = ""
    @BlackbirdColumn var logs = ""
    @BlackbirdColumn var fetchDetailedUpdates = false
    @BlackbirdColumn var lastUpdate = Date()

    var db : Blackbird.Database { SharedDatabase.db }

    static let primaryKey: [BlackbirdColumnKeyPath] = [ \.$id ]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [ \.$serverId ]
    ]

    func server(in db: Blackbird.Database = SharedDatabase.db) async -> Server? {
        try? await Server.read(from: db, id: serverId)
    }
    var server: Server? {
        get async {
            try? await Server.read(from: db, id: serverId)
        }
    }

    init(id: String, name: String, status: String, cpuUsage: Double, memoryUsage: Double, serverId: String) {
        self.id = id
        self.name = name
        self.status = status
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.serverId = serverId
    }
}

extension Container {
    // Start the container
    func start() async throws {
        guard let server = await server else {return}
        let db = SharedDatabase.db
        
        let command = "docker start \(id)"
        do {
            let _ = try await server.execute(command)
            let status = "Up - loading status..."

            if var container = try await Container.read(from: db, id: id){
                container.status = status
                try await container.write(to: db)
                try await fetchDetails()
            }
        } catch {
            throw error
        }
    }

    // Stop the container
    func stop() async throws {
        guard let server = await server else {return}

        let db = SharedDatabase.db
        let command = "docker stop \(id)"
        do {
            let _ = try await server.execute(command)
            let status = "Exited - loading status..."

            if var container = try await Container.read(from: db, id: id){
                container.status = status
                try await container.write(to: db)
                try await fetchDetails()
            }
        } catch {
            throw error
        }
    }

    func fetchDetails() async throws(ServerError) {
        guard let server = await server else {return}
        // Command to fetch the container's command
        let commandCmd = "docker inspect --format='{{.Config.Cmd}}' \(id)"
        // Command to fetch the container's status
        let commandStatus = "docker ps -a --filter 'id=\(id)' --format '{{.Status}}'"
        // Command to fetch the container's logs
        let commandLogs = "docker logs --tail 50 \(id)"

        do {
            // Fetch the container's command
            let cmdOutput = try await server.execute(commandCmd)
            let cleanedCommand = cmdOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")

            // Assign default command if cleanedCommand is empty
            let cmd = cleanedCommand.isEmpty ? "unknown" : cleanedCommand

            // Fetch the container's status
            let cleanedStatus = try await server.execute(commandStatus).trimmingCharacters(in: .whitespacesAndNewlines)

            // Fetch the container's logs
            let logs = try await server.execute(commandLogs).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !Task.isCancelled else { return }

            var container = try await Container.read(from: SharedDatabase.db, id: id)
            container?.cmd = cmd
            container?.status = cleanedStatus
            container?.logs = logs

            try await container?.write(to: SharedDatabase.db)
        } catch {
            throw ServerError.invalidStatsOutput(
                "Failed to fetch details for container \(name): \(error.generateDescription())"
            )
        }
    }
}
