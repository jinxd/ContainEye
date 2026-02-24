import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
final class TerminalSettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case appearance
        case hardware
    }

    private enum Row: Hashable {
        case theme
        case createTheme
        case editTheme
        case deleteTheme
        case fontSize
        case volumeEnabled
        case volumeUpAction
        case volumeDownAction
        case shakeEnabled
        case shakeAction
    }

    private let settings = TerminalSettingsStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Terminal Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .prominent,
            target: self,
            action: #selector(didTapDone)
        )
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        startObservingSettings()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(for: section).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .appearance:
            return "Appearance"
        case .hardware:
            return "Hardware Inputs"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .appearance:
            return "Theme here is the app default for terminal sessions. Shortcut launches can override the theme per shortcut."
        case .hardware, .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows(for: indexPath.section)[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.secondaryTextProperties.color = .secondaryLabel
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch row {
        case .theme:
            config.text = "Default Theme"
            config.secondaryText = settings.selectedThemeName
            cell.accessoryType = .disclosureIndicator

        case .createTheme:
            config.text = "Create Theme"
            config.secondaryText = "Build with color pickers"
            cell.accessoryType = .disclosureIndicator

        case .editTheme:
            config.text = "Edit Current Theme"
            config.secondaryText = settings.selectedThemeName
            cell.accessoryType = .disclosureIndicator

        case .deleteTheme:
            config.text = "Delete Current Theme"
            config.textProperties.color = .systemRed
            cell.selectionStyle = .default

        case .fontSize:
            config.text = "Font Size"
            config.secondaryText = "\(settings.state.display.fontSize)"
            let stepper = UIStepper()
            stepper.minimumValue = Double(settings.state.display.minFontSize)
            stepper.maximumValue = Double(settings.state.display.maxFontSize)
            stepper.stepValue = Double(settings.state.display.step)
            stepper.value = Double(settings.state.display.fontSize)
            stepper.addTarget(self, action: #selector(didChangeFontStepper(_:)), for: .valueChanged)
            cell.accessoryView = stepper
            cell.selectionStyle = .none

        case .volumeEnabled:
            config.text = "Use Volume Buttons"
            let toggle = UISwitch()
            toggle.isOn = settings.state.hardware.volumeEnabled
            toggle.addTarget(self, action: #selector(didToggleVolume(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none

        case .volumeUpAction:
            config.text = "Volume Up Action"
            config.secondaryText = settings.state.hardware.volumeUpAction.title
            cell.accessoryType = .disclosureIndicator

        case .volumeDownAction:
            config.text = "Volume Down Action"
            config.secondaryText = settings.state.hardware.volumeDownAction.title
            cell.accessoryType = .disclosureIndicator

        case .shakeEnabled:
            config.text = "Enable Shake"
            let toggle = UISwitch()
            toggle.isOn = settings.state.hardware.shakeEnabled
            toggle.addTarget(self, action: #selector(didToggleShake(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none

        case .shakeAction:
            config.text = "Shake Action"
            config.secondaryText = settings.state.hardware.shakeAction.title
            cell.accessoryType = .disclosureIndicator
        }

        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        let row = rows(for: indexPath.section)[indexPath.row]
        switch row {
        case .theme:
            navigationController?.pushViewController(TerminalThemeSelectionViewController(settings: settings), animated: true)

        case .createTheme:
            navigationController?.pushViewController(
                TerminalThemeEditorViewController(settings: settings, mode: .create),
                animated: true
            )

        case .editTheme:
            if case let .custom(id) = settings.state.themeSelection,
               let custom = settings.customTheme(id: id)
            {
                navigationController?.pushViewController(
                    TerminalThemeEditorViewController(settings: settings, mode: .edit(custom)),
                    animated: true
                )
            }

        case .deleteTheme:
            if case let .custom(id) = settings.state.themeSelection {
                confirmDeleteTheme(id: id)
            }

        case .volumeUpAction:
            presentActionPicker(title: "Volume Up Action", selected: settings.state.hardware.volumeUpAction) { [weak self] action in
                self?.settings.setVolumeUpAction(action)
            }

        case .volumeDownAction:
            presentActionPicker(title: "Volume Down Action", selected: settings.state.hardware.volumeDownAction) { [weak self] action in
                self?.settings.setVolumeDownAction(action)
            }

        case .shakeAction:
            presentActionPicker(title: "Shake Action", selected: settings.state.hardware.shakeAction) { [weak self] action in
                self?.settings.setShakeAction(action)
            }

        case .fontSize, .volumeEnabled, .shakeEnabled:
            break
        }
    }

    private func rows(for section: Int) -> [Row] {
        guard let section = Section(rawValue: section) else { return [] }

        switch section {
        case .appearance:
            var rows: [Row] = [.theme, .createTheme, .fontSize]
            if case .custom = settings.state.themeSelection {
                rows.insert(.editTheme, at: 2)
                rows.insert(.deleteTheme, at: 3)
            }
            return rows
        case .hardware:
            return [.volumeEnabled, .volumeUpAction, .volumeDownAction, .shakeEnabled, .shakeAction]
        }
    }

    private func startObservingSettings() {
        withObservationTracking({ [weak self] in
            guard let self else { return }
            _ = self.settings.state
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startObservingSettings()
                self.tableView.reloadData()
            }
        })
    }

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }

    @objc
    private func didChangeFontStepper(_ sender: UIStepper) {
        settings.setFontSize(Int(sender.value))
    }

    @objc
    private func didToggleVolume(_ sender: UISwitch) {
        settings.setVolumeEnabled(sender.isOn)
    }

    @objc
    private func didToggleShake(_ sender: UISwitch) {
        settings.setShakeEnabled(sender.isOn)
    }

    private func presentActionPicker(
        title: String,
        selected: TerminalHardwareAction,
        onPick: @escaping (TerminalHardwareAction) -> Void
    ) {
        let picker = TerminalHardwareActionPickerViewController(title: title, selected: selected) { action in
            onPick(action)
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func confirmDeleteTheme(id: String) {
        let alert = UIAlertController(
            title: "Delete Theme?",
            message: "This custom theme will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            self?.settings.deleteTheme(id: id)
        }))
        present(alert, animated: true)
    }
}

@MainActor
private final class TerminalThemeSelectionViewController: UITableViewController {
    private enum Item: Hashable {
        case preset(TerminalThemePreset)
        case custom(TerminalThemeCustom)
    }

    private let settings: TerminalSettingsStore

    init(settings: TerminalSettingsStore) {
        self.settings = settings
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Default Theme"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "theme-cell")
        startObserving()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        settings.state.customThemes.isEmpty ? 1 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if settings.state.customThemes.isEmpty { return "Built-in" }
        return section == 0 ? "Built-in" : "Custom"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if settings.state.customThemes.isEmpty {
            return TerminalThemePreset.all.count
        }
        return section == 0 ? TerminalThemePreset.all.count : settings.state.customThemes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "theme-cell", for: indexPath)
        var config = cell.defaultContentConfiguration()

        let item = itemAt(indexPath)
        switch item {
        case let .preset(preset):
            config.text = preset.name
        case let .custom(custom):
            config.text = custom.name
        }

        cell.contentConfiguration = config
        cell.accessoryType = isSelected(item) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        let item = itemAt(indexPath)

        switch item {
        case let .preset(preset):
            settings.setThemeSelection(.preset(id: preset.id))
        case let .custom(custom):
            settings.setThemeSelection(.custom(id: custom.id))
        }
    }

    private func itemAt(_ indexPath: IndexPath) -> Item {
        if settings.state.customThemes.isEmpty {
            return .preset(TerminalThemePreset.all[indexPath.row])
        }

        if indexPath.section == 0 {
            return .preset(TerminalThemePreset.all[indexPath.row])
        }
        return .custom(settings.state.customThemes[indexPath.row])
    }

    private func isSelected(_ item: Item) -> Bool {
        switch (item, settings.state.themeSelection) {
        case let (.preset(preset), .preset(id)):
            return preset.id == id
        case let (.custom(custom), .custom(id)):
            return custom.id == id
        default:
            return false
        }
    }

    private func startObserving() {
        withObservationTracking({ [weak self] in
            guard let self else { return }
            _ = self.settings.state
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startObserving()
                self.tableView.reloadData()
            }
        })
    }
}

@MainActor
private final class TerminalThemeEditorViewController: UIHostingController<TerminalThemeEditorScreen> {
    enum Mode {
        case create
        case edit(TerminalThemeCustom)

        var title: String {
            switch self {
            case .create: return "Create Theme"
            case .edit: return "Edit Theme"
            }
        }
    }

    init(settings: TerminalSettingsStore, mode: Mode) {
        super.init(rootView: TerminalThemeEditorScreen(settings: settings, mode: mode, onRequestClose: nil))
        var updated = rootView
        updated.onRequestClose = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        rootView = updated
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct TerminalThemeEditorScreen: View {
    @Environment(\.dismiss) private var dismiss

    let settings: TerminalSettingsStore
    let mode: TerminalThemeEditorViewController.Mode
    var onRequestClose: (() -> Void)?

    @State private var name: String
    @State private var background: Color
    @State private var foreground: Color
    @State private var cursor: Color
    @State private var selection: Color

    init(settings: TerminalSettingsStore, mode: TerminalThemeEditorViewController.Mode, onRequestClose: (() -> Void)?) {
        self.settings = settings
        self.mode = mode
        self.onRequestClose = onRequestClose

        let custom: TerminalThemeCustom = {
            switch mode {
            case .create:
                return TerminalThemeCustom(
                    id: UUID().uuidString,
                    name: "",
                    background: "#0D1117",
                    foreground: "#E6EDF3",
                    cursor: "#58A6FF",
                    selectionBackground: "#264F78"
                )
            case let .edit(existing):
                return existing
            }
        }()

        _name = State(initialValue: custom.name)
        _background = State(initialValue: Color(UIColor(hex: custom.background) ?? .black))
        _foreground = State(initialValue: Color(UIColor(hex: custom.foreground) ?? .white))
        _cursor = State(initialValue: Color(UIColor(hex: custom.cursor) ?? .systemBlue))
        _selection = State(initialValue: Color(UIColor(hex: custom.selectionBackground) ?? .systemGray))
    }

    var body: some View {
        Form {
            Section("Theme") {
                TextField("Theme Name", text: $name)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: UIFloat(10)) {
                    Text("ssh production\nLast login: today")
                        .font(.system(size: UIFloat(12), weight: .regular, design: .monospaced))
                        .foregroundStyle(foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("$ ./deploy.sh --env prod")
                        .font(.system(size: UIFloat(12), weight: .medium, design: .monospaced))
                        .foregroundStyle(cursor)
                        .padding(.horizontal, UIFloat(8))
                        .padding(.vertical, UIFloat(4))
                        .background(selection.opacity(0.32), in: RoundedRectangle(cornerRadius: UIFloat(6)))
                }
                .padding(UIFloat(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background, in: RoundedRectangle(cornerRadius: UIFloat(12)))
            }

            Section("Colors") {
                TerminalThemeColorRow(title: "Background", color: $background)
                TerminalThemeColorRow(title: "Foreground", color: $foreground)
                TerminalThemeColorRow(title: "Cursor", color: $cursor)
                TerminalThemeColorRow(title: "Selection", color: $selection)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func save() {
        let bgHex = UIColor(background).hexString
        let fgHex = UIColor(foreground).hexString
        let cursorHex = UIColor(cursor).hexString
        let selHex = UIColor(selection).hexString

        switch mode {
        case .create:
            settings.createTheme(
                name: name,
                background: bgHex,
                foreground: fgHex,
                cursor: cursorHex,
                selectionBackground: selHex
            )
        case let .edit(custom):
            settings.updateTheme(
                id: custom.id,
                name: name,
                background: bgHex,
                foreground: fgHex,
                cursor: cursorHex,
                selectionBackground: selHex
            )
        }
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }
}

private struct TerminalThemeColorRow: View {
    let title: String
    @Binding var color: Color

    var body: some View {
        LabeledContent(title) {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
        }
    }
}

@MainActor
private final class TerminalHardwareActionPickerViewController: UITableViewController {
    private let selected: TerminalHardwareAction
    private let onPick: (TerminalHardwareAction) -> Void

    init(title: String, selected: TerminalHardwareAction, onPick: @escaping (TerminalHardwareAction) -> Void) {
        self.selected = selected
        self.onPick = onPick
        super.init(style: .insetGrouped)
        navigationItem.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "action-cell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        TerminalHardwareAction.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "action-cell", for: indexPath)
        let action = TerminalHardwareAction.allCases[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = action.title
        cell.contentConfiguration = config
        cell.accessoryType = action == selected ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        let action = TerminalHardwareAction.allCases[indexPath.row]
        onPick(action)
        navigationController?.popViewController(animated: true)
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        let raw = hex.replacingOccurrences(of: "#", with: "")
        guard raw.count == 6,
              let value = Int(raw, radix: 16)
        else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        guard let components = cgColor.components else {
            return "#000000"
        }
        let red: Int
        let green: Int
        let blue: Int

        if components.count >= 3 {
            red = Int((components[0] * 255.0).rounded())
            green = Int((components[1] * 255.0).rounded())
            blue = Int((components[2] * 255.0).rounded())
        } else if components.count == 2 {
            let mono = Int((components[0] * 255.0).rounded())
            red = mono
            green = mono
            blue = mono
        } else {
            return "#000000"
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
