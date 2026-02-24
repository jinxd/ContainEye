import Foundation

struct CommandSuggestion: Identifiable, Hashable {
    enum Source: String, Hashable {
        case documentTree
        case history
        case snippet
        case live
    }

    let id: String
    let text: String
    let source: Source
    let score: Double

    init(text: String, source: Source, score: Double) {
        self.text = text
        self.source = source
        self.score = score
        self.id = "\(source.rawValue)|\(text)"
    }
}

struct CommandSuggestionContext {
    let input: String
    let credential: Credential
    let currentDirectory: String
    let history: [String]
}

protocol CommandSuggestionProviding: AnyObject {
    func suggest(input: String, context: CommandSuggestionContext) async -> [CommandSuggestion]
}

final class CommandSuggestionEngine: CommandSuggestionProviding {
    typealias SnippetCommandsProvider = (_ credentialKey: String) async -> [String]

    private let index: RemoteDocumentTreeIndex
    private let fetchSnippetCommands: SnippetCommandsProvider
    private let pathCommands: Set<String> = [
        "cd", "ls", "cat", "tail", "head", "less", "more", "nano", "vim", "emacs", "cp", "mv", "rm", "chmod", "chown", "grep", "find"
    ]

    init(
        index: RemoteDocumentTreeIndex,
        fetchSnippetCommands: @escaping SnippetCommandsProvider = {
            credentialKey in
            let snippets = (try? await Snippet.read(from: SharedDatabase.db, matching: .all, orderBy: .descending(\.$lastUse), limit: 220)) ?? []
            return snippets
                .filter { ($0.credentialKey ?? "").isEmpty || $0.credentialKey == credentialKey }
                .map(\.command)
        }
    ) {
        self.index = index
        self.fetchSnippetCommands = fetchSnippetCommands
    }

    func suggest(input: String, context: CommandSuggestionContext) async -> [CommandSuggestion] {
        let trimmedInput = input.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.isEmpty else {
            return []
        }

        let tokens = tokenize(input: input)
        guard let command = tokens.first else {
            return []
        }

        var scored: [CommandSuggestion] = []

        if pathCommands.contains(command) {
            let (directory, prefix, baseCommand, replacementBase) = resolveCompletionContext(input: input, cwd: context.currentDirectory)

            let indexedChildren = await index.suggestChildren(
                credentialKey: context.credential.key,
                directory: directory,
                prefix: prefix,
                limit: 8
            )

            for child in indexedChildren {
                let fullLine = rebuildInput(baseCommand: baseCommand, replacementToken: replacementBase + child)
                scored.append(CommandSuggestion(text: fullLine, source: .documentTree, score: scoreForPrefixMatch(prefix: prefix, candidate: child, sourceBoost: 0.95)))
            }

            if scored.count < 3 {
                let liveChildren = await livePathSuggestions(
                    credential: context.credential,
                    directory: directory,
                    prefix: prefix,
                    limit: 10
                )

                for candidate in liveChildren {
                    let fullLine = rebuildInput(baseCommand: baseCommand, replacementToken: replacementBase + candidate)
                    scored.append(CommandSuggestion(text: fullLine, source: .live, score: scoreForPrefixMatch(prefix: prefix, candidate: candidate, sourceBoost: 0.85)))

                    let path = joinPath(directory: directory, child: candidate)
                    let isDirectory = candidate.hasSuffix("/")
                    await index.upsert(credentialKey: context.credential.key, path: path, isDirectory: isDirectory)
                }
            }
        }

        let historyMatches = await historySuggestions(
            for: context,
            command: command,
            trimmedInput: trimmedInput
        )

        scored.append(contentsOf: historyMatches)

        let snippetMatches = await fetchSnippetCommands(context.credential.key)
            .filter { $0.hasPrefix(trimmedInput) }
            .prefix(6)
            .map { CommandSuggestion(text: $0, source: .snippet, score: scoreForPrefixMatch(prefix: trimmedInput, candidate: $0, sourceBoost: 0.75)) }

        scored.append(contentsOf: snippetMatches)

        // Highest score first, dedupe by text.
        var deduped: [String: CommandSuggestion] = [:]
        for entry in scored.sorted(by: { $0.score > $1.score }) {
            if deduped[entry.text] == nil {
                deduped[entry.text] = entry
            }
        }

        return Array(deduped.values)
            .sorted(by: { $0.score > $1.score })
            .prefix(3)
            .map { $0 }
    }

    private func tokenize(input: String) -> [String] {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
    }

    private func resolveCompletionContext(input: String, cwd: String) -> (directory: String, prefix: String, baseCommand: String, replacementBase: String) {
        let hasTrailingSpace = input.last?.isWhitespace == true
        var parts = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        guard !parts.isEmpty else {
            return (cwd, "", "", "")
        }

        let command = parts.removeFirst()
        let target = hasTrailingSpace ? "" : (parts.last ?? "")
        let commandPrefix = parts.dropLast().joined(separator: " ")
        let baseCommand = ([command] + (commandPrefix.isEmpty ? [] : [commandPrefix])).joined(separator: " ")

        let resolved = resolvePathToken(token: target, cwd: cwd)
        return (resolved.directory, resolved.prefix, baseCommand, resolved.replacementBase)
    }

    private func resolvePathToken(token: String, cwd: String) -> (directory: String, prefix: String, replacementBase: String) {
        if token.isEmpty {
            return (cwd, "", "")
        }

        if token.hasPrefix("/") {
            if token.hasSuffix("/") {
                return (token, "", token)
            }

            let comps = token.split(separator: "/").map(String.init)
            if comps.count <= 1 {
                return ("/", token.replacingOccurrences(of: "/", with: ""), "/")
            }

            let prefix = comps.last ?? ""
            let dir = "/" + comps.dropLast().joined(separator: "/")
            let replacementBase = dir.hasSuffix("/") ? dir : dir + "/"
            return (dir, prefix, replacementBase)
        }

        if token.hasSuffix("/") {
            return (joinPath(directory: cwd, child: token), "", token)
        }

        if token.contains("/") {
            let comps = token.split(separator: "/").map(String.init)
            let prefix = comps.last ?? ""
            let dirToken = comps.dropLast().joined(separator: "/")
            let replacementBase = dirToken.isEmpty ? "" : dirToken + "/"
            return (joinPath(directory: cwd, child: dirToken), prefix, replacementBase)
        }

        return (cwd, token, "")
    }

    private func rebuildInput(baseCommand: String, replacementToken: String) -> String {
        if baseCommand.isEmpty {
            return replacementToken
        }
        return "\(baseCommand) \(replacementToken)"
    }

    private func scoreForPrefixMatch(prefix: String, candidate: String, sourceBoost: Double) -> Double {
        let normalizedCandidate = candidate.lowercased()
        let normalizedPrefix = prefix.lowercased()

        let prefixScore: Double
        if normalizedPrefix.isEmpty {
            prefixScore = 0.5
        } else if normalizedCandidate == normalizedPrefix {
            prefixScore = 1.0
        } else if normalizedCandidate.hasPrefix(normalizedPrefix) {
            prefixScore = 0.9
        } else {
            prefixScore = 0.2
        }

        let lengthPenalty = min(Double(candidate.count) / 120.0, 0.35)
        return sourceBoost + prefixScore - lengthPenalty
    }

    private func historySuggestions(
        for context: CommandSuggestionContext,
        command: String,
        trimmedInput: String
    ) async -> [CommandSuggestion] {
        _ = command
        let candidates = context.history
            .filter { $0.hasPrefix(trimmedInput) }
            .prefix(6)

        return candidates.map {
            CommandSuggestion(
                text: $0,
                source: .history,
                score: scoreForPrefixMatch(prefix: trimmedInput, candidate: $0, sourceBoost: 0.8)
            )
        }
    }

    private func livePathSuggestions(credential: Credential, directory: String, prefix: String, limit: Int) async -> [String] {
        let escapedDirectory = shellQuote(directory)
        let command = "cd \(escapedDirectory) 2>/dev/null && ls -1Ap 2>/dev/null | head -n \(max(limit * 3, 24))"

        let output = (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""

        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .filter { prefix.isEmpty ? true : $0.hasPrefix(prefix) }
            .prefix(limit)
            .map { $0 }
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func joinPath(directory: String, child: String) -> String {
        let cleanedChild = child.hasSuffix("/") ? String(child.dropLast()) : child

        if cleanedChild.hasPrefix("/") {
            return cleanedChild
        }

        if directory.hasSuffix("/") {
            return directory + cleanedChild
        }

        return directory + "/" + cleanedChild
    }
}
