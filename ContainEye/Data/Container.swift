//
//  Container.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import SwiftUI

@MainActor
@Observable
class Container: @preconcurrency Identifiable, @preconcurrency Equatable, @preconcurrency Hashable {
    var id: String
    var name: String
    var status: String
    var cpuUsage: Double
    var memoryUsage: Double
    var server: Server
    var cmd = ""
    var fetchDetailedUpdates = false
    var lastUpdate = Date()

    // Start the container
    func start() async throws {
        let command = "docker start \(id)"
        do {
            let _ = try await server.execute(command)
            status = "Up - loading status..."
            try await fetchDetails()
        } catch {
            throw error
        }
    }

    // Stop the container
    func stop() async throws {
        let command = "docker stop \(id)"
        do {
            let _ = try await server.execute(command)
            status = "Exited - loading status..."
            try await fetchDetails()
        } catch {
            throw error
        }
    }

    func fetchDetails() async throws(Server.ServerError) {
        // Command to fetch the container's command
        let commandCmd = "docker inspect --format='{{.Config.Cmd}}' \(id)"
        // Command to fetch the container's status
        let commandStatus = "docker ps -a --filter 'id=\(id)' --format '{{.Status}}'"

        do {
            // Fetch the container's command
            let cmdOutput = try await server.execute(commandCmd)
            let cleanedCommand = cmdOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")

            // Assign default command if cleanedCommand is empty
            cmd = cleanedCommand.isEmpty ? "docker compose" : cleanedCommand

            // Fetch the container's status
            let statusOutput = try await server.execute(commandStatus)
            let cleanedStatus = statusOutput.trimmingCharacters(in: .whitespacesAndNewlines)

            // Assign the status directly
            status = cleanedStatus
        } catch {
            throw Server.ServerError.invalidStatsOutput(
                "Failed to fetch details for container \(id): \(error.generateDescription())"
            )
        }
    }

    init(id: String, name: String, status: String, cpuUsage: Double, memoryUsage: Double, server: Server) {
        self.id = id
        self.name = name
        self.status = status
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.server = server
    }

    static func == (lhs: Container, rhs: Container) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.status == rhs.status &&
        lhs.cpuUsage == rhs.cpuUsage && lhs.memoryUsage == rhs.memoryUsage &&
        lhs.server == rhs.server && lhs.cmd == rhs.cmd && lhs.fetchDetailedUpdates == rhs.fetchDetailedUpdates
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(status)
        hasher.combine(cpuUsage)
        hasher.combine(memoryUsage)
        hasher.combine(server)
        hasher.combine(cmd)
        hasher.combine(fetchDetailedUpdates)
    }
}
