//
//  DockerCompose.swift
//  ContainEye
//
//  Created by Claude on 6/22/25.
//

import Foundation
import Blackbird

struct DockerCompose: BlackbirdModel, Identifiable, Hashable, Codable {
    static let primaryKey: [BlackbirdColumnKeyPath] = [\.$id]
    
    @BlackbirdColumn var id: String = UUID().uuidString
    @BlackbirdColumn var serverId: String
    @BlackbirdColumn var filePath: String
    @BlackbirdColumn var projectName: String
    @BlackbirdColumn var services: String // JSON string of service names
    @BlackbirdColumn var lastModified: Date?
    @BlackbirdColumn var isRunning: Bool = false
    
    var serviceList: [String] {
        (try? JSONDecoder().decode([String].self, from: services.data(using: .utf8) ?? Data())) ?? []
    }
    
    init(serverId: String, filePath: String, projectName: String, services: [String], lastModified: Date? = nil, isRunning: Bool = false) {
        self.serverId = serverId
        self.filePath = filePath
        self.projectName = projectName
        self.services = (try? String(data: JSONEncoder().encode(services), encoding: .utf8)) ?? "[]"
        self.lastModified = lastModified
        self.isRunning = isRunning
    }
}

extension Server {
    func fetchDockerComposeFiles() async {
        // Find all docker-compose files
        let findCommand = """
        find /home /opt /var /root -name "docker-compose*.yml" -o -name "docker-compose*.yaml" -o -name "compose*.yml" -o -name "compose*.yaml" 2>/dev/null | head -20
        """
        
        guard let output = try? await execute(findCommand) else { return }
        let filePaths = output.split(separator: "\n").map(String.init)
        
        var composeFiles: [DockerCompose] = []
        
        for filePath in filePaths {
            // Extract project name from directory or file
            let projectName = extractProjectName(from: filePath)
            
            // Get file modification time
            let statCommand = "stat -c %Y '\(filePath)' 2>/dev/null || echo 0"
            let modTimeString = try? await execute(statCommand)
            let modTime = modTimeString.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .map { Date(timeIntervalSince1970: $0) }
            
            // Extract service names from compose file
            let services = await extractServices(from: filePath)
            
            // Check if project is running
            let isRunning = await checkIfProjectRunning(projectName: projectName, filePath: filePath)
            
            let composeFile = DockerCompose(
                serverId: id,
                filePath: filePath,
                projectName: projectName,
                services: services,
                lastModified: modTime,
                isRunning: isRunning
            )
            composeFiles.append(composeFile)
        }
        
        // Update database - only update/add, don't delete unless confirmed
        let filesToSave = composeFiles
        let currentPaths = Set(composeFiles.map { $0.filePath })
        
        // Get existing compose files for this server (outside transaction)
        let existingFiles = try? await DockerCompose.read(from: db, matching: \.$serverId == id)
        
        // Check which files need to be removed (outside transaction)
        var filesToDelete: [DockerCompose] = []
        if let existing = existingFiles {
            for existingFile in existing {
                if !currentPaths.contains(existingFile.filePath) {
                    // Double-check if file still exists on server
                    let checkCommand = "test -f '\(existingFile.filePath)' && echo 'exists' || echo 'missing'"
                    if let checkOutput = try? await execute(checkCommand) {
                        if checkOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "missing" {
                            filesToDelete.append(existingFile)
                            print("Will delete non-existent compose file: \(existingFile.filePath)")
                        } else {
                            print("Compose file \(existingFile.filePath) still exists on server, keeping in cache")
                        }
                    } else {
                        print("Could not verify compose file \(existingFile.filePath) existence, keeping in cache")
                    }
                }
            }
        }
        
        // Prepare updates (outside transaction)
        var filesToUpdate: [(existing: DockerCompose, new: DockerCompose)] = []
        var filesToAdd: [DockerCompose] = []
        
        for composeFile in filesToSave {
            if let existing = existingFiles?.first(where: { $0.filePath == composeFile.filePath }) {
                filesToUpdate.append((existing, composeFile))
            } else {
                filesToAdd.append(composeFile)
            }
        }
        
        // Now perform all database operations in transaction
        let deleteList = filesToDelete
        let updateList = filesToUpdate
        let addList = filesToAdd
        
        try? await db.transaction { core in
            // Delete verified non-existent files
            for fileToDelete in deleteList {
                try? fileToDelete.deleteIsolated(from: db, core: core)
            }
            
            // Update existing files
            for (existing, new) in updateList {
                var updated = existing
                updated.projectName = new.projectName
                updated.services = new.services
                updated.lastModified = new.lastModified
                updated.isRunning = new.isRunning
                try? updated.writeIsolated(to: db, core: core)
            }
            
            // Add new files
            for newFile in addList {
                try? newFile.writeIsolated(to: db, core: core)
            }
        }
    }
    
    private func extractProjectName(from filePath: String) -> String {
        let pathComponents = filePath.split(separator: "/")
        if pathComponents.count > 1 {
            return String(pathComponents[pathComponents.count - 2]) // Parent directory name
        }
        return "unknown"
    }
    
    private func extractServices(from filePath: String) async -> [String] {
        let command = """
        grep -E '^  [a-zA-Z0-9_-]+:' '\(filePath)' 2>/dev/null | sed 's/^  //' | sed 's/://' | head -10
        """
        
        guard let output = try? await execute(command) else { return [] }
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func checkIfProjectRunning(projectName: String, filePath: String) async -> Bool {
        // Check if any containers are running for this project
        let directoryPath = (filePath as NSString).deletingLastPathComponent
        let command = "cd '\(directoryPath)' && docker compose ps --services --filter status=running 2>/dev/null | wc -l"
        
        guard let output = try? await execute(command),
              let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        
        return count > 0
    }
    
    func startDockerCompose(at filePath: String) async throws {
        let directoryPath = (filePath as NSString).deletingLastPathComponent
        let command = "cd '\(directoryPath)' && docker compose up -d"
        _ = try await execute(command)
        await fetchDockerComposeFiles()
    }
    
    func stopDockerCompose(at filePath: String) async throws {
        let directoryPath = (filePath as NSString).deletingLastPathComponent
        let command = "cd '\(directoryPath)' && docker compose down"
        _ = try await execute(command)
        await fetchDockerComposeFiles()
    }
    
    func restartDockerCompose(at filePath: String) async throws {
        let directoryPath = (filePath as NSString).deletingLastPathComponent
        let command = "cd '\(directoryPath)' && docker compose restart"
        _ = try await execute(command)
        await fetchDockerComposeFiles()
    }
    
    func pullDockerComposeImages(at filePath: String) async throws {
        let directoryPath = (filePath as NSString).deletingLastPathComponent
        let command = "cd '\(directoryPath)' && docker compose pull"
        _ = try await execute(command)
        await fetchDockerComposeFiles()
    }
}