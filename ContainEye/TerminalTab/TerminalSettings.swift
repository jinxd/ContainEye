import Foundation
import Observation

struct TerminalThemePreset: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    let selectionBackground: String

    static let all: [TerminalThemePreset] = [
        .init(
            id: "midnight",
            name: "Midnight",
            background: "#0D1117",
            foreground: "#E6EDF3",
            cursor: "#58A6FF",
            selectionBackground: "#264F78"
        ),
        .init(
            id: "solarized-dark",
            name: "Solarized Dark",
            background: "#002B36",
            foreground: "#93A1A1",
            cursor: "#B58900",
            selectionBackground: "#073642"
        ),
        .init(
            id: "dracula",
            name: "Dracula",
            background: "#282A36",
            foreground: "#F8F8F2",
            cursor: "#FF79C6",
            selectionBackground: "#44475A"
        ),
        .init(
            id: "light",
            name: "Paper Light",
            background: "#FAFAFA",
            foreground: "#1F2328",
            cursor: "#0969DA",
            selectionBackground: "#DDF4FF"
        ),
    ]
}

struct TerminalThemeCustom: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var background: String
    var foreground: String
    var cursor: String
    var selectionBackground: String
}

enum TerminalThemeSelection: Codable, Hashable {
    case preset(id: String)
    case custom(id: String)
}

enum TerminalHardwareAction: String, Codable, CaseIterable {
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case tab
    case enter
    case escape
    case ctrlToggle
    case pageUp
    case pageDown
    case interrupt

    var title: String {
        switch self {
        case .arrowUp: "Arrow Up"
        case .arrowDown: "Arrow Down"
        case .arrowLeft: "Arrow Left"
        case .arrowRight: "Arrow Right"
        case .tab: "Tab"
        case .enter: "Enter"
        case .escape: "Escape"
        case .ctrlToggle: "Ctrl Toggle"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .interrupt: "Interrupt (Ctrl+C)"
        }
    }
}

struct TerminalDisplaySettings: Codable, Hashable {
    var fontSize: Int
    var minFontSize: Int
    var maxFontSize: Int
    var step: Int

    static let `default` = TerminalDisplaySettings(
        fontSize: 13,
        minFontSize: 10,
        maxFontSize: 24,
        step: 1
    )
}

struct TerminalHardwareSettings: Codable, Hashable {
    var volumeEnabled: Bool
    var volumeUpAction: TerminalHardwareAction
    var volumeDownAction: TerminalHardwareAction
    var shakeEnabled: Bool
    var shakeAction: TerminalHardwareAction

    static let `default` = TerminalHardwareSettings(
        volumeEnabled: false,
        volumeUpAction: .arrowUp,
        volumeDownAction: .arrowDown,
        shakeEnabled: false,
        shakeAction: .interrupt
    )
}

struct TerminalSettingsState: Codable, Hashable {
    var themeSelection: TerminalThemeSelection
    var customThemes: [TerminalThemeCustom]
    var display: TerminalDisplaySettings
    var hardware: TerminalHardwareSettings

    static let `default` = TerminalSettingsState(
        themeSelection: .preset(id: "midnight"),
        customThemes: [],
        display: .default,
        hardware: .default
    )
}

struct TerminalResolvedTheme: Hashable {
    let background: String
    let foreground: String
    let cursor: String
    let selectionBackground: String

    var payload: [String: String] {
        [
            "background": background,
            "foreground": foreground,
            "cursor": cursor,
            "selectionBackground": selectionBackground,
        ]
    }
}

@MainActor
@Observable
final class TerminalSettingsStore {
    static let shared = TerminalSettingsStore(userDefaults: .standard)

    private enum Keys {
        static let state = "terminal.settings.v1"
        static let migrationFlag = "terminal.settings.migrated.v1"
        static let legacyUseVolumeButtons = "useVolumeButtons"
    }

    private let defaults: UserDefaults

    private(set) var state: TerminalSettingsState {
        didSet {
            persist()
        }
    }

    init(userDefaults: UserDefaults) {
        defaults = userDefaults
        state = Self.loadState(from: userDefaults)
        state = sanitize(state)
        persist()
    }

    var resolvedTheme: TerminalResolvedTheme {
        resolveTheme(for: state.themeSelection)
    }

    func resolvedTheme(for selection: TerminalThemeSelection) -> TerminalResolvedTheme {
        resolveTheme(for: selection)
    }

    func themeSelectionKey(for selection: TerminalThemeSelection) -> String {
        switch selection {
        case let .preset(id):
            return "preset:\(id)"
        case let .custom(id):
            return "custom:\(id)"
        }
    }

    func themeSelection(from key: String) -> TerminalThemeSelection? {
        if key.hasPrefix("preset:") {
            return .preset(id: String(key.dropFirst("preset:".count)))
        }
        if key.hasPrefix("custom:") {
            return .custom(id: String(key.dropFirst("custom:".count)))
        }
        return nil
    }

    func themeDisplayName(for key: String?) -> String {
        guard let key,
              let selection = themeSelection(from: key)
        else {
            return "Use App Default Theme"
        }

        switch selection {
        case let .preset(id):
            return TerminalThemePreset.all.first(where: { $0.id == id })?.name ?? "Use App Default Theme"
        case let .custom(id):
            return state.customThemes.first(where: { $0.id == id })?.name ?? "Use App Default Theme"
        }
    }

    var selectedThemeName: String {
        switch state.themeSelection {
        case let .preset(id):
            return TerminalThemePreset.all.first(where: { $0.id == id })?.name ?? "Midnight"
        case let .custom(id):
            return state.customThemes.first(where: { $0.id == id })?.name ?? "Custom"
        }
    }

    func setThemeSelection(_ selection: TerminalThemeSelection) {
        state.themeSelection = selection
    }

    func createTheme(
        name: String,
        background: String,
        foreground: String,
        cursor: String,
        selectionBackground: String
    ) {
        let custom = TerminalThemeCustom(
            id: UUID().uuidString,
            name: normalizedName(name),
            background: normalizeHex(background),
            foreground: normalizeHex(foreground),
            cursor: normalizeHex(cursor),
            selectionBackground: normalizeHex(selectionBackground)
        )
        state.customThemes.append(custom)
        state.themeSelection = .custom(id: custom.id)
        state = sanitize(state)
    }

    func updateTheme(
        id: String,
        name: String,
        background: String,
        foreground: String,
        cursor: String,
        selectionBackground: String
    ) {
        guard let index = state.customThemes.firstIndex(where: { $0.id == id }) else { return }
        state.customThemes[index].name = normalizedName(name)
        state.customThemes[index].background = normalizeHex(background)
        state.customThemes[index].foreground = normalizeHex(foreground)
        state.customThemes[index].cursor = normalizeHex(cursor)
        state.customThemes[index].selectionBackground = normalizeHex(selectionBackground)
        state = sanitize(state)
    }

    func deleteTheme(id: String) {
        state.customThemes.removeAll(where: { $0.id == id })
        if case let .custom(selectedID) = state.themeSelection, selectedID == id {
            state.themeSelection = .preset(id: "midnight")
        }
        state = sanitize(state)
    }

    func setFontSize(_ size: Int) {
        let clamped = clamp(size, min: state.display.minFontSize, max: state.display.maxFontSize)
        state.display.fontSize = clamped
    }

    func adjustFontSize(steps: Int) {
        guard steps != 0 else { return }
        let delta = steps * max(1, state.display.step)
        setFontSize(state.display.fontSize + delta)
    }

    func setVolumeEnabled(_ enabled: Bool) {
        state.hardware.volumeEnabled = enabled
    }

    func setShakeEnabled(_ enabled: Bool) {
        state.hardware.shakeEnabled = enabled
    }

    func setVolumeUpAction(_ action: TerminalHardwareAction) {
        state.hardware.volumeUpAction = action
    }

    func setVolumeDownAction(_ action: TerminalHardwareAction) {
        state.hardware.volumeDownAction = action
    }

    func setShakeAction(_ action: TerminalHardwareAction) {
        state.hardware.shakeAction = action
    }

    func customTheme(id: String) -> TerminalThemeCustom? {
        state.customThemes.first(where: { $0.id == id })
    }

    private func resolveTheme(for selection: TerminalThemeSelection) -> TerminalResolvedTheme {
        switch selection {
        case let .preset(id):
            if let preset = TerminalThemePreset.all.first(where: { $0.id == id }) {
                return TerminalResolvedTheme(
                    background: preset.background,
                    foreground: preset.foreground,
                    cursor: preset.cursor,
                    selectionBackground: preset.selectionBackground
                )
            }
        case let .custom(id):
            if let custom = state.customThemes.first(where: { $0.id == id }) {
                return TerminalResolvedTheme(
                    background: custom.background,
                    foreground: custom.foreground,
                    cursor: custom.cursor,
                    selectionBackground: custom.selectionBackground
                )
            }
        }

        let fallback = TerminalThemePreset.all[0]
        return TerminalResolvedTheme(
            background: fallback.background,
            foreground: fallback.foreground,
            cursor: fallback.cursor,
            selectionBackground: fallback.selectionBackground
        )
    }

    private static func loadState(from defaults: UserDefaults) -> TerminalSettingsState {
        if let data = defaults.data(forKey: Keys.state),
           let decoded = try? JSONDecoder().decode(TerminalSettingsState.self, from: data)
        {
            return decoded
        }

        var initial = TerminalSettingsState.default
        if !defaults.bool(forKey: Keys.migrationFlag),
           defaults.object(forKey: Keys.legacyUseVolumeButtons) != nil
        {
            initial.hardware.volumeEnabled = defaults.bool(forKey: Keys.legacyUseVolumeButtons)
        }
        defaults.set(true, forKey: Keys.migrationFlag)
        return initial
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Keys.state)
        }
    }

    private func sanitize(_ state: TerminalSettingsState) -> TerminalSettingsState {
        var sanitized = state

        if sanitized.display.minFontSize > sanitized.display.maxFontSize {
            sanitized.display.minFontSize = 10
            sanitized.display.maxFontSize = 24
        }
        sanitized.display.step = max(1, sanitized.display.step)
        sanitized.display.fontSize = clamp(
            sanitized.display.fontSize,
            min: sanitized.display.minFontSize,
            max: sanitized.display.maxFontSize
        )

        sanitized.customThemes = dedupeCustomThemeNames(in: sanitized.customThemes)

        switch sanitized.themeSelection {
        case let .preset(id):
            if !TerminalThemePreset.all.contains(where: { $0.id == id }) {
                sanitized.themeSelection = .preset(id: "midnight")
            }
        case let .custom(id):
            if !sanitized.customThemes.contains(where: { $0.id == id }) {
                sanitized.themeSelection = .preset(id: "midnight")
            }
        }

        return sanitized
    }

    private func dedupeCustomThemeNames(in themes: [TerminalThemeCustom]) -> [TerminalThemeCustom] {
        var seen: [String: Int] = [:]
        return themes.map { theme in
            var current = theme
            let base = normalizedName(theme.name)
            let count = seen[base, default: 0]
            if count == 0 {
                current.name = base
            } else {
                current.name = "\(base) \(count + 1)"
            }
            seen[base] = count + 1
            current.background = normalizeHex(current.background)
            current.foreground = normalizeHex(current.foreground)
            current.cursor = normalizeHex(current.cursor)
            current.selectionBackground = normalizeHex(current.selectionBackground)
            return current
        }
    }

    private func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Custom Theme" : trimmed
    }

    private func normalizeHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.replacingOccurrences(of: "#", with: "")
        if withoutPrefix.count == 6,
           withoutPrefix.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
        {
            return "#\(withoutPrefix.uppercased())"
        }

        return "#000000"
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}
