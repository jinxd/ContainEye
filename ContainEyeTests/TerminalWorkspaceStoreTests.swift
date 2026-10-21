import Foundation
import Testing
@testable import ContainEye

struct TerminalWorkspaceStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ContainEyeTests.Workspace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func makeStore(
        defaults: UserDefaults? = nil,
        persistenceKey: String = "workspace.\(UUID().uuidString)"
    ) -> TerminalWorkspaceStore {
        TerminalWorkspaceStore(
            userDefaults: defaults ?? makeDefaults(),
            persistenceKey: persistenceKey,
            resolveCredentialLabel: { key in "Label-\(key)" },
            autoConnectControllers: false
        )
    }

    @MainActor
    @Test
    func enforcesMaxTabCount() {
        let store = makeStore()

        for idx in 0..<(store.maxTabCount + 6) {
            store.openTab(credentialKey: "server-\(idx)")
        }

        #expect(store.tabs.count == store.maxTabCount)
        #expect(store.tabIDs(inWindow: TerminalWorkspaceStore.mainWindowID).count == store.maxTabCount)
    }

    @MainActor
    @Test
    func scopesTabsToTheirOwnWindow() {
        let store = makeStore()

        store.openTab(credentialKey: "one", windowID: "main")
        store.openTab(credentialKey: "two", windowID: "second")

        #expect(store.tabIDs(inWindow: "main").count == 1)
        #expect(store.tabIDs(inWindow: "second").count == 1)
        #expect(Set(store.windowIDsWithTabs()) == ["main", "second"])

        let secondPaneID = store.paneID(forWindow: "second")
        #expect(store.activeTab(in: secondPaneID)?.credentialKey == "two")
        #expect(store.focusedPaneID == secondPaneID)
    }

    @MainActor
    @Test
    func emptyTabBecomesSessionWhenFilled() {
        let store = makeStore()
        let paneID = store.paneID(forWindow: TerminalWorkspaceStore.mainWindowID)

        let tabID = store.beginNewTab(inWindow: TerminalWorkspaceStore.mainWindowID)
        #expect(store.isTabEmpty(tabID))
        #expect(store.activeTab(in: paneID)?.title == "New Tab")

        store.fillTab(tabID: tabID, credentialKey: "server-one", preferredTitle: "Production")

        #expect(!store.isTabEmpty(tabID))
        #expect(store.tabs.count == 1)
        #expect(store.tabState(id: tabID)?.credentialKey == "server-one")
        #expect(store.tabState(id: tabID)?.title == "Production")
        #expect(store.activeTab(in: paneID)?.id == tabID)
    }

    @MainActor
    @Test
    func reopeningTmuxSessionFocusesExistingTab() {
        let store = makeStore()

        store.openTab(credentialKey: "server-one", preferredTitle: "alpha", tmuxSessionName: "alpha")
        let existingTabID = store.tabIDs(inWindow: "main").first
        #expect(existingTabID != nil)

        store.openTab(credentialKey: "server-two", windowID: "second")
        store.openTab(credentialKey: "server-one", preferredTitle: "alpha again", tmuxSessionName: "alpha")

        #expect(store.tabs.count == 2)
        #expect(store.focusedPaneID == store.paneID(forWindow: "main"))
        #expect(store.activeTab(in: store.paneID(forWindow: "main"))?.id == existingTabID)
    }

    @MainActor
    @Test
    func uniquifiesDuplicateTabTitles() {
        let store = makeStore()

        store.openTab(credentialKey: "one", preferredTitle: "Production")
        store.openTab(credentialKey: "one", preferredTitle: "Production")

        let titles = store.tabStates(in: store.paneID(forWindow: TerminalWorkspaceStore.mainWindowID))
            .map(\.title)
        #expect(titles == ["Production", "Production (2)"])
    }

    @MainActor
    @Test
    func movesTabBetweenWindowsAndReorders() {
        let store = makeStore()
        let paneID = store.paneID(forWindow: TerminalWorkspaceStore.mainWindowID)

        store.openTab(credentialKey: "one", windowID: "main")
        store.openTab(credentialKey: "two", windowID: "main")
        let firstTabID = store.tabIDs(inWindow: "main")[0]
        let secondTabID = store.tabIDs(inWindow: "main")[1]

        store.moveTab(tabID: secondTabID, toWindow: "main", at: 0)
        #expect(store.tabIDs(inWindow: "main") == [secondTabID, firstTabID])
        #expect(store.activeTab(in: paneID)?.id == secondTabID)

        store.moveTab(tabID: firstTabID, toWindow: "second")
        #expect(store.tabIDs(inWindow: "main") == [secondTabID])
        #expect(store.tabIDs(inWindow: "second") == [firstTabID])
        #expect(store.focusedPaneID == store.paneID(forWindow: "second"))
    }

    @MainActor
    @Test
    func collapseAllWindowsDropsEmptyPlaceholders() {
        let store = makeStore()

        store.openTab(credentialKey: "one", windowID: "main")
        store.beginNewTab(inWindow: "main")
        store.openTab(credentialKey: "two", windowID: "second")

        store.collapseAllWindows()

        #expect(store.panes.count == 1)
        #expect(store.tabs.count == 2)
        #expect(store.tabIDs(inWindow: "main").count == 2)
        #expect(store.tabIDs(inWindow: "second").isEmpty)
    }

    @MainActor
    @Test
    func discardWindowMovesOrClosesItsTabs() {
        let store = makeStore()
        store.openTab(credentialKey: "one", windowID: "main")
        store.openTab(credentialKey: "two", windowID: "second")

        store.discardWindow("second", moveTabsTo: "main")

        #expect(store.panes.count == 1)
        #expect(store.tabIDs(inWindow: "main").count == 2)

        let closingStore = makeStore()
        closingStore.openTab(credentialKey: "one", windowID: "main")
        closingStore.openTab(credentialKey: "two", windowID: "second")

        closingStore.discardWindow("second", moveTabsTo: nil)

        #expect(closingStore.panes.count == 1)
        #expect(closingStore.tabs.count == 1)
        #expect(closingStore.tabIDs(inWindow: "main").count == 1)
    }

    @MainActor
    @Test
    func clearPaneToServerPickerRemovesEveryTabInThatPane() {
        let store = makeStore()
        let paneID = store.paneID(forWindow: TerminalWorkspaceStore.mainWindowID)

        store.openTab(credentialKey: "one", windowID: "main")
        store.beginNewTab(inWindow: "main")

        store.clearPaneToServerPicker(paneID: paneID)

        #expect(store.tabs.isEmpty)
        #expect(store.tabIDs(inWindow: "main").isEmpty)
        #expect(store.focusedPaneID == paneID)
    }

    @MainActor
    @Test
    func persistsAndRestoresWorkspaceSnapshot() {
        let defaults = makeDefaults()
        let persistenceKey = "workspace.persist.\(UUID().uuidString)"

        let storeA = makeStore(defaults: defaults, persistenceKey: persistenceKey)
        storeA.openTab(credentialKey: "one", windowID: "main")
        storeA.openTab(credentialKey: "two", windowID: "second")
        storeA.persistWorkspace()

        let paneCount = storeA.panes.count
        let tabCount = storeA.tabs.count
        let focusedPane = storeA.focusedPaneID

        let storeB = makeStore(defaults: defaults, persistenceKey: persistenceKey)

        #expect(storeB.panes.count == paneCount)
        #expect(storeB.tabs.count == tabCount)
        #expect(storeB.focusedPaneID == focusedPane)
        #expect(storeB.tabIDs(inWindow: "main").count == 1)
        #expect(storeB.tabIDs(inWindow: "second").count == 1)
    }

    @MainActor
    @Test
    func persistsExplicitTmuxSessionNameOnTab() {
        let defaults = makeDefaults()
        let persistenceKey = "workspace.tmux.persist.\(UUID().uuidString)"

        let storeA = makeStore(defaults: defaults, persistenceKey: persistenceKey)
        storeA.openTab(
            credentialKey: "server-one",
            preferredTitle: "Session alpha",
            tmuxSessionName: "alpha"
        )
        storeA.persistWorkspace()

        let storeB = makeStore(defaults: defaults, persistenceKey: persistenceKey)

        let restored = storeB.tabs.values.first
        #expect(restored?.tmuxSessionName == "alpha")
        #expect(restored?.credentialKey == "server-one")
        #expect(restored?.title == "Session alpha")
    }

    @MainActor
    @Test
    func restoredEmptyTabStaysEmptyWhileSessionTabsReconnect() {
        let defaults = makeDefaults()
        let persistenceKey = "workspace.empty.\(UUID().uuidString)"

        let storeA = makeStore(defaults: defaults, persistenceKey: persistenceKey)
        let emptyTabID = storeA.beginNewTab(inWindow: "main")
        storeA.openTab(credentialKey: "server-one", windowID: "second")
        storeA.persistWorkspace()

        let storeB = makeStore(defaults: defaults, persistenceKey: persistenceKey)

        // The placeholder tab must not come back as a live-but-dead terminal:
        // no controller means `isTabEmpty` keeps the shortcut picker visible.
        #expect(storeB.tabs[emptyTabID] != nil)
        #expect(storeB.isTabEmpty(emptyTabID))
        #expect(storeB.controller(for: emptyTabID) == nil)

        // Real sessions still get a controller so they reconnect on launch.
        let sessionTabID = storeB.tabIDs(inWindow: "second").first
        #expect(sessionTabID != nil)
        #expect(sessionTabID.flatMap { storeB.controller(for: $0) } != nil)
    }
}
