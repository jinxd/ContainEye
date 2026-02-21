import SwiftUI

private struct AgenticBridgeKey: EnvironmentKey {
    static var defaultValue: AgenticContextBridge {
        MainActor.assumeIsolated { AgenticContextBridge.shared }
    }
}

private struct AgenticContextStoreKey: EnvironmentKey {
    static var defaultValue: AgenticScreenContextStore {
        MainActor.assumeIsolated { AgenticScreenContextStore.shared }
    }
}

private struct TerminalNavigationManagerKey: EnvironmentKey {
    static var defaultValue: TerminalNavigationManager {
        MainActor.assumeIsolated { TerminalNavigationManager.shared }
    }
}

private struct StoreKitManagerKey: EnvironmentKey {
    static var defaultValue: StoreKitManager {
        MainActor.assumeIsolated { StoreKitManager.shared }
    }
}

extension EnvironmentValues {
    var agenticBridge: AgenticContextBridge {
        get { self[AgenticBridgeKey.self] }
        set { self[AgenticBridgeKey.self] = newValue }
    }

    var agenticContextStore: AgenticScreenContextStore {
        get { self[AgenticContextStoreKey.self] }
        set { self[AgenticContextStoreKey.self] = newValue }
    }

    var terminalNavigationManager: TerminalNavigationManager {
        get { self[TerminalNavigationManagerKey.self] }
        set { self[TerminalNavigationManagerKey.self] = newValue }
    }

    var storeKitManager: StoreKitManager {
        get { self[StoreKitManagerKey.self] }
        set { self[StoreKitManagerKey.self] = newValue }
    }
}
