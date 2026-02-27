import Foundation
import Observation

struct TerminalTabState: Identifiable, Codable, Hashable {
    let id: UUID
    var credentialKey: String
    var title: String
    var createdAt: Date
    var themeOverrideSelectionKey: String?
    var shortcutColorHex: String?
}

struct TerminalPaneState: Identifiable, Codable, Hashable {
    let id: UUID
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
    static let shared = TerminalWorkspaceStore(
        userDefaults: .standard,
        persistenceKey: "terminal.workspace.snapshot.v2",
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

    let maxPaneCount = 4
    let maxTabCount = 12

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
        persistenceKey: String = "terminal.workspace.snapshot.v1",
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

    func openTab(
        credentialKey: String,
        preferredTitle: String? = nil,
        inFocusedPane: Bool = true,
        themeOverrideSelectionKey: String? = nil,
        shortcutColorHex: String? = nil
    ) {
        guard tabs.count < maxTabCount else {
            return
        }

        let trimmedPreferredTitle = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (trimmedPreferredTitle?.isEmpty == false ? trimmedPreferredTitle! : nil)
            ?? resolveCredentialLabel(credentialKey)
            ?? credentialKey
        let tabTitle = makeTabTitle(baseLabel: label, credentialKey: credentialKey)

        if panes.isEmpty {
            panes = [TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)]
            focusedPaneID = panes.first?.id
        }

        normalizePanesForSingleSession()

        let targetPaneID: UUID
        if inFocusedPane,
           let focusedPaneID,
           let focusedIndex = panes.firstIndex(where: { $0.id == focusedPaneID }),
           panes[focusedIndex].activeTabID == nil {
            targetPaneID = focusedPaneID
        } else if let emptyPane = panes.first(where: { $0.activeTabID == nil }) {
            targetPaneID = emptyPane.id
        } else if panes.count < maxPaneCount {
            let pane = TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)
            panes.append(pane)
            targetPaneID = pane.id
        } else {
            // One live session per pane. At max pane count we cannot open another session.
            return
        }

        let tab = TerminalTabState(
            id: UUID(),
            credentialKey: credentialKey,
            title: tabTitle,
            createdAt: .now,
            themeOverrideSelectionKey: themeOverrideSelectionKey,
            shortcutColorHex: shortcutColorHex
        )

        tabs[tab.id] = tab

        if let idx = panes.firstIndex(where: { $0.id == targetPaneID }) {
            panes[idx].tabIDs = [tab.id]
            panes[idx].activeTabID = tab.id
        }

        focusedPaneID = targetPaneID

        let controller = XTermSessionController(
            id: tab.id,
            credentialKey: credentialKey,
            title: tab.title,
            suggestionEngine: suggestionEngine,
            documentIndex: suggestionIndex
        )
        if autoConnectControllers {
            controller.connect()
        }
        controllers[tab.id] = controller

        persistWorkspace()
    }

    private func makeTabTitle(baseLabel: String, credentialKey: String) -> String {
        let existingCount = tabs.values.filter { $0.credentialKey == credentialKey }.count
        if existingCount == 0 {
            return baseLabel
        }
        return "\(baseLabel) (\(existingCount + 1))"
    }

    func closeTab(tabID: UUID) {
        guard tabs[tabID] != nil else {
            return
        }

        tabs[tabID] = nil
        controllers[tabID]?.disconnect()
        controllers[tabID] = nil

        for idx in panes.indices {
            panes[idx].tabIDs.removeAll(where: { $0 == tabID })
            if panes[idx].activeTabID == tabID {
                panes[idx].activeTabID = panes[idx].tabIDs.last
            }
        }

        // Remove empty non-primary panes.
        if panes.count > 1 {
            panes.removeAll(where: { $0.tabIDs.isEmpty })
        }

        normalizePanesForSingleSession()

        persistWorkspace()
    }

    func splitPane() {
        guard panes.count < maxPaneCount else {
            return
        }

        let pane = TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)
        panes.append(pane)
        focusedPaneID = pane.id

        persistWorkspace()
    }

    func focusOrCreateEmptyPane() {
        if panes.isEmpty {
            let pane = TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)
            panes = [pane]
            focusedPaneID = pane.id
            persistWorkspace()
            return
        }

        if let emptyPane = panes.first(where: { $0.activeTabID == nil }) {
            focusedPaneID = emptyPane.id
            persistWorkspace()
            return
        }

        guard panes.count < maxPaneCount else {
            return
        }

        let pane = TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)
        panes.append(pane)
        focusedPaneID = pane.id
        persistWorkspace()
    }

    func removePane(paneID: UUID) {
        guard panes.count > 1,
              let pane = panes.first(where: { $0.id == paneID })
        else {
            return
        }

        for tabID in pane.tabIDs {
            tabs[tabID] = nil
            controllers[tabID]?.disconnect()
            controllers[tabID] = nil
        }

        panes.removeAll(where: { $0.id == paneID })
        normalizePanesForSingleSession()

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

    func controller(for tabID: UUID) -> XTermSessionController? {
        controllers[tabID]
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

    func visiblePaneIDs(isRegularWidth: Bool) -> [UUID] {
        if isRegularWidth {
            return panes.map(\.id)
        }

        if let focusedPaneID {
            return [focusedPaneID]
        }

        return panes.first.map { [$0.id] } ?? []
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

    func restoreWorkspace() {
        guard let data = defaults.data(forKey: persistenceKey),
              let snapshot = try? JSONDecoder().decode(TerminalWorkspaceSnapshot.self, from: data)
        else {
            if panes.isEmpty {
                panes = [TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)]
                focusedPaneID = panes.first?.id
            }
            return
        }

        panes = snapshot.panes
        focusedPaneID = snapshot.focusedPaneID
        tabs = Dictionary(uniqueKeysWithValues: snapshot.tabs.map { ($0.id, $0) })

        controllers = [:]
        for tab in snapshot.tabs {
            let controller = XTermSessionController(
                id: tab.id,
                credentialKey: tab.credentialKey,
                title: tab.title,
                suggestionEngine: suggestionEngine,
                documentIndex: suggestionIndex
            )
            if autoConnectControllers {
                controller.connect()
            }
            controllers[tab.id] = controller
        }

        normalizePanesForSingleSession()
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

    private func normalizePanesForSingleSession() {
        if panes.isEmpty {
            panes = [TerminalPaneState(id: UUID(), tabIDs: [], activeTabID: nil)]
        }

        var usedTabIDs = Set<UUID>()
        var attachedTabIDs = Set<UUID>()

        for idx in panes.indices {
            let preferred = panes[idx].activeTabID
            let candidates = [preferred] + panes[idx].tabIDs

            let chosen = candidates
                .compactMap { $0 }
                .first(where: { tabs[$0] != nil && !usedTabIDs.contains($0) })

            if let chosen {
                panes[idx].activeTabID = chosen
                panes[idx].tabIDs = [chosen]
                usedTabIDs.insert(chosen)
                attachedTabIDs.insert(chosen)
            } else {
                panes[idx].activeTabID = nil
                panes[idx].tabIDs = []
            }
        }

        // Drop detached tab/controller state to avoid stale shared sessions across panes.
        let detachedTabIDs = Set(tabs.keys).subtracting(attachedTabIDs)
        for tabID in detachedTabIDs {
            controllers[tabID]?.disconnect()
            controllers[tabID] = nil
            tabs[tabID] = nil
        }

        if focusedPaneID == nil || !panes.contains(where: { $0.id == focusedPaneID }) {
            focusedPaneID = panes.first?.id
        }
    }
}
