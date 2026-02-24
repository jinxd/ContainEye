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

    static func ensureDefaultShortcutIfNeeded(for credential: Credential, in db: Blackbird.Database) async {
        let existing = (try? await TerminalLaunchShortcut.read(from: db, matching: \.$credentialKey == credential.key, limit: 1)) ?? []
        guard existing.isEmpty else { return }

        let shortcut = TerminalLaunchShortcut(
            credentialKey: credential.key,
            title: credential.label,
            startupScript: "",
            colorHex: "#3B82F6",
            themeSelectionKey: nil,
            lastUse: .distantPast
        )
        try? await shortcut.write(to: db)
    }
}
