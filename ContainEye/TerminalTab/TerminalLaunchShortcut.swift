import Foundation
import Blackbird

struct TerminalLaunchShortcut: BlackbirdModel {
    @BlackbirdColumn var id: String = UUID().uuidString
    @BlackbirdColumn var credentialKey: String
    @BlackbirdColumn var title: String
    @BlackbirdColumn var startupScript: String
    @BlackbirdColumn var colorHex: String? = nil
    @BlackbirdColumn var themeSelectionKey: String? = nil
    @BlackbirdColumn var lastUse: Date

    static let primaryKey: [BlackbirdColumnKeyPath] = [\.$id]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [\.$credentialKey, \.$lastUse],
        [\.$lastUse],
    ]

    static func all(in db: Blackbird.Database) async -> [TerminalLaunchShortcut] {
        (try? await TerminalLaunchShortcut.read(from: db, matching: .all, orderBy: .descending(\.$lastUse), limit: 500)) ?? []
    }
}

/// Creates the default shortcut for every credential and drops duplicates.
///
/// The terminal picker reloads from unstructured tasks that can overlap while the
/// pane is being laid out. Doing the read-then-write directly in each task let
/// several passes observe "no shortcut yet" and each insert its own row, so a
/// single credential ended up with many identical "This Mac" cells. Provisioning
/// is therefore chained: every request runs only after its predecessor finished,
/// which makes it idempotent. The same pass cleans up rows that earlier versions
/// already duplicated.
actor TerminalShortcutProvisioner {
    static let shared = TerminalShortcutProvisioner()

    /// Tail of the provisioning chain. Actor reentrancy alone is not enough here:
    /// a batch suspends on its database awaits, so a second batch could otherwise
    /// read before the first one writes.
    private var tail: Task<Void, Never>?

    func ensureShortcuts(for credentials: [Credential], in db: Blackbird.Database) async {
        let previous = tail
        let work = Task { [credentials, db] in
            await previous?.value
            for credential in credentials {
                await Self.ensureShortcut(for: credential, in: db)
            }
        }
        tail = work
        await work.value
    }

    private static func ensureShortcut(for credential: Credential, in db: Blackbird.Database) async {
        let existing = (try? await TerminalLaunchShortcut.read(
            from: db,
            matching: \.$credentialKey == credential.key,
            orderBy: .descending(\.$lastUse)
        )) ?? []

        if existing.isEmpty {
            let shortcut = TerminalLaunchShortcut(
                credentialKey: credential.key,
                title: credential.label,
                startupScript: "",
                colorHex: "#3B82F6",
                themeSelectionKey: nil,
                lastUse: .distantPast
            )
            try? await shortcut.write(to: db)
            return
        }

        // Keep the most recently used shortcut, delete the accidental duplicates.
        for duplicate in existing.dropFirst() {
            try? await duplicate.delete(from: db)
        }
    }
}
