//
//  TerminalWindowScene.swift
//  ContainEye
//
//  Standalone, single-session terminal windows for iPad/Mac multi-window.
//  Each pop-out window attaches its own SSH connection to one server-side tmux
//  session, independent of the main tabbed workspace.
//

import SwiftUI
import UIKit

/// A tmux session that can be opened in its own window.
struct TerminalWindowTarget: Codable, Hashable, Identifiable {
    var credentialKey: String
    var tmuxSessionName: String
    var title: String
    var colorHex: String?

    /// Stable identity so reopening the same session reuses its window state.
    var id: String { "\(credentialKey)|\(tmuxSessionName)" }
}

/// Bridges the UIKit terminal chrome to SwiftUI's multi-window support. The main
/// terminal view registers the `openTerminalWindow` closure while it is on screen.
@MainActor
final class TerminalWindowRouter {
    static let shared = TerminalWindowRouter()
    private init() {}

    var openTerminalWindow: ((TerminalWindowTarget) -> Void)?

    /// True only on platforms/configurations that allow multiple scenes (iPad, Mac).
    var supportsMultipleWindows: Bool {
        UIApplication.shared.supportsMultipleScenes
    }

    func open(_ target: TerminalWindowTarget) {
        openTerminalWindow?(target)
    }
}

enum TerminalWindowStore {
    /// Builds an independent workspace store seeded with a single attached session.
    /// A per-target persistence key keeps each window's layout separate from the
    /// main workspace and from other pop-out windows.
    @MainActor
    static func make(for target: TerminalWindowTarget) -> TerminalWorkspaceStore {
        let store = TerminalWorkspaceStore(
            userDefaults: .standard,
            persistenceKey: "terminal.window.\(target.id)",
            resolveCredentialLabel: { key in
                keychain().getCredential(for: key)?.label
            },
            autoConnectControllers: true
        )
        // Attach the requested tmux session (deduped against any restored state).
        store.openTab(
            credentialKey: target.credentialKey,
            preferredTitle: target.title,
            tmuxSessionName: target.tmuxSessionName,
            tmuxAttachOnly: true,
            disableAutoPersistentSession: true
        )
        return store
    }
}

/// The content of a standalone terminal window.
struct StandaloneTerminalScene: View {
    let target: TerminalWindowTarget
    @State private var workspace: TerminalWorkspaceStore

    init(target: TerminalWindowTarget) {
        self.target = target
        _workspace = State(initialValue: TerminalWindowStore.make(for: target))
    }

    var body: some View {
        TerminalWorkspaceNavigationHost(workspace: workspace)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(target.title)
            .trackView("terminal/window")
    }
}
