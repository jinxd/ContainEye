import Foundation
import Testing
@testable import ContainEye

struct TerminalWorkspaceStoreTests {
    @MainActor
    private func makeStore(persistenceKey: String = UUID().uuidString) -> TerminalWorkspaceStore {
        let suiteName = "ContainEyeTests.Workspace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return TerminalWorkspaceStore(
            userDefaults: defaults,
            persistenceKey: persistenceKey,
            resolveCredentialLabel: { key in "Label-\(key)" },
            autoConnectControllers: false
        )
    }

    @MainActor
    @Test
    func enforcesPaneLimitOfFour() {
        let store = makeStore()

        for _ in 0..<10 {
            store.splitPane()
        }

        #expect(store.panes.count == 4)
    }

    @MainActor
    @Test
    func opensTabsAcrossPanesAndEnforcesOneSessionPerPaneLimit() {
        let store = makeStore()
        store.splitPane()

        let focusedPaneID = store.focusedPaneID
        #expect(focusedPaneID != nil)

        for idx in 0..<20 {
            store.openTab(credentialKey: "server-\(idx)", inFocusedPane: true)
        }

        #expect(store.tabs.count == 4)

        if let focusedPaneID {
            let focusedTabs = store.tabStates(in: focusedPaneID)
            #expect(focusedTabs.count == 1)
        }
    }

    @MainActor
    @Test
    func persistsAndRestoresWorkspaceSnapshot() {
        let persistenceKey = "workspace.persist.\(UUID().uuidString)"
        let suiteName = "ContainEyeTests.Workspace.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let storeA = TerminalWorkspaceStore(
            userDefaults: defaults,
            persistenceKey: persistenceKey,
            resolveCredentialLabel: { key in "Label-\(key)" },
            autoConnectControllers: false
        )

        storeA.openTab(credentialKey: "one", inFocusedPane: true)
        storeA.splitPane()
        storeA.openTab(credentialKey: "two", inFocusedPane: true)
        storeA.persistWorkspace()

        let paneCount = storeA.panes.count
        let tabCount = storeA.tabs.count
        let focusedPane = storeA.focusedPaneID

        let storeB = TerminalWorkspaceStore(
            userDefaults: defaults,
            persistenceKey: persistenceKey,
            resolveCredentialLabel: { key in "Label-\(key)" },
            autoConnectControllers: false
        )

        #expect(storeB.panes.count == paneCount)
        #expect(storeB.tabs.count == tabCount)
        #expect(storeB.focusedPaneID == focusedPane)
    }

    @MainActor
    @Test
    func persistsExplicitTmuxSessionNameOnTab() {
        let persistenceKey = "workspace.tmux.persist.\(UUID().uuidString)"
        let suiteName = "ContainEyeTests.Workspace.tmux.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let storeA = TerminalWorkspaceStore(
            userDefaults: defaults,
            persistenceKey: persistenceKey,
            resolveCredentialLabel: { key in "Label-\(key)" },
            autoConnectControllers: false
        )

        storeA.openTab(
            credentialKey: "server-one",
            preferredTitle: "Session alpha",
            inFocusedPane: true,
            tmuxSessionName: "alpha"
        )
        storeA.persistWorkspace()

        let storeB = TerminalWorkspaceStore(
            userDefaults: defaults,
            persistenceKey: persistenceKey,
            resolveCredentialLabel: { key in "Label-\(key)" },
            autoConnectControllers: false
        )

        let restored = storeB.tabs.values.first
        #expect(restored?.tmuxSessionName == "alpha")
    }
}
