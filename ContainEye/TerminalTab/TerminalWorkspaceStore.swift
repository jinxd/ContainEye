import Foundation
import Observation

struct TerminalTabState: Identifiable, Codable, Hashable {
    let id: UUID
    var credentialKey: String
    var title: String
    var createdAt: Date
    var themeOverrideSelectionKey: String?
    var shortcutColorHex: String?
    var tmuxSessionName: String?
    var tmuxAttachOnly: Bool? = nil
    var disableAutoPersistentSession: Bool
}

/// A per-window tab group. Each OS window maps to exactly one pane; the pane
/// holds that window's tabs (Safari-style), one of which is active.
struct TerminalPaneState: Identifiable, Codable, Hashable {
    let id: UUID
    var windowID: String
    var tabIDs: [UUID]
    var activeTabID: UUID?
}

struct TerminalWorkspaceSnapshot: Codable {
    var panes: [TerminalPaneState]
    var tabs: [TerminalTabState]
    var focusedPaneID: UUID?
}

@MainActor
@Observable
final class TerminalWorkspaceStore {
    nonisolated static let mainWindowID = "main"

    static let shared = TerminalWorkspaceStore(
        userDefaults: .standard,
        persistenceKey: "terminal.workspace.snapshot.v3",
        resolveCredentialLabel: { key in
            keychain().getCredential(for: key)?.label
        },
        autoConnectControllers: true
    )

    private(set) var panes: [TerminalPaneState] = []
    private(set) var tabs: [UUID: TerminalTabState] = [:]
    private(set) var focusedPaneID: UUID?

    @ObservationIgnored
    private var controllers: [UUID: XTermSessionController] = [:]

    let maxTabCount = 24

    @ObservationIgnored
    private let suggestionIndex: RemoteDocumentTreeIndex
    @ObservationIgnored
    private let suggestionEngine: CommandSuggestionEngine

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let persistenceKey: String
    @ObservationIgnored
    private let resolveCredentialLabel: (String) -> String?
    @ObservationIgnored
    private let autoConnectControllers: Bool

    init(
        userDefaults: UserDefaults = .standard,
        persistenceKey: String = "terminal.workspace.snapshot.v3",
        resolveCredentialLabel: @escaping (String) -> String?,
        autoConnectControllers: Bool = true
    ) {
        defaults = userDefaults
        self.persistenceKey = persistenceKey
        self.resolveCredentialLabel = resolveCredentialLabel
        self.autoConnectControllers = autoConnectControllers
        suggestionIndex = RemoteDocumentTreeIndex()
        suggestionEngine = CommandSuggestionEngine(index: suggestionIndex)
        restoreWorkspace()
    }

    // MARK: Window ↔ pane mapping

    /// The pane backing a window, creating it if needed.
    @discardableResult
    func paneID(forWindow windowID: String) -> UUID {
        if let existing = panes.first(where: { $0.windowID == windowID }) {
            return existing.id
        }
        let pane = TerminalPaneState(id: UUID(), windowID: windowID, tabIDs: [], activeTabID: nil)
        panes.append(pane)
        if focusedPaneID == nil {
            focusedPaneID = pane.id
        }
        return pane.id
    }

    func windowID(forPane paneID: UUID) -> String? {
        panes.first(where: { $0.id == paneID })?.windowID
    }

    /// Window IDs that currently have at least one tab.
    func windowIDsWithTabs() -> [String] {
        panes.filter { !$0.tabIDs.isEmpty }.map(\.windowID)
    }

    /// "credentialKey|normalizedSession" keys for tmux sessions already open as
    /// tabs in some window *other than* the given one. Used so a window's picker
    /// and tabs overview don't offer sessions that belong to another window.
    func sessionKeysBoundToOtherWindows(excluding windowID: String) -> Set<String> {
        var result = Set<String>()
        for pane in panes where pane.windowID != windowID {
            for tabID in pane.tabIDs {
                guard let tab = tabs[tabID], let raw = tab.tmuxSessionName else { continue }
                let normalized = XTermSessionController.normalizeTmuxSessionName(raw)
                guard !normalized.isEmpty else { continue }
                result.insert("\(tab.credentialKey)|\(normalized)")
            }
        }
        return result
    }

    // MARK: Tabs

    func openTab(
        credentialKey: String,
        preferredTitle: String? = nil,
        windowID: String = TerminalWorkspaceStore.mainWindowID,
        themeOverrideSelectionKey: String? = nil,
        shortcutColorHex: String? = nil,
        tmuxSessionName: String? = nil,
        tmuxAttachOnly: Bool = false,
        disableAutoPersistentSession: Bool = false
    ) {
        guard tabs.count < maxTabCount else {
            return
        }

        let normalizedTmuxSessionName = tmuxSessionName.map { XTermSessionController.normalizeTmuxSessionName($0) }

        // If the session is already open in any window, focus it there.
        if let tmuxName = normalizedTmuxSessionName, !tmuxName.isEmpty,
           let existing = tabs.values.first(where: {
               $0.credentialKey == credentialKey &&
               ($0.tmuxSessionName.map { XTermSessionController.normalizeTmuxSessionName($0) } == tmuxName)
           }),
           let paneIndex = panes.firstIndex(where: { $0.tabIDs.contains(existing.id) }) {
            panes[paneIndex].activeTabID = existing.id
            focusedPaneID = panes[paneIndex].id
            persistWorkspace()
            return
        }

        let paneID = paneID(forWindow: windowID)

        let trimmedPreferredTitle = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (trimmedPreferredTitle?.isEmpty == false ? trimmedPreferredTitle! : nil)
            ?? resolveCredentialLabel(credentialKey)
            ?? credentialKey
        let tabTitle = makeTabTitle(baseLabel: label, paneID: paneID)

        let tab = TerminalTabState(
            id: UUID(),
            credentialKey: credentialKey,
            title: tabTitle,
            createdAt: .now,
            themeOverrideSelectionKey: themeOverrideSelectionKey,
            shortcutColorHex: shortcutColorHex,
            tmuxSessionName: normalizedTmuxSessionName,
            tmuxAttachOnly: tmuxAttachOnly,
            disableAutoPersistentSession: disableAutoPersistentSession
        )

        tabs[tab.id] = tab

        if let idx = panes.firstIndex(where: { $0.id == paneID }) {
            panes[idx].tabIDs.append(tab.id)
            panes[idx].activeTabID = tab.id
        }
        focusedPaneID = paneID

        let controller = XTermSessionController(
            id: tab.id,
            credentialKey: credentialKey,
            title: tab.title,
            tmuxSessionName: tab.tmuxSessionName,
            tmuxAttachOnly: tab.tmuxAttachOnly ?? false,
            disableAutoPersistentSession: tab.disableAutoPersistentSession,
            suggestionEngine: suggestionEngine,
            documentIndex: suggestionIndex
        )
        if autoConnectControllers {
            controller.connect()
        }
        controllers[tab.id] = controller

        persistWorkspace()
    }

    private func makeTabTitle(baseLabel: String, paneID: UUID) -> String {
        let siblingTitles = tabStates(in: paneID).map(\.title)
        guard siblingTitles.contains(baseLabel) else {
            return baseLabel
        }
        var index = 2
        while siblingTitles.contains("\(baseLabel) (\(index))") {
            index += 1
        }
        return "\(baseLabel) (\(index))"
    }

    func closeTab(tabID: UUID) {
        guard tabs[tabID] != nil else {
            return
        }

        tabs[tabID] = nil
        controllers[tabID]?.disconnect()
        controllers[tabID] = nil

        for idx in panes.indices {
            guard panes[idx].tabIDs.contains(tabID) else { continue }
            panes[idx].tabIDs.removeAll(where: { $0 == tabID })
            if panes[idx].activeTabID == tabID {
                panes[idx].activeTabID = panes[idx].tabIDs.last
            }
        }

        persistWorkspace()
    }

    /// Puts a window into "new tab" mode: keeps its tabs but shows the server
    /// picker (no active tab) so the user can start or attach another session.
    func beginNewTab(inWindow windowID: String) {
        let id = paneID(forWindow: windowID)
        guard let idx = panes.firstIndex(where: { $0.id == id }) else { return }
        panes[idx].activeTabID = nil
        focusedPaneID = id
        persistWorkspace()
    }

    func clearPaneToServerPicker(paneID: UUID) {
        guard let paneIndex = panes.firstIndex(where: { $0.id == paneID }) else {
            return
        }

        let tabIDsToClose = panes[paneIndex].tabIDs
        for tabID in tabIDsToClose {
            tabs[tabID] = nil
            controllers[tabID]?.disconnect()
            controllers[tabID] = nil
        }

        panes[paneIndex].tabIDs = []
        panes[paneIndex].activeTabID = nil
        focusedPaneID = paneID
        persistWorkspace()
    }

    // MARK: Moving tabs between windows

    /// Moves a tab into another window (or reorders within the same window),
    /// activating it there. The session controller is preserved, so the live
    /// terminal simply reappears at the destination. `index` inserts at a
    /// specific position; `nil` appends.
    func moveTab(tabID: UUID, toWindow windowID: String, at index: Int? = nil) {
        guard tabs[tabID] != nil else { return }

        let destination = paneID(forWindow: windowID)
        let sameWindow = panes.first(where: { $0.tabIDs.contains(tabID) })?.windowID == windowID

        for idx in panes.indices where panes[idx].tabIDs.contains(tabID) {
            panes[idx].tabIDs.removeAll(where: { $0 == tabID })
            if !sameWindow, panes[idx].activeTabID == tabID {
                panes[idx].activeTabID = panes[idx].tabIDs.last
            }
        }

        if let idx = panes.firstIndex(where: { $0.id == destination }) {
            let insertion = min(max(0, index ?? panes[idx].tabIDs.count), panes[idx].tabIDs.count)
            panes[idx].tabIDs.insert(tabID, at: insertion)
            panes[idx].activeTabID = tabID
        }
        focusedPaneID = destination
        persistWorkspace()
    }

    /// Pulls every tab from all windows into a single window (the main window by
    /// default). Other windows are emptied; their OS windows can then be closed.
    func collapseAllWindows(into windowID: String = TerminalWorkspaceStore.mainWindowID) {
        let destination = paneID(forWindow: windowID)
        guard let destIndex = panes.firstIndex(where: { $0.id == destination }) else { return }

        var orderedTabIDs = panes[destIndex].tabIDs
        let previousActive = panes[destIndex].activeTabID

        for idx in panes.indices where panes[idx].id != destination {
            orderedTabIDs.append(contentsOf: panes[idx].tabIDs.filter { !orderedTabIDs.contains($0) })
            panes[idx].tabIDs = []
            panes[idx].activeTabID = nil
        }

        panes[destIndex].tabIDs = orderedTabIDs
        panes[destIndex].activeTabID = previousActive ?? orderedTabIDs.last
        focusedPaneID = destination

        // Drop now-empty non-main panes.
        panes.removeAll(where: { $0.id != destination && $0.tabIDs.isEmpty })

        persistWorkspace()
    }

    func tabIDs(inWindow windowID: String) -> [UUID] {
        panes.first(where: { $0.windowID == windowID })?.tabIDs ?? []
    }

    /// Handles a closed window: either move its tabs to another window, or close
    /// them. The window's pane is then removed.
    func discardWindow(_ windowID: String, moveTabsTo destination: String?) {
        guard let paneIndex = panes.firstIndex(where: { $0.windowID == windowID }) else { return }
        let tabIDsInWindow = panes[paneIndex].tabIDs

        if let destination, destination != windowID {
            for tabID in tabIDsInWindow {
                moveTab(tabID: tabID, toWindow: destination)
            }
        } else {
            for tabID in tabIDsInWindow {
                tabs[tabID] = nil
                controllers[tabID]?.disconnect()
                controllers[tabID] = nil
            }
        }

        panes.removeAll(where: { $0.windowID == windowID })
        if focusedPaneID == nil || !panes.contains(where: { $0.id == focusedPaneID }) {
            focusedPaneID = panes.first?.id
        }
        persistWorkspace()
    }

    func focusPane(paneID: UUID) {
        guard panes.contains(where: { $0.id == paneID }) else {
            return
        }
        focusedPaneID = paneID
        persistWorkspace()
    }

    func setActiveTab(tabID: UUID, in paneID: UUID) {
        guard let idx = panes.firstIndex(where: { $0.id == paneID }) else {
            return
        }
        guard panes[idx].tabIDs.contains(tabID) else {
            return
        }

        panes[idx].activeTabID = tabID
        focusedPaneID = paneID
        persistWorkspace()
    }

    // MARK: Lookups

    func controller(for tabID: UUID) -> XTermSessionController? {
        controllers[tabID]
    }

    func tabState(id: UUID) -> TerminalTabState? {
        tabs[id]
    }

    func activeTab(in paneID: UUID) -> TerminalTabState? {
        guard let pane = panes.first(where: { $0.id == paneID }),
              let active = pane.activeTabID
        else {
            return nil
        }
        return tabs[active]
    }

    func tabStates(in paneID: UUID) -> [TerminalTabState] {
        guard let pane = panes.first(where: { $0.id == paneID }) else {
            return []
        }
        return pane.tabIDs.compactMap { tabs[$0] }
    }

    func activeControllerInFocusedPane() -> XTermSessionController? {
        guard let paneID = focusedPaneID,
              let pane = panes.first(where: { $0.id == paneID }),
              let activeID = pane.activeTabID
        else {
            return nil
        }
        return controllers[activeID]
    }

    /// The active session controller for a specific window (not the globally
    /// focused pane) — so each window's keyboard bar/suggestions are its own.
    func activeController(inWindow windowID: String) -> XTermSessionController? {
        guard let pane = panes.first(where: { $0.windowID == windowID }),
              let activeID = pane.activeTabID
        else {
            return nil
        }
        return controllers[activeID]
    }

    // MARK: Persistence

    func restoreWorkspace() {
        guard let data = defaults.data(forKey: persistenceKey),
              let snapshot = try? JSONDecoder().decode(TerminalWorkspaceSnapshot.self, from: data)
        else {
            if panes.isEmpty {
                _ = paneID(forWindow: TerminalWorkspaceStore.mainWindowID)
            }
            return
        }

        panes = snapshot.panes
        focusedPaneID = snapshot.focusedPaneID
        let migratedTabs = snapshot.tabs.map { migrateLegacyTabTmuxBinding($0) }
        tabs = Dictionary(uniqueKeysWithValues: migratedTabs.map { ($0.id, $0) })

        controllers = [:]
        for tab in migratedTabs {
            let controller = XTermSessionController(
                id: tab.id,
                credentialKey: tab.credentialKey,
                title: tab.title,
                tmuxSessionName: tab.tmuxSessionName,
                tmuxAttachOnly: tab.tmuxAttachOnly ?? false,
                disableAutoPersistentSession: tab.disableAutoPersistentSession,
                suggestionEngine: suggestionEngine,
                documentIndex: suggestionIndex
            )
            if autoConnectControllers {
                controller.connect()
            }
            controllers[tab.id] = controller
        }

        normalizeWorkspace()
    }

    func persistWorkspace() {
        let allTabs = tabs.values.sorted(by: { $0.createdAt < $1.createdAt })
        let snapshot = TerminalWorkspaceSnapshot(
            panes: panes,
            tabs: allTabs,
            focusedPaneID: focusedPaneID
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: persistenceKey)
        }
    }

    /// Ensures the main window pane exists, tab references are valid, and each
    /// pane's active tab is one it actually holds. Detached tabs are dropped.
    private func normalizeWorkspace() {
        if !panes.contains(where: { $0.windowID == TerminalWorkspaceStore.mainWindowID }) {
            _ = paneID(forWindow: TerminalWorkspaceStore.mainWindowID)
        }

        var referencedTabIDs = Set<UUID>()
        for idx in panes.indices {
            panes[idx].tabIDs = panes[idx].tabIDs.filter { tabs[$0] != nil }
            referencedTabIDs.formUnion(panes[idx].tabIDs)
            if let active = panes[idx].activeTabID, !panes[idx].tabIDs.contains(active) {
                panes[idx].activeTabID = panes[idx].tabIDs.last
            }
        }

        // Drop tabs/controllers that no pane references.
        let orphanTabIDs = Set(tabs.keys).subtracting(referencedTabIDs)
        for tabID in orphanTabIDs {
            controllers[tabID]?.disconnect()
            controllers[tabID] = nil
            tabs[tabID] = nil
        }

        if focusedPaneID == nil || !panes.contains(where: { $0.id == focusedPaneID }) {
            focusedPaneID = panes.first?.id
        }
    }

    func closeTabsBoundToTmuxSession(credentialKey: String, sessionName: String) {
        let normalizedTarget = XTermSessionController.normalizeTmuxSessionName(sessionName)
        guard !normalizedTarget.isEmpty else { return }

        let targetTabIDs = tabs.values.compactMap { tab -> UUID? in
            guard tab.credentialKey == credentialKey else { return nil }
            if let explicitRaw = tab.tmuxSessionName {
                let explicit = XTermSessionController.normalizeTmuxSessionName(explicitRaw)
                if !explicit.isEmpty && explicit == normalizedTarget {
                    return tab.id
                }
            }
            return nil
        }

        guard !targetTabIDs.isEmpty else { return }
        for tabID in targetTabIDs {
            closeTab(tabID: tabID)
        }
    }

    func renameTabsBoundToTmuxSession(credentialKey: String, oldSessionName: String, newSessionName: String) {
        let normalizedOld = XTermSessionController.normalizeTmuxSessionName(oldSessionName)
        let normalizedNew = XTermSessionController.normalizeTmuxSessionName(newSessionName)
        guard !normalizedOld.isEmpty, !normalizedNew.isEmpty, normalizedOld != normalizedNew else { return }

        var changed = false
        for tabID in tabs.keys {
            guard var tab = tabs[tabID], tab.credentialKey == credentialKey else { continue }
            let explicit = XTermSessionController.normalizeTmuxSessionName(tab.tmuxSessionName ?? "")
            guard !explicit.isEmpty, explicit == normalizedOld else { continue }
            tab.tmuxSessionName = normalizedNew
            tabs[tabID] = tab
            changed = true
        }

        guard changed else { return }
        persistWorkspace()
    }

    private func migrateLegacyTabTmuxBinding(_ tab: TerminalTabState) -> TerminalTabState {
        guard let raw = tab.tmuxSessionName else { return tab }
        let normalized = XTermSessionController.normalizeTmuxSessionName(raw)
        guard normalized.hasPrefix(XTermSessionController.autoTmuxSessionPrefix) else {
            return tab
        }

        var migrated = tab
        migrated.tmuxSessionName = nil
        migrated.tmuxAttachOnly = false
        migrated.disableAutoPersistentSession = true
        return migrated
    }
}
