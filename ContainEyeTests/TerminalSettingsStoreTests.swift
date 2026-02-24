import Foundation
import Testing
@testable import ContainEye

struct TerminalSettingsStoreTests {
    @MainActor
    private func makeDefaults(suffix: String = UUID().uuidString) -> UserDefaults {
        let suite = "ContainEyeTests.TerminalSettings.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    @Test
    func migrationReadsLegacyVolumeFlag() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "useVolumeButtons")

        let store = TerminalSettingsStore(userDefaults: defaults)

        #expect(store.state.hardware.volumeEnabled == true)
    }

    @MainActor
    @Test
    func clampsFontSizeToBounds() {
        let defaults = makeDefaults()
        let store = TerminalSettingsStore(userDefaults: defaults)

        store.setFontSize(999)
        #expect(store.state.display.fontSize == store.state.display.maxFontSize)

        store.setFontSize(-1)
        #expect(store.state.display.fontSize == store.state.display.minFontSize)
    }

    @MainActor
    @Test
    func persistsAndRestoresCustomThemeAndSelection() {
        let defaults = makeDefaults(suffix: "persist")

        let storeA = TerminalSettingsStore(userDefaults: defaults)
        storeA.createTheme(
            name: "Ocean",
            background: "#001122",
            foreground: "#CCDDEE",
            cursor: "#00AAFF",
            selectionBackground: "#113355"
        )

        let selectedName = storeA.selectedThemeName
        let selectedTheme = storeA.resolvedTheme

        let storeB = TerminalSettingsStore(userDefaults: defaults)
        #expect(storeB.selectedThemeName == selectedName)
        #expect(storeB.resolvedTheme == selectedTheme)
    }

    @MainActor
    @Test
    func dedupesCustomThemeNames() {
        let defaults = makeDefaults()
        let store = TerminalSettingsStore(userDefaults: defaults)

        store.createTheme(
            name: "Same",
            background: "#111111",
            foreground: "#EEEEEE",
            cursor: "#AAAAAA",
            selectionBackground: "#222222"
        )
        store.createTheme(
            name: "Same",
            background: "#333333",
            foreground: "#DDDDDD",
            cursor: "#BBBBBB",
            selectionBackground: "#444444"
        )

        let names = store.state.customThemes.map(\.name)
        #expect(names.contains("Same"))
        #expect(names.contains("Same 2"))
    }
}
