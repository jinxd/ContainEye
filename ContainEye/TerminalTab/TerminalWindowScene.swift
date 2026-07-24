//
//  TerminalWindowScene.swift
//  ContainEye
//
//  Standalone terminal windows for iPad/Mac multi-window. Every window shares the
//  single workspace store but is scoped to its own `windowID`; a window shows only
//  the tabs assigned to it (Safari-style).
//

import SwiftUI
import UIKit

/// Identifies which window a standalone terminal scene should display.
struct TerminalWindowTarget: Codable, Hashable, Identifiable {
    var windowID: String
    var id: String { windowID }
}

/// Bridges the UIKit terminal chrome to SwiftUI's multi-window support. The main
/// terminal view registers `openTerminalWindow` while it is on screen.
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

    /// Best-effort close of every window except the currently active one. Used by
    /// "collapse" after all tabs have been pulled into the main window.
    func closeSecondaryWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if windowScene.activationState != .foregroundActive {
                UIApplication.shared.requestSceneSessionDestruction(windowScene.session, options: nil)
            }
        }
    }

    private var installedDisconnectObserver = false

    /// Watches for windows being closed so we can ask what to do with their tabs.
    func installSceneDisconnectObserverIfNeeded() {
        guard !installedDisconnectObserver else { return }
        installedDisconnectObserver = true
        NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let scene = note.object as? UIScene,
                      let windowID = scene.session.userInfo?["terminalWindowID"] as? String else { return }
                TerminalWindowRouter.shared.handleWindowClosed(windowID: windowID)
            }
        }
    }

    private func handleWindowClosed(windowID: String) {
        guard windowID != TerminalWorkspaceStore.mainWindowID else { return }
        let store = TerminalWorkspaceStore.shared
        let tabCount = store.tabIDs(inWindow: windowID).count
        guard tabCount > 0 else {
            store.discardWindow(windowID, moveTabsTo: nil)
            return
        }

        let alert = UIAlertController(
            title: "Window closed",
            message: "Move its \(tabCount) tab\(tabCount == 1 ? "" : "s") to the main window, or close them?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Move to Main Window", style: .default) { _ in
            store.discardWindow(windowID, moveTabsTo: TerminalWorkspaceStore.mainWindowID)
        })
        alert.addAction(UIAlertAction(title: "Close Tabs", style: .destructive) { _ in
            store.discardWindow(windowID, moveTabsTo: nil)
        })

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var top = windowScene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
}

/// The content of a standalone terminal window: the shared workspace scoped to one
/// window. A `nil` target means a system-opened window that gets a fresh windowID.
struct StandaloneTerminalScene: View {
    @State private var windowID: String

    init(target: TerminalWindowTarget?) {
        _windowID = State(initialValue: target?.windowID ?? UUID().uuidString)
    }

    var body: some View {
        TerminalWorkspaceNavigationHost(workspace: .shared, windowID: windowID)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("Terminal")
            .trackView("terminal/window")
    }
}
