//
//  AppSceneRootView.swift
//  ContainEye
//
//  Enforces a single "main" app window. The first scene shows the full app;
//  any additional window the system opens shows a standalone terminal instead,
//  so there is only ever one main window.
//

import SwiftUI

@MainActor
@Observable
final class AppSceneCoordinator {
    static let shared = AppSceneCoordinator()
    private init() {}

    private var mainSceneID: String?

    /// Returns true if the given scene is (or becomes) the single main scene.
    func isMainScene(_ id: String) -> Bool {
        if mainSceneID == nil {
            mainSceneID = id
        }
        return mainSceneID == id
    }

    func release(_ id: String) {
        if mainSceneID == id {
            mainSceneID = nil
        }
    }
}

/// Root of every app scene. Resolves whether this scene is the main window or an
/// overflow window; overflow windows render a standalone terminal.
struct AppSceneRootView<MainContent: View>: View {
    @ViewBuilder let mainContent: () -> MainContent

    @State private var sceneID = UUID().uuidString
    @State private var isMain: Bool?

    var body: some View {
        Group {
            switch isMain {
            case .some(true):
                mainContent()
            case .some(false):
                StandaloneTerminalScene(target: nil)
            case .none:
                Color(.systemBackground).ignoresSafeArea()
            }
        }
        .onAppear {
            if isMain == nil {
                isMain = AppSceneCoordinator.shared.isMainScene(sceneID)
            }
        }
        .onDisappear {
            AppSceneCoordinator.shared.release(sceneID)
        }
    }
}
