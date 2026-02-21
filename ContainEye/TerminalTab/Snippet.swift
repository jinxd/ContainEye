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
    @BlackbirdColumn var credentialKey: String? = nil

    static let primaryKey: [BlackbirdColumnKeyPath] = [ \.$id ]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [ \.$credentialKey, \.$lastUse ],
        [ \.$comment, \.$lastUse, \.$command ]
    ]

    // Legacy defaults used in earlier app versions; kept only for cleanup.
    private static let legacyDefaultSnippets: [(command: String, comment: String)] = [
        ("docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'", "List running containers with status and ports"),
        ("docker logs --tail 100 <container>", "Show the latest 100 log lines for a container"),
        ("docker exec -it <container> sh", "Open a shell in a running container"),
        ("docker stats --no-stream", "Show a single snapshot of container resource usage"),
        ("docker compose ps", "Show services and container states for this compose project"),
        ("docker compose logs -f --tail 50", "Follow compose service logs"),
        ("df -h", "Show disk usage in human-readable format"),
        ("free -h", "Show memory usage in human-readable format")
    ]

    static func ensureDefaults(in db: Blackbird.Database) async {
        _ = db
    }

    static func addDefaults(in db: Blackbird.Database) async {
        _ = db
    }

    static func purgeLegacyDefaults(in db: Blackbird.Database) async {
        let cleanupKey = "terminal.snippets.legacy-defaults-removed.v1"
        if UserDefaults.standard.bool(forKey: cleanupKey) {
            return
        }

        let legacyCommands = Set(legacyDefaultSnippets.map(\.command))
        do {
            let rows = try await Snippet.read(from: db, matching: .all, limit: 1200)
            for row in rows where legacyCommands.contains(row.command) && (row.credentialKey ?? "").isEmpty {
                try await row.delete(from: db)
            }
            UserDefaults.standard.set(true, forKey: cleanupKey)
        } catch {
            print("Failed to purge legacy default snippets: \(error)")
        }
    }

    static func saveCommand(
        command: String,
        comment: String,
        credentialKey: String?,
        in db: Blackbird.Database
    ) async throws {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else { return }
        let all = try await Snippet.read(from: db, matching: .all, orderBy: .descending(\.$lastUse), limit: 500)
        if var existing = all.first(where: {
            $0.command == normalizedCommand &&
            (($0.credentialKey ?? "") == (credentialKey ?? ""))
        }) {
            existing.lastUse = .now
            if !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.comment = comment
            }
            try await existing.write(to: db)
            return
        }

        let snippet = Snippet(
            command: normalizedCommand,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            lastUse: .now,
            credentialKey: credentialKey
        )
        try await snippet.write(to: db)
    }

    static func deleteForServer(credentialKey: String, in db: Blackbird.Database) async {
        guard !credentialKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let scoped = try await Snippet.read(from: db, matching: \.$credentialKey == credentialKey, limit: 1000)
            for snippet in scoped {
                try await snippet.delete(from: db)
            }
        } catch {
            print("Failed to delete snippets for server \(credentialKey): \(error)")
        }
    }
}
