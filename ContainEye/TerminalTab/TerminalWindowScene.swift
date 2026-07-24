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
