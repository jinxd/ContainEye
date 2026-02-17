import Foundation
import Testing
@testable import ContainEye

struct CommandSuggestionEngineTests {
    private func makeCredential() -> Credential {
        Credential(
            key: "cred-test",
            label: "Test",
            host: "127.0.0.1",
            port: 22,
            username: "user",
            password: "pass"
        )
    }

    @Test
    func prefersHistoryOverSnippetForSamePrefix() async {
        let index = RemoteDocumentTreeIndex()
        let engine = CommandSuggestionEngine(
            index: index,
            fetchSnippetCommands: { ["git stash", "git switch main"] }
        )

        let context = CommandSuggestionContext(
            input: "git st",
            credential: makeCredential(),
            currentDirectory: "/tmp",
            history: ["git status"]
        )

        let suggestions = await engine.suggest(input: "git st", context: context)

        #expect(!suggestions.isEmpty)
        #expect(suggestions.first?.text == "git status")
        #expect(suggestions.first?.source == .history)
    }

    @Test
    func usesSnippetWhenHistoryDoesNotMatch() async {
        let index = RemoteDocumentTreeIndex()
        let engine = CommandSuggestionEngine(
            index: index,
            fetchSnippetCommands: { ["docker compose up -d"] }
        )

        let context = CommandSuggestionContext(
            input: "docker co",
            credential: makeCredential(),
            currentDirectory: "/tmp",
            history: []
        )

        let suggestions = await engine.suggest(input: "docker co", context: context)

        #expect(suggestions.contains(where: { $0.source == .snippet && $0.text == "docker compose up -d" }))
    }

    @Test
    func pathSuggestionsPreserveRelativePrefixBase() async {
        let index = RemoteDocumentTreeIndex()
        await index.upsert(credentialKey: "cred-test", path: "/home/user/src/fizz", isDirectory: true)
        await index.upsert(credentialKey: "cred-test", path: "/home/user/src/folder", isDirectory: true)
        await index.upsert(credentialKey: "cred-test", path: "/home/user/src/foo", isDirectory: true)

        let engine = CommandSuggestionEngine(
            index: index,
            fetchSnippetCommands: { [] }
        )

        let context = CommandSuggestionContext(
            input: "cd src/f",
            credential: makeCredential(),
            currentDirectory: "/home/user",
            history: []
        )

        let suggestions = await engine.suggest(input: "cd src/f", context: context)

        #expect(!suggestions.isEmpty)
        #expect(suggestions.allSatisfy { $0.text.hasPrefix("cd src/") })
    }
}
