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

    static let defaultSnippets: [(command: String, comment: String)] = [
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
        let defaultsKey = "terminal.snippets.defaults.seeded.v1"
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return
        }

        let existing = (try? await Snippet.read(from: db, matching: .all, limit: 1)) ?? []
        guard existing.isEmpty else {
            UserDefaults.standard.set(true, forKey: defaultsKey)
            return
        }

        for template in defaultSnippets {
            let snippet = Snippet(
                command: template.command,
                comment: template.comment,
                lastUse: .distantPast
            )
            try? await snippet.write(to: db)
        }
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    static func addDefaults(in db: Blackbird.Database) async {
        let existing = (try? await Snippet.read(from: db, matching: .all, limit: 400)) ?? []
        let existingCommands = Set(existing.map(\.command))

        for template in defaultSnippets where !existingCommands.contains(template.command) {
            let snippet = Snippet(
                command: template.command,
                comment: template.comment,
                lastUse: .distantPast
            )
            try? await snippet.write(to: db)
        }
    }
}
