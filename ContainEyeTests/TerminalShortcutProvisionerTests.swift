import Foundation
import Blackbird
import Testing
@testable import ContainEye

struct TerminalShortcutProvisionerTests {
    private func makeDatabase() throws -> Blackbird.Database {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContainEyeTests.Shortcuts.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Blackbird.Database(path: directory.appendingPathComponent("db.sqlite").path)
    }

    private func makeCredential(key: String, label: String) -> Credential {
        Credential(
            key: key,
            label: label,
            host: "127.0.0.1",
            port: 22,
            username: "root",
            password: "secret"
        )
    }

    private func shortcuts(for credentialKey: String, in db: Blackbird.Database) async throws -> [TerminalLaunchShortcut] {
        try await TerminalLaunchShortcut.read(from: db, matching: \.$credentialKey == credentialKey)
    }

    private func writeShortcut(credentialKey: String, title: String, in db: Blackbird.Database) async throws {
        try await TerminalLaunchShortcut(
            credentialKey: credentialKey,
            title: title,
            startupScript: "",
            colorHex: "#3B82F6",
            themeSelectionKey: nil,
            lastUse: .distantPast
        ).write(to: db)
    }

    @Test
    func createsExactlyOneShortcutPerCredential() async throws {
        let db = try makeDatabase()
        let credential = makeCredential(key: "server-one", label: "Server One")

        await TerminalShortcutProvisioner.shared.ensureShortcuts(for: [credential], in: db)

        let rows = try await shortcuts(for: "server-one", in: db)
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Server One")
        #expect(rows.first?.startupScript.isEmpty == true)
    }

    @Test
    func concurrentProvisioningStaysIdempotent() async throws {
        let db = try makeDatabase()
        let credential = makeCredential(key: "server-one", label: "Server One")

        async let first: Void = TerminalShortcutProvisioner.shared.ensureShortcuts(for: [credential], in: db)
        async let second: Void = TerminalShortcutProvisioner.shared.ensureShortcuts(for: [credential], in: db)
        async let third: Void = TerminalShortcutProvisioner.shared.ensureShortcuts(for: [credential], in: db)
        _ = await (first, second, third)

        #expect(try await shortcuts(for: "server-one", in: db).count == 1)
    }

    @Test
    func removesDuplicatesLeftBehindByEarlierVersions() async throws {
        let db = try makeDatabase()
        for _ in 0..<4 {
            try await writeShortcut(credentialKey: "server-one", title: "Server One", in: db)
        }
        try await writeShortcut(credentialKey: "server-two", title: "Server Two", in: db)

        await TerminalShortcutProvisioner.shared.ensureShortcuts(
            for: [makeCredential(key: "server-one", label: "Server One")],
            in: db
        )

        #expect(try await shortcuts(for: "server-one", in: db).count == 1)
        #expect(try await shortcuts(for: "server-two", in: db).count == 1)
    }
}
