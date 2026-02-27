import Blackbird
import Observation
import SwiftUI
import UIKit

// MARK: - UI Scaling

@inlinable
func UIFloat(_ value: CGFloat) -> CGFloat {
#if os(macOS)
    return value * 0.92
#else
    return value
#endif
}

@inlinable
func UIFloat(_ value: Double) -> CGFloat {
    UIFloat(CGFloat(value))
}

@inlinable
func UIFloat(_ value: Int) -> CGFloat {
    UIFloat(CGFloat(value))
}

// MARK: - SwiftUI Host

struct RemoteTerminalView: View {
    var body: some View {
        TerminalWorkspaceNavigationHost()
            .ignoresSafeArea(.container, edges: .bottom)
            .trackView("terminal/workspace")
    }
}

#Preview(traits: .sampleData) {
    RemoteTerminalView()
}

private struct TerminalWorkspaceNavigationHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let root = TerminalWorkspaceViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = false
        return navigation
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let root = uiViewController.viewControllers.first as? TerminalWorkspaceViewController {
            root.refreshUI()
        }
    }
}

// MARK: - Shared UI Constants

private enum TerminalUIMetrics {
    static let pageInset = UIFloat(8)
    static let paneGap = UIFloat(8)
    static let paneInnerInset = UIFloat(6)
    static let paneCornerRadius = UIFloat(14)
    static let terminalCornerRadius = UIFloat(12)
    static let paneHeaderHeight = UIFloat(28)
    static let keyboardSuggestionHeight = UIFloat(34)
    static let keyboardSuggestionBottomGap = UIFloat(8)
    static let keyboardBarHeight = UIFloat(40)
    static let keyboardBarBottomInset = UIFloat(4)
    static let keyboardChipHorizontal = UIFloat(10)
    static let keyboardChipVertical = UIFloat(6)
    static let messageHorizontalInset = UIFloat(12)
    static let messageVerticalInset = UIFloat(8)
    static let messageTopSpacing = UIFloat(6)
    static let serverCellHeight = UIFloat(60)
    static let snippetCellHeight = UIFloat(72)
    static let sectionTopInset = UIFloat(8)
    static let sectionBottomInset = UIFloat(8)
    static let sectionSideInset = UIFloat(2)
}

private enum TerminalUIColors {
    static let workspaceBackground = UIColor.systemBackground
    static let paneMaterial = UIColor.secondarySystemBackground
    static let paneStroke = UIColor.separator
    static let focusedPaneStroke = UIColor.tintColor
    static let terminalBackground = UIColor.black
    static let secondaryText = UIColor.secondaryLabel
    static let keyboardKeyFill = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.secondarySystemFill
        }
        return UIColor.white.withAlphaComponent(0.92)
    }
    static let keyboardSuggestionFill = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.tertiarySystemFill
        }
        return UIColor.white.withAlphaComponent(0.82)
    }
    static let keyboardKeyActiveFill = UIColor.tintColor
    static let hintBackground = UIColor.black.withAlphaComponent(0.9)
}

private enum TerminalSplitAxis {
    case horizontal
    case vertical
}

// MARK: - CGRect Helpers

private extension CGRect {
    func split(at distance: CGFloat, from edge: CGRectEdge) -> (slice: CGRect, remainder: CGRect) {
        divided(atDistance: distance, from: edge)
    }
}

private func splitRect(_ rect: CGRect, count: Int, spacing: CGFloat, axis: TerminalSplitAxis) -> [CGRect] {
    guard count > 0 else { return [] }

    let totalSpacing = spacing * CGFloat(max(0, count - 1))
    let availableLength: CGFloat
    switch axis {
    case .horizontal:
        availableLength = max(UIFloat(0), rect.width - totalSpacing)
    case .vertical:
        availableLength = max(UIFloat(0), rect.height - totalSpacing)
    }

    var remaining = rect
    var result: [CGRect] = []
    let base = availableLength / CGFloat(count)

    for index in 0..<count {
        let isLast = index == count - 1
        let distance: CGFloat

        if isLast {
            switch axis {
            case .horizontal:
                distance = remaining.width
            case .vertical:
                distance = remaining.height
            }
        } else {
            distance = base
        }

        let split = remaining.split(at: distance, from: axis == .horizontal ? .minXEdge : .minYEdge)
        result.append(split.slice)

        if isLast {
            remaining = split.remainder
            continue
        }

        if spacing > 0 {
            let spacerSplit = split.remainder.split(at: spacing, from: axis == .horizontal ? .minXEdge : .minYEdge)
            remaining = spacerSplit.remainder
        } else {
            remaining = split.remainder
        }
    }

    return result
}

// MARK: - Workspace View Controller

@MainActor
final class TerminalWorkspaceViewController: UIViewController {
    private let workspace = TerminalWorkspaceStore.shared
    private let terminalManager = TerminalNavigationManager.shared
    private let hardwareInput = TerminalHardwareInputController()
    private let shakeInput = TerminalShakeInputController()
    private let settingsStore = TerminalSettingsStore.shared

    private enum InputConfirmationKeys {
        static let didConfirmVolumeInput = "terminal.hardware.confirmed.volume"
        static let didConfirmShakeInput = "terminal.hardware.confirmed.shake"
    }

    private let navigationTitleMenuButton = UIButton(type: .system)
    private let paneContainerView = UIView()
    private let keyboardBarView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let keyboardSuggestionsContainerView = UIView()
    private let keyboardControlsContainer = UIView()
    private let keyboardStackView = UIStackView()
    private let messageLabel = UILabel()

    private var paneControllers: [UUID: TerminalPaneViewController] = [:]

    private var keyboardVisible = false
    private var activeControllerIDForKeyboard: UUID?
    private var messageHideTask: Task<Void, Never>?
    private lazy var addBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "plus"),
        style: .plain,
        target: self,
        action: #selector(didTapAddPane)
    )
    private lazy var snippetBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "ellipsis.curlybraces"),
        style: .plain,
        target: self,
        action: #selector(didTapSnippets)
    )
    private lazy var settingsBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "gearshape"),
        style: .plain,
        target: self,
        action: #selector(didTapSettings)
    )

    private var keyboardButtons: [UIButton] = []
    private var keyboardSuggestionButtons: [UIButton] = []
    private var keyboardSuggestionDividers: [UIView] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        configureBaseUI()
        configureNavigationItems()
        configureKeyboardBar()
        installObservers()
        configureHardwareInputs()

        workspace.restoreWorkspace()
        refreshUI()
        processPendingRequests()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        configureHardwareInputs()
        refreshNavigationChrome()
        processPendingRequests()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hardwareInput.stop()
        shakeInput.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutWorkspaceViews()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.refreshUI()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Public Refresh

    func refreshUI() {
        syncPaneControllers()
        refreshNavigationChrome()
        updateKeyboardBarVisibility()
        view.setNeedsLayout()
    }

    // MARK: Setup

    private func configureBaseUI() {
        view.backgroundColor = TerminalUIColors.workspaceBackground

        paneContainerView.backgroundColor = .clear
        view.addSubview(paneContainerView)

        keyboardBarView.clipsToBounds = true
        keyboardBarView.layer.cornerRadius = UIFloat(14)
        keyboardBarView.layer.cornerCurve = .continuous
        keyboardBarView.layer.borderWidth = 0
        keyboardBarView.isHidden = true
        view.addSubview(keyboardBarView)

        keyboardControlsContainer.backgroundColor = .clear
        keyboardBarView.contentView.addSubview(keyboardControlsContainer)

        keyboardSuggestionsContainerView.backgroundColor = TerminalUIColors.keyboardSuggestionFill
        keyboardSuggestionsContainerView.layer.cornerRadius = UIFloat(14)
        keyboardSuggestionsContainerView.layer.cornerCurve = .continuous
        keyboardSuggestionsContainerView.clipsToBounds = true
        keyboardSuggestionsContainerView.layer.borderWidth = 0
        keyboardBarView.contentView.addSubview(keyboardSuggestionsContainerView)

        keyboardStackView.axis = .horizontal
        keyboardStackView.alignment = .fill
        keyboardStackView.distribution = .fill
        keyboardStackView.spacing = UIFloat(6)
        keyboardControlsContainer.addSubview(keyboardStackView)

        messageLabel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        messageLabel.textColor = UIColor.label
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .semibold)
        messageLabel.layer.cornerRadius = UIFloat(16)
        messageLabel.layer.cornerCurve = .continuous
        messageLabel.clipsToBounds = true
        messageLabel.isHidden = true
        view.addSubview(messageLabel)
    }

    private func configureNavigationItems() {
        navigationTitleMenuButton.showsMenuAsPrimaryAction = true
        navigationTitleMenuButton.tintColor = UIColor.label
        navigationTitleMenuButton.setTitleColor(UIColor.label, for: .normal)
        navigationTitleMenuButton.titleLabel?.numberOfLines = 1
        navigationTitleMenuButton.titleLabel?.lineBreakMode = .byTruncatingTail
        navigationTitleMenuButton.titleLabel?.adjustsFontSizeToFitWidth = true
        navigationTitleMenuButton.titleLabel?.minimumScaleFactor = 0.72
        navigationTitleMenuButton.titleLabel?.allowsDefaultTighteningForTruncation = true
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = UIColor.label
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = UIFloat(6)
        config.contentInsets = .zero
        config.titleLineBreakMode = .byTruncatingTail
        navigationTitleMenuButton.configuration = config

        navigationItem.titleView = navigationTitleMenuButton
        navigationItem.leftBarButtonItem = addBarButtonItem
        navigationItem.rightBarButtonItems = [snippetBarButtonItem, settingsBarButtonItem]
    }

    private func configureKeyboardBar() {
        keyboardButtons = TerminalKeyboardControl.allCases.map { control in
            let button = UIButton(type: .system)
            button.setTitle(control.title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .semibold)
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.lineBreakMode = .byClipping
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.8
            button.layer.cornerRadius = UIFloat(14)
            button.layer.cornerCurve = .continuous
            let insets = NSDirectionalEdgeInsets(
                top: TerminalUIMetrics.keyboardChipVertical,
                leading: TerminalUIMetrics.keyboardChipHorizontal,
                bottom: TerminalUIMetrics.keyboardChipVertical,
                trailing: TerminalUIMetrics.keyboardChipHorizontal
            )
            var config = UIButton.Configuration.plain()
            config.contentInsets = insets
            button.configuration = config
            button.backgroundColor = TerminalUIColors.keyboardKeyFill
            button.tintColor = UIColor.label
            button.setTitleColor(UIColor.label, for: .normal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.tag = control.rawValue
            button.addTarget(self, action: #selector(didTapKeyboardControl(_:)), for: .touchUpInside)
            keyboardStackView.addArrangedSubview(button)
            return button
        }
    }

    private func installObservers() {
        startWorkspaceObservation()
        startKeyboardControllerObservation()
        startSettingsObservation()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShowOrChange(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShowOrChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenRequestNotification),
            name: .terminalOpenRequestsDidChange,
            object: nil
        )
    }

    // MARK: Observation

    private func startWorkspaceObservation() {
        withObservationTracking({ [weak self] in
            guard let self else { return }
            _ = self.workspace.panes
            _ = self.workspace.focusedPaneID
            _ = self.workspace.tabs
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.startWorkspaceObservation()
                self?.refreshUI()
            }
        })
    }

    private func startKeyboardControllerObservation() {
        withObservationTracking({ [weak self] in
            guard let self else { return }
            _ = self.workspace.focusedPaneID
            _ = self.workspace.activeControllerInFocusedPane()?.id
            _ = self.workspace.activeControllerInFocusedPane()?.controlModifierArmed
            _ = self.workspace.activeControllerInFocusedPane()?.suggestions
            _ = self.workspace.activeControllerInFocusedPane()?.currentInputBuffer
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.startKeyboardControllerObservation()
                self?.updateKeyboardButtonsState()
                self?.updateKeyboardBarVisibility()
            }
        })
    }

    private func startSettingsObservation() {
        withObservationTracking({ [weak self] in
            guard let self else { return }
            _ = self.settingsStore.state
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startSettingsObservation()
                self.configureHardwareInputs()
                self.applySettingsToAllVisiblePanes()
            }
        })
    }

    // MARK: Navigation UI

    private func refreshNavigationChrome() {
        let title = titleTextForFocusedPane()
        if var navigationConfig = navigationTitleMenuButton.configuration {
            navigationConfig.title = title
            navigationTitleMenuButton.configuration = navigationConfig
        } else {
            navigationTitleMenuButton.setTitle(title, for: .normal)
        }

        let titleMenu = makeTitleMenu()
        navigationTitleMenuButton.menu = titleMenu

    }

    private func titleTextForFocusedPane() -> String {
        guard let focusedID = workspace.focusedPaneID,
              let index = workspace.panes.firstIndex(where: { $0.id == focusedID })
        else {
            return "Terminal"
        }

        if let active = workspace.activeTab(in: focusedID) {
            return "\(index + 1): \(active.title)"
        }

        return "\(index + 1)"
    }

    private func makeTitleMenu() -> UIMenu {
        var actions: [UIMenuElement] = [
            UIAction(title: "New Tab", image: UIImage(systemName: "plus")) { [weak self] _ in
                self?.workspace.focusOrCreateEmptyPane()
            }
        ]

        if !workspace.panes.isEmpty {
            actions.append(UIMenu(title: "", options: .displayInline, children: paneSwitchActions()))
        }

        return UIMenu(children: actions)
    }

    private func paneSwitchActions() -> [UIAction] {
        let selectedPaneID = workspace.focusedPaneID ?? workspace.panes.first?.id

        return workspace.panes.enumerated().map { index, pane in
            let isSelected = pane.id == selectedPaneID
            let title = "Tab \(index + 1)"
            return UIAction(
                title: title,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.workspace.focusPane(paneID: pane.id)
            }
        }
    }

    // MARK: Layout

    private func layoutWorkspaceViews() {
        let insets = view.safeAreaInsets
        var layoutRect = view.bounds.inset(by: UIEdgeInsets(
            top: insets.top + TerminalUIMetrics.pageInset,
            left: TerminalUIMetrics.pageInset,
            bottom: insets.bottom + TerminalUIMetrics.pageInset,
            right: TerminalUIMetrics.pageInset
        ))

        if !messageLabel.isHidden {
            let messageHeight = UIFloat(32)
            let split = layoutRect.split(at: messageHeight + TerminalUIMetrics.messageTopSpacing, from: .minYEdge)
            let available = split.slice
            messageLabel.frame = available.inset(by: UIEdgeInsets(
                top: TerminalUIMetrics.messageTopSpacing,
                left: TerminalUIMetrics.messageHorizontalInset,
                bottom: 0,
                right: TerminalUIMetrics.messageHorizontalInset
            ))
            layoutRect = split.remainder
        } else {
            messageLabel.frame = .zero
        }

        if shouldShowKeyboardBar {
            let hasSuggestions = !keyboardSuggestionButtons.isEmpty
            let suggestionHeight = hasSuggestions ? (TerminalUIMetrics.keyboardSuggestionHeight + TerminalUIMetrics.keyboardSuggestionBottomGap) : UIFloat(0)
            let barHeight = TerminalUIMetrics.keyboardBarHeight + TerminalUIMetrics.keyboardBarBottomInset + suggestionHeight
            let split = layoutRect.split(at: barHeight, from: .maxYEdge)
            keyboardBarView.frame = split.slice
            let contentBounds = keyboardBarView.bounds.inset(by: UIEdgeInsets(
                top: UIFloat(4),
                left: UIFloat(6),
                bottom: UIFloat(4),
                right: UIFloat(6)
            ))
            if hasSuggestions {
                let suggestionSplit = contentBounds.split(at: TerminalUIMetrics.keyboardSuggestionHeight, from: .minYEdge)
                keyboardSuggestionsContainerView.frame = suggestionSplit.slice
                let controlsRect = suggestionSplit.remainder.inset(by: UIEdgeInsets(
                    top: TerminalUIMetrics.keyboardSuggestionBottomGap,
                    left: 0,
                    bottom: 0,
                    right: 0
                ))
                keyboardControlsContainer.frame = controlsRect
            } else {
                keyboardSuggestionsContainerView.frame = .zero
                keyboardControlsContainer.frame = contentBounds
            }
            keyboardStackView.frame = keyboardControlsContainer.bounds
            layoutKeyboardSuggestions(in: keyboardSuggestionsContainerView.bounds)
            layoutRect = split.remainder
        } else {
            keyboardBarView.frame = .zero
            keyboardSuggestionsContainerView.frame = .zero
            keyboardControlsContainer.frame = .zero
        }

        paneContainerView.frame = layoutRect
        layoutPaneControllers(in: paneContainerView.bounds)
    }

    private func layoutPaneControllers(in bounds: CGRect) {
        let visiblePaneIDs = workspace.visiblePaneIDs(isRegularWidth: isRegularLayout)
        let visibleControllers: [TerminalPaneViewController] = visiblePaneIDs.compactMap { paneControllers[$0] }

        guard !visibleControllers.isEmpty else { return }

        if isRegularLayout {
            let rowCount = Int(ceil(Double(visibleControllers.count) / 2.0))
            let rowRects = splitRect(bounds, count: rowCount, spacing: TerminalUIMetrics.paneGap, axis: .vertical)

            var index = 0
            for row in 0..<rowCount {
                let remaining = visibleControllers.count - index
                let columns = min(2, remaining)
                let columnRects = splitRect(rowRects[row], count: columns, spacing: TerminalUIMetrics.paneGap, axis: .horizontal)

                for columnRect in columnRects {
                    guard index < visibleControllers.count else { continue }
                    visibleControllers[index].view.frame = columnRect
                    index += 1
                }
            }
            return
        }

        if let first = visibleControllers.first {
            first.view.frame = bounds
        }
    }

    private var isRegularLayout: Bool {
        traitCollection.horizontalSizeClass == .regular
    }

    // MARK: Pane Sync

    private func syncPaneControllers() {
        let visiblePaneIDs = Set(workspace.visiblePaneIDs(isRegularWidth: isRegularLayout))

        let idsToRemove = Set(paneControllers.keys).subtracting(visiblePaneIDs)
        for paneID in idsToRemove {
            guard let controller = paneControllers[paneID] else { continue }
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            paneControllers[paneID] = nil
        }

        let orderedVisibleIDs = workspace.visiblePaneIDs(isRegularWidth: isRegularLayout)
        for paneID in orderedVisibleIDs {
            let controller: TerminalPaneViewController

            if let existing = paneControllers[paneID] {
                controller = existing
            } else {
                let created = TerminalPaneViewController(paneID: paneID, workspace: workspace)
                created.delegate = self
                addChild(created)
                paneContainerView.addSubview(created.view)
                created.didMove(toParent: self)
                paneControllers[paneID] = created
                controller = created
            }

            controller.refreshFromWorkspace()
            controller.applyDisplaySettings(fontSize: settingsStore.state.display.fontSize)
        }

        for paneID in orderedVisibleIDs {
            if let paneView = paneControllers[paneID]?.view {
                paneContainerView.bringSubviewToFront(paneView)
            }
        }
    }

    // MARK: Message

    private func showMessage(_ text: String) {
        messageHideTask?.cancel()
        messageLabel.text = text
        messageLabel.isHidden = false
        messageLabel.alpha = 1
        view.setNeedsLayout()

        messageHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                guard let self else { return }
                UIView.animate(withDuration: 0.2, animations: {
                    self.messageLabel.alpha = 0
                }, completion: { _ in
                    self.messageLabel.alpha = 1
                    self.messageLabel.isHidden = true
                    self.view.setNeedsLayout()
                })
            }
        }
    }

    // MARK: Keyboard Bar

    private var shouldShowKeyboardBar: Bool {
        keyboardVisible && workspace.activeControllerInFocusedPane() != nil
    }

    private func updateKeyboardBarVisibility() {
        updateKeyboardSuggestionButtons()
        keyboardBarView.isHidden = !shouldShowKeyboardBar
        updateKeyboardButtonsState()
        view.setNeedsLayout()
    }

    private func updateKeyboardSuggestionButtons() {
        let wasVisible = !keyboardSuggestionButtons.isEmpty

        guard let controller = workspace.activeControllerInFocusedPane() else {
            setKeyboardSuggestionButtons([], typedInput: "")
            animateSuggestionBarVisibilityIfNeeded(
                wasVisible: wasVisible,
                isVisible: !keyboardSuggestionButtons.isEmpty
            )
            return
        }

        setKeyboardSuggestionButtons(
            Array(controller.suggestions.prefix(3)),
            typedInput: controller.currentInputBuffer
        )
        animateSuggestionBarVisibilityIfNeeded(
            wasVisible: wasVisible,
            isVisible: !keyboardSuggestionButtons.isEmpty
        )
    }

    private func updateKeyboardButtonsState() {
        guard let controller = workspace.activeControllerInFocusedPane() else {
            for button in keyboardButtons {
                button.backgroundColor = TerminalUIColors.keyboardKeyFill
                button.setTitleColor(UIColor.label, for: .normal)
            }
            return
        }

        activeControllerIDForKeyboard = controller.id

        for button in keyboardButtons {
            guard let control = TerminalKeyboardControl(rawValue: button.tag) else { continue }
            let isActive = control == .control && controller.controlModifierArmed
            button.backgroundColor = isActive ? TerminalUIColors.keyboardKeyActiveFill : TerminalUIColors.keyboardKeyFill
            button.setTitleColor(isActive ? UIColor.white : UIColor.label, for: .normal)
        }
    }

    private func configureHardwareInputs() {
        let hardware = settingsStore.state.hardware

        if hardware.volumeEnabled {
            hardwareInput.start(
                onVolumeDown: { [weak self] in
                    self?.handleVolumeButton(action: hardware.volumeDownAction)
                },
                onVolumeUp: { [weak self] in
                    self?.handleVolumeButton(action: hardware.volumeUpAction)
                }
            )
        } else {
            hardwareInput.stop()
        }

        if hardware.shakeEnabled {
            shakeInput.start(in: view) { [weak self] in
                self?.handleShake(action: hardware.shakeAction)
            }
        } else {
            shakeInput.stop()
        }
    }

    private func handleVolumeButton(action: TerminalHardwareAction) {
        confirmFirstUseIfNeeded(
            key: InputConfirmationKeys.didConfirmVolumeInput,
            title: "Enable Volume Button Shortcuts?",
            message: "Volume button presses will trigger terminal actions instead of only changing volume while this screen is active."
        ) { [weak self] in
            self?.performHardwareAction(action)
        }
    }

    private func handleShake(action: TerminalHardwareAction) {
        confirmFirstUseIfNeeded(
            key: InputConfirmationKeys.didConfirmShakeInput,
            title: "Enable Shake Shortcut?",
            message: "Shake gestures will trigger terminal actions while this screen is active."
        ) { [weak self] in
            self?.performHardwareAction(action)
        }
    }

    private func confirmFirstUseIfNeeded(
        key: String,
        title: String,
        message: String,
        onConfirm: @escaping () -> Void
    ) {
        if UserDefaults.standard.bool(forKey: key) {
            onConfirm()
            return
        }

        if presentedViewController != nil {
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Allow", style: .default, handler: { _ in
            UserDefaults.standard.set(true, forKey: key)
            onConfirm()
        }))
        present(alert, animated: true)
    }

    private func performHardwareAction(_ action: TerminalHardwareAction) {
        guard let controller = workspace.activeControllerInFocusedPane() else {
            return
        }

        switch action {
        case .arrowUp:
            controller.sendArrowUp()
        case .arrowDown:
            controller.sendArrowDown()
        case .arrowLeft:
            controller.sendArrowLeft()
        case .arrowRight:
            controller.sendArrowRight()
        case .tab:
            controller.sendTabKey()
        case .enter:
            controller.sendEnter()
        case .escape:
            controller.sendEscape()
        case .ctrlToggle:
            controller.toggleControlModifier()
            updateKeyboardButtonsState()
        case .pageUp:
            controller.sendPageUp()
        case .pageDown:
            controller.sendPageDown()
        case .interrupt:
            controller.sendInterrupt()
        }

        controller.focus()
    }

    private func applySettingsToAllVisiblePanes() {
        let state = settingsStore.state
        for pane in paneControllers.values {
            pane.applyDisplaySettings(fontSize: state.display.fontSize)
        }
    }

    private func setKeyboardSuggestionButtons(_ suggestions: [CommandSuggestion], typedInput: String) {
        for button in keyboardSuggestionButtons {
            button.removeFromSuperview()
        }
        keyboardSuggestionButtons.removeAll(keepingCapacity: false)
        for divider in keyboardSuggestionDividers {
            divider.removeFromSuperview()
        }
        keyboardSuggestionDividers.removeAll(keepingCapacity: false)

        for (index, suggestion) in suggestions.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(displaySuggestionText(suggestion.text, typedInput: typedInput), for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .medium)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.8
            button.contentHorizontalAlignment = .center
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(
                top: UIFloat(6),
                leading: UIFloat(8),
                bottom: UIFloat(6),
                trailing: UIFloat(8)
            )
            button.configuration = config
            button.layer.cornerRadius = 0
            button.setTitleColor(UIColor.label, for: .normal)
            button.backgroundColor = .clear
            button.accessibilityLabel = suggestion.text
            button.addAction(UIAction(handler: { [weak self] _ in
                guard let self, let controller = self.workspace.activeControllerInFocusedPane() else { return }
                controller.applySuggestion(suggestion.text)
                controller.focus()
            }), for: .touchUpInside)
            keyboardSuggestionsContainerView.addSubview(button)
            keyboardSuggestionButtons.append(button)

            if index < suggestions.count - 1 {
                let divider = UIView()
                divider.backgroundColor = UIColor.separator.withAlphaComponent(0.6)
                keyboardSuggestionsContainerView.addSubview(divider)
                keyboardSuggestionDividers.append(divider)
            }
        }
    }

    private func layoutKeyboardSuggestions(in bounds: CGRect) {
        guard !keyboardSuggestionButtons.isEmpty else { return }
        let suggestionRects = splitRect(bounds, count: keyboardSuggestionButtons.count, spacing: 0, axis: .horizontal)
        for (index, button) in keyboardSuggestionButtons.enumerated() {
            button.frame = suggestionRects[index]
        }
        for (index, divider) in keyboardSuggestionDividers.enumerated() {
            let rect = suggestionRects[index]
            divider.frame = CGRect(
                x: rect.maxX - 0.5,
                y: UIFloat(6),
                width: 1,
                height: max(0, bounds.height - UIFloat(12))
            )
        }
    }

    private func displaySuggestionText(_ suggestion: String, typedInput: String) -> String {
        let trimmedLeading = typedInput.trimmingCharacters(in: .newlines)
        guard !trimmedLeading.isEmpty else { return suggestion }

        let hasTrailingSpace = typedInput.last?.isWhitespace == true
        let typedWords = trimmedLeading.split(whereSeparator: \.isWhitespace).map(String.init)
        let fullWordCount = hasTrailingSpace ? typedWords.count : max(typedWords.count - 1, 0)
        guard fullWordCount > 0 else { return suggestion }

        let fullWords = Array(typedWords.prefix(fullWordCount))
        let suggestionWords = suggestion.split(whereSeparator: \.isWhitespace).map(String.init)
        guard suggestionWords.count > fullWords.count else { return suggestion }

        for (index, fullWord) in fullWords.enumerated() {
            if suggestionWords[index].lowercased() != fullWord.lowercased() {
                return suggestion
            }
        }

        let trimmed = suggestionWords.dropFirst(fullWords.count).joined(separator: " ")
        return trimmed.isEmpty ? suggestion : trimmed
    }

    private func animateSuggestionBarVisibilityIfNeeded(wasVisible: Bool, isVisible: Bool) {
        guard wasVisible != isVisible else { return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut]) {
            self.layoutWorkspaceViews()
        }
    }

    // MARK: Terminal Requests

    private func processPendingRequests() {
        let requests = terminalManager.dequeueAllRequests()
        guard !requests.isEmpty else { return }

        for request in requests {
            workspace.openTab(credentialKey: request.credentialKey, inFocusedPane: true)
            showMessage("Connected to \(request.label)")
        }

        terminalManager.showingDeeplinkConfirmation = false
    }

    // MARK: Actions

    @objc
    private func didTapAddPane() {
        workspace.focusOrCreateEmptyPane()
    }

    @objc
    private func didTapSnippets() {
        let currentCredentialKey = workspace.activeControllerInFocusedPane()?.credentialKey
        let picker = TerminalSnippetPickerViewController(
            database: SharedDatabase.db,
            credentialKey: currentCredentialKey
        ) { [weak self] snippet in
            self?.workspace.activeControllerInFocusedPane()?.applySuggestion(snippet.command)
        }

        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    @objc
    private func didTapSettings() {
        let settings = TerminalSettingsViewController()
        let navigation = UINavigationController(rootViewController: settings)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    @objc
    private func didTapKeyboardControl(_ sender: UIButton) {
        guard let control = TerminalKeyboardControl(rawValue: sender.tag),
              let controller = workspace.activeControllerInFocusedPane()
        else {
            return
        }

        switch control {
        case .control:
            controller.toggleControlModifier()
        case .escape:
            controller.sendEscape()
        case .tab:
            controller.sendTabKey()
        case .left:
            controller.sendArrowLeft()
        case .right:
            controller.sendArrowRight()
        case .up:
            controller.sendArrowUp()
        case .down:
            controller.sendArrowDown()
        }

        controller.focus()
        updateKeyboardButtonsState()
    }

    @objc
    private func keyboardWillShowOrChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            keyboardVisible = true
            updateKeyboardBarVisibility()
            return
        }

        let fallbackScreenHeight = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .bounds
            .height ?? UIFloat(0)
        let screenHeight = view.window?.windowScene?.screen.bounds.height ?? fallbackScreenHeight
        keyboardVisible = frame.minY < screenHeight
        updateKeyboardBarVisibility()
    }

    @objc
    private func keyboardWillHide(_ notification: Notification) {
        keyboardVisible = false
        updateKeyboardBarVisibility()
    }

    @objc
    private func handleOpenRequestNotification() {
        processPendingRequests()
    }
}

// MARK: - Workspace Delegate

extension TerminalWorkspaceViewController: TerminalPaneViewControllerDelegate {
    func terminalPane(_ pane: TerminalPaneViewController, didRequestMessage message: String) {
        showMessage(message)
    }
}

// MARK: - Keyboard Controls

private enum TerminalKeyboardControl: Int, CaseIterable {
    case control
    case escape
    case tab
    case left
    case right
    case up
    case down

    var title: String {
        switch self {
        case .control:
            return "Ctrl"
        case .escape:
            return "Esc"
        case .tab:
            return "Tab"
        case .left:
            return "←"
        case .right:
            return "→"
        case .up:
            return "↑"
        case .down:
            return "↓"
        }
    }
}

// MARK: - Pane View Controller

@MainActor
protocol TerminalPaneViewControllerDelegate: AnyObject {
    func terminalPane(_ pane: TerminalPaneViewController, didRequestMessage message: String)
}

@MainActor
final class TerminalPaneViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: TerminalPaneViewControllerDelegate?

    private let paneID: UUID
    private let workspace: TerminalWorkspaceStore
    private let settingsStore = TerminalSettingsStore.shared

    private let panelView = UIView()
    private let headerView = UIView()
    private let contentView = UIView()

    private let tabTitleLabel = UILabel()
    private let activeTitleLabel = UILabel()
    private let cwdLabel = UILabel()
    private let warningImageView = UIImageView()
    private let closeButton = UIButton(type: .system)

    private var activeHostView: XTermWebHostView?
    private var serverPickerController: TerminalServerPickerViewController?
    private var observedControllerID: UUID?
    private var lastPresentedPromptID: UUID?
    private var pinchBaseFontSize: Int = 13
    private var pinchLastDeltaSteps = 0

    init(paneID: UUID, workspace: TerminalWorkspaceStore) {
        self.paneID = paneID
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePaneUI()
        refreshFromWorkspace()

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapPane))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        view.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinchTerminal(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPaneViews()
    }

    // MARK: Setup

    private func configurePaneUI() {
        view.backgroundColor = .clear

        panelView.backgroundColor = TerminalUIColors.paneMaterial
        panelView.layer.cornerRadius = TerminalUIMetrics.paneCornerRadius
        panelView.layer.cornerCurve = .continuous
        panelView.layer.borderWidth = UIFloat(1)
        panelView.layer.borderColor = TerminalUIColors.paneStroke.cgColor
        view.addSubview(panelView)

        headerView.backgroundColor = .clear
        panelView.addSubview(headerView)

        contentView.backgroundColor = .clear
        panelView.addSubview(contentView)

        tabTitleLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .semibold)
        tabTitleLabel.textColor = TerminalUIColors.secondaryText
        headerView.addSubview(tabTitleLabel)

        activeTitleLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .regular)
        activeTitleLabel.textColor = TerminalUIColors.secondaryText
        activeTitleLabel.lineBreakMode = .byTruncatingTail
        headerView.addSubview(activeTitleLabel)

        cwdLabel.font = UIFont.systemFont(ofSize: UIFloat(11), weight: .regular)
        cwdLabel.textColor = TerminalUIColors.secondaryText
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        headerView.addSubview(cwdLabel)

        warningImageView.image = UIImage(systemName: "exclamationmark.triangle.fill")
        warningImageView.tintColor = UIColor.systemYellow
        warningImageView.contentMode = .scaleAspectFit
        warningImageView.isHidden = true
        headerView.addSubview(warningImageView)

        closeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        closeButton.tintColor = UIColor.secondaryLabel
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        headerView.addSubview(closeButton)
    }

    // MARK: Refresh

    func refreshFromWorkspace() {
        let focused = workspace.focusedPaneID == paneID
        let activeTab = workspace.activeTab(in: paneID)
        applyPaneBorderStyle(focused: focused, activeTab: activeTab)

        let tabNumber = (workspace.panes.firstIndex(where: { $0.id == paneID }) ?? 0) + 1
        tabTitleLabel.text = "Tab \(tabNumber)"

        guard let activeTab,
              let controller = workspace.controller(for: activeTab.id)
        else {
            observedControllerID = nil
            activeTitleLabel.text = "Choose a server"
            cwdLabel.text = ""
            warningImageView.isHidden = true
            closeButton.isHidden = true
            showServerPicker()
            view.setNeedsLayout()
            return
        }

        closeButton.isHidden = false
        activeTitleLabel.text = activeTab.title
        cwdLabel.text = controller.cwd
        warningImageView.isHidden = controller.shellIntegrationStatus != .warning

        showTerminalHost(for: controller)
        observeControllerIfNeeded(controller)
        presentPendingPromptIfNeeded(controller)

        view.setNeedsLayout()
    }

    // MARK: Observation

    private func observeControllerIfNeeded(_ controller: XTermSessionController) {
        guard observedControllerID != controller.id else { return }
        observedControllerID = controller.id

        withObservationTracking({ [weak self] in
            guard let self else { return }
            _ = controller.cwd
            _ = controller.shellIntegrationStatus
            _ = controller.suggestions
            _ = controller.pendingSFTPEditPrompt
            _ = self.workspace.focusedPaneID
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.workspace.controller(for: controller.id) != nil {
                    self.observeControllerIfNeeded(controller)
                }
                self.refreshFromWorkspace()
            }
        })
    }

    // MARK: Layout

    private func layoutPaneViews() {
        panelView.frame = view.bounds.inset(by: UIEdgeInsets(
            top: TerminalUIMetrics.paneInnerInset,
            left: TerminalUIMetrics.paneInnerInset,
            bottom: TerminalUIMetrics.paneInnerInset,
            right: TerminalUIMetrics.paneInnerInset
        ))

        var inner = panelView.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(8),
            left: UIFloat(8),
            bottom: UIFloat(8),
            right: UIFloat(8)
        ))

        let headerSplit = inner.split(at: TerminalUIMetrics.paneHeaderHeight, from: .minYEdge)
        headerView.frame = headerSplit.slice
        inner = headerSplit.remainder

        contentView.frame = inner

        layoutHeaderViews(in: headerView.bounds)
        activeHostView?.frame = contentView.bounds
        serverPickerController?.view.frame = contentView.bounds
    }

    private func layoutHeaderViews(in bounds: CGRect) {
        var headerRect = bounds

        let trailingWidth = UIFloat(28)
        let closeSplit = headerRect.split(at: trailingWidth, from: .maxXEdge)
        closeButton.frame = closeSplit.slice
        headerRect = closeSplit.remainder

        let warningSplit = headerRect.split(at: UIFloat(22), from: .maxXEdge)
        warningImageView.frame = warningSplit.slice.insetBy(dx: UIFloat(3), dy: UIFloat(5))
        headerRect = warningSplit.remainder

        let tabSplit = headerRect.split(at: UIFloat(56), from: .minXEdge)
        tabTitleLabel.frame = tabSplit.slice

        var middle = tabSplit.remainder
        let cwdSplit = middle.split(at: UIFloat(90), from: .maxXEdge)
        cwdLabel.frame = cwdSplit.slice
        middle = cwdSplit.remainder

        activeTitleLabel.frame = middle
    }

    // MARK: Content Switching

    private func showServerPicker() {
        activeHostView?.removeFromSuperview()
        activeHostView = nil

        if let picker = serverPickerController {
            picker.reloadCredentials()
            return
        }

        let picker = TerminalServerPickerViewController()
        picker.onShortcutSelected = { [weak self] shortcut in
            guard let self else { return }
            self.workspace.focusPane(paneID: self.paneID)
            self.workspace.openTab(
                credentialKey: shortcut.credentialKey,
                preferredTitle: shortcut.title,
                inFocusedPane: true,
                themeOverrideSelectionKey: shortcut.themeSelectionKey,
                shortcutColorHex: shortcut.colorHex
            )
            self.launchStartupScriptIfNeeded(shortcut.startupScript, credentialKey: shortcut.credentialKey)
        }
        addChild(picker)
        contentView.addSubview(picker.view)
        picker.didMove(toParent: self)
        serverPickerController = picker
    }

    private func showTerminalHost(for controller: XTermSessionController) {
        if let picker = serverPickerController {
            picker.willMove(toParent: nil)
            picker.view.removeFromSuperview()
            picker.removeFromParent()
            serverPickerController = nil
        }

        let host = controller.makeOrReuseHostView()
        let initialTheme = effectiveThemePayload()
        host.backgroundColor = UIColor(terminalHex: initialTheme["background"]) ?? TerminalUIColors.terminalBackground
        host.layer.cornerRadius = TerminalUIMetrics.terminalCornerRadius
        host.layer.cornerCurve = .continuous
        host.clipsToBounds = true

        if host.superview !== contentView {
            activeHostView?.removeFromSuperview()
            contentView.addSubview(host)
            activeHostView = host
        } else {
            activeHostView = host
        }

        applyDisplaySettings(
            fontSize: settingsStore.state.display.fontSize
        )
    }

    func applyDisplaySettings(fontSize: Int) {
        let themePayload = effectiveThemePayload()
        if let themedBackground = UIColor(terminalHex: themePayload["background"]) {
            activeHostView?.backgroundColor = themedBackground
        }
        activeHostView?.setTheme(themePayload)
        activeHostView?.setFontSize(fontSize)
    }

    private func launchStartupScriptIfNeeded(_ script: String, credentialKey: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task { [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self else { return }
                guard let controller = self.workspace.activeControllerInFocusedPane() else { continue }
                guard controller.credentialKey == credentialKey else { continue }
                guard controller.connectionStatus == .connected else { continue }

                controller.sendInput(trimmed)
                controller.sendEnter()
                controller.focus()
                return
            }
        }
    }

    private func effectiveThemePayload() -> [String: String] {
        guard let activeTab = workspace.activeTab(in: paneID),
              let key = activeTab.themeOverrideSelectionKey,
              let selection = settingsStore.themeSelection(from: key)
        else {
            return settingsStore.resolvedTheme.payload
        }
        return settingsStore.resolvedTheme(for: selection).payload
    }

    private func applyPaneBorderStyle(focused: Bool, activeTab: TerminalTabState?) {
        if let colorHex = activeTab?.shortcutColorHex,
           let shortcutColor = UIColor(hex: colorHex)
        {
            panelView.layer.borderColor = shortcutColor.cgColor
            panelView.layer.borderWidth = UIFloat(3)
            return
        }

        panelView.layer.borderColor = (focused ? TerminalUIColors.focusedPaneStroke : TerminalUIColors.paneStroke).cgColor
        panelView.layer.borderWidth = UIFloat(1)
    }

    // MARK: Prompt Handling

    private func presentPendingPromptIfNeeded(_ controller: XTermSessionController) {
        guard let prompt = controller.pendingSFTPEditPrompt else {
            lastPresentedPromptID = nil
            return
        }

        guard prompt.id != lastPresentedPromptID else { return }
        lastPresentedPromptID = prompt.id

        let alert = UIAlertController(
            title: "Open in SFTP editor?",
            message: "Detected \(prompt.command) for \(prompt.path). Open in SFTP editor instead?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Open in SFTP Editor", style: .default, handler: { _ in
            controller.openPendingFileInSFTP()
            self.delegate?.terminalPane(self, didRequestMessage: "Opening file in SFTP editor")
        }))

        alert.addAction(UIAlertAction(title: "Never show again", style: .destructive, handler: { _ in
            controller.dismissPendingSFTPEditPrompt(neverShowAgain: true)
        }))

        alert.addAction(UIAlertAction(title: "Continue in Terminal", style: .cancel, handler: { _ in
            controller.continuePendingSFTPEditInTerminal()
        }))

        present(alert, animated: true)
    }

    // MARK: Actions

    @objc
    private func didTapPane() {
        workspace.focusPane(paneID: paneID)

        if let active = workspace.activeTab(in: paneID),
           let controller = workspace.controller(for: active.id) {
            controller.focus()
        }
    }

    @objc
    private func didTapClose() {
        guard let active = workspace.activeTab(in: paneID) else { return }
        workspace.closeTab(tabID: active.id)
    }

    @objc
    private func didPinchTerminal(_ recognizer: UIPinchGestureRecognizer) {
        guard activeHostView != nil else { return }

        switch recognizer.state {
        case .began:
            pinchBaseFontSize = settingsStore.state.display.fontSize
            pinchLastDeltaSteps = 0
        case .changed:
            let scaledDelta = (recognizer.scale - 1.0) * 8.0
            let deltaSteps = Int(scaledDelta.rounded(.towardZero))
            guard deltaSteps != pinchLastDeltaSteps else { return }
            pinchLastDeltaSteps = deltaSteps
            let step = max(1, settingsStore.state.display.step)
            settingsStore.setFontSize(pinchBaseFontSize + (deltaSteps * step))
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UIPinchGestureRecognizer {
            return true
        }
        var candidate = touch.view
        while let current = candidate {
            if current is UIControl || current is UICollectionView || current is UICollectionViewCell {
                return false
            }
            candidate = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
    }
}

private extension UIColor {
    convenience init?(terminalHex: String?) {
        guard let terminalHex else { return nil }
        let raw = terminalHex.replacingOccurrences(of: "#", with: "")
        guard raw.count == 6,
              let value = Int(raw, radix: 16)
        else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: - Server Picker

@MainActor
final class TerminalServerPickerViewController: UIViewController {
    var onShortcutSelected: ((TerminalLaunchShortcut) -> Void)?

    private enum Section: Int, CaseIterable {
        case main
    }

    private struct Item: Hashable {
        let shortcutID: String
        let credentialKey: String
        let title: String
        let host: String
        let startupScript: String
        let colorHex: String
    }

    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private let emptyStateLabel = UILabel()
    private let addShortcutButton = UIButton(type: .system)

    private var items: [Item] = []

    init() {
        let layout = TerminalServerPickerViewController.makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        reloadCredentials()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let buttonSize = CGSize(width: UIFloat(42), height: UIFloat(42))
        addShortcutButton.frame = CGRect(
            x: view.bounds.maxX - buttonSize.width - UIFloat(12),
            y: view.bounds.maxY - buttonSize.height - UIFloat(12),
            width: buttonSize.width,
            height: buttonSize.height
        )
        collectionView.frame = view.bounds
        emptyStateLabel.frame = view.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(10),
            left: UIFloat(14),
            bottom: UIFloat(10),
            right: UIFloat(14)
        ))
    }

    // MARK: Setup

    private func configureUI() {
        view.backgroundColor = .clear

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.alwaysBounceHorizontal = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.allowsSelection = true
        collectionView.register(TerminalServerCell.self, forCellWithReuseIdentifier: TerminalServerCell.reuseID)
        collectionView.delegate = self
        view.addSubview(collectionView)

        addShortcutButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addShortcutButton.tintColor = .white
        addShortcutButton.backgroundColor = .systemBlue
        addShortcutButton.layer.cornerRadius = UIFloat(21)
        addShortcutButton.layer.cornerCurve = .continuous
        addShortcutButton.addTarget(self, action: #selector(didTapAddShortcut), for: .touchUpInside)
        view.addSubview(addShortcutButton)

        emptyStateLabel.text = "No shortcuts yet"
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.font = UIFont.systemFont(ofSize: UIFloat(14), weight: .medium)
        emptyStateLabel.textColor = UIColor.secondaryLabel
        emptyStateLabel.numberOfLines = 2
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)
    }

    // MARK: Data

    func reloadCredentials() {
        Task {
            let credentials = keychain()
                .allKeys()
                .compactMap { keychain().getCredential(for: $0) }
                .sorted { lhs, rhs in
                    lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }

            for credential in credentials {
                await TerminalLaunchShortcut.ensureDefaultShortcutIfNeeded(for: credential, in: SharedDatabase.db)
            }

            let shortcuts = await TerminalLaunchShortcut.all(in: SharedDatabase.db)
            let credentialMap = Dictionary(uniqueKeysWithValues: credentials.map { ($0.key, $0) })
            let mappedItems = shortcuts.compactMap { shortcut -> Item? in
                guard let credential = credentialMap[shortcut.credentialKey] else { return nil }
                return Item(
                    shortcutID: shortcut.id,
                    credentialKey: shortcut.credentialKey,
                    title: shortcut.title,
                    host: credential.host,
                    startupScript: shortcut.startupScript,
                    colorHex: shortcut.colorHex ?? "#3B82F6"
                )
            }

            await MainActor.run {
                self.items = mappedItems
                var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
                snapshot.appendSections([.main])
                snapshot.appendItems(mappedItems, toSection: .main)
                self.dataSource.apply(snapshot, animatingDifferences: true)
                self.emptyStateLabel.isHidden = !mappedItems.isEmpty
            }
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TerminalServerCell.reuseID,
                for: indexPath
            ) as? TerminalServerCell else {
                return UICollectionViewCell()
            }

            cell.apply(
                title: item.title,
                host: item.host,
                startupScript: item.startupScript,
                colorHex: item.colorHex
            )
            return cell
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment -> NSCollectionLayoutSection? in
            let width = environment.container.effectiveContentSize.width
            let sideInset = max(UIFloat(2), min(UIFloat(8), width * 0.03))

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .fractionalHeight(1)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: UIFloat(3), bottom: 0, trailing: UIFloat(3))

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(UIFloat(98))
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item])

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = UIFloat(8)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: TerminalUIMetrics.sectionTopInset,
                leading: sideInset,
                bottom: TerminalUIMetrics.sectionBottomInset,
                trailing: sideInset
            )
            return section
        }
    }

    @objc
    private func didTapAddShortcut() {
        let editor = TerminalShortcutEditorViewController()
        editor.onSaved = { [weak self] in
            self?.reloadCredentials()
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(nav, animated: true)
    }
}

extension TerminalServerPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        let item = items[indexPath.item]
        Task {
            let shortcuts = await TerminalLaunchShortcut.all(in: SharedDatabase.db)
            guard var selected = shortcuts.first(where: { $0.id == item.shortcutID }) else { return }
            selected.lastUse = .now
            try? await selected.write(to: SharedDatabase.db)
            await MainActor.run {
                self.onShortcutSelected?(selected)
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.item < items.count else { return nil }
        let item = items[indexPath.item]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }

            let edit = UIAction(title: "Edit Shortcut", image: UIImage(systemName: "pencil")) { _ in
                self.presentShortcutEditor(for: item.shortcutID)
            }

            let delete = UIAction(
                title: "Delete Shortcut",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.deleteShortcut(shortcutID: item.shortcutID)
            }

            return UIMenu(children: [edit, delete])
        }
    }

    private func presentShortcutEditor(for shortcutID: String) {
        Task {
            let rows = (try? await TerminalLaunchShortcut.read(
                from: SharedDatabase.db,
                matching: \.$id == shortcutID,
                limit: 1
            )) ?? []
            guard let existing = rows.first else { return }

            await MainActor.run {
                let editor = TerminalShortcutEditorViewController(shortcut: existing)
                editor.onSaved = { [weak self] in
                    self?.reloadCredentials()
                }
                let nav = UINavigationController(rootViewController: editor)
                nav.modalPresentationStyle = .pageSheet
                if let sheet = nav.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                }
                self.present(nav, animated: true)
            }
        }
    }

    private func deleteShortcut(shortcutID: String) {
        Task {
            let rows = (try? await TerminalLaunchShortcut.read(
                from: SharedDatabase.db,
                matching: \.$id == shortcutID,
                limit: 1
            )) ?? []
            guard let row = rows.first else { return }
            try? await row.delete(from: SharedDatabase.db)
            await MainActor.run {
                self.reloadCredentials()
            }
        }
    }
}

@MainActor
final class TerminalShortcutEditorViewController: UIHostingController<TerminalShortcutEditorScreen> {
    var onSaved: (() -> Void)? {
        didSet {
            updateRootView()
        }
    }

    init(shortcut: TerminalLaunchShortcut? = nil) {
        super.init(rootView: TerminalShortcutEditorScreen(existingShortcut: shortcut, onSaved: nil, onRequestClose: nil))
        updateRootView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateRootView() {
        var updated = rootView
        updated.onSaved = onSaved
        updated.onRequestClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        rootView = updated
    }
}

struct TerminalShortcutEditorScreen: View {
    @Environment(\.dismiss) private var dismiss

    let existingShortcut: TerminalLaunchShortcut?
    var onSaved: (() -> Void)?
    var onRequestClose: (() -> Void)?

    @State private var credentials: [Credential]
    @State private var selectedCredentialKey: String?
    @State private var selectedThemeKey: String?
    @State private var name: String
    @State private var startupScript: String
    @State private var color: Color
    private let settingsStore = TerminalSettingsStore.shared

    init(existingShortcut: TerminalLaunchShortcut?, onSaved: (() -> Void)?, onRequestClose: (() -> Void)?) {
        self.existingShortcut = existingShortcut
        self.onSaved = onSaved
        self.onRequestClose = onRequestClose

        let loadedCredentials = keychain()
            .allKeys()
            .compactMap { keychain().getCredential(for: $0) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        _credentials = State(initialValue: loadedCredentials)
        _selectedCredentialKey = State(initialValue: existingShortcut?.credentialKey ?? loadedCredentials.first?.key)
        _selectedThemeKey = State(initialValue: existingShortcut?.themeSelectionKey)
        _name = State(initialValue: existingShortcut?.title ?? "")
        _startupScript = State(initialValue: existingShortcut?.startupScript ?? "")
        _color = State(initialValue: Color(UIColor(hex: existingShortcut?.colorHex ?? "#3B82F6") ?? .systemBlue))
    }

    var body: some View {
        Form {
            Section("Shortcut") {
                TextField("Shortcut name", text: $name)

                NavigationLink {
                    TerminalShortcutServerSelectionScreen(
                        credentials: credentials,
                        selectedCredentialKey: $selectedCredentialKey
                    )
                } label: {
                    LabeledContent("Server") {
                        Text(selectedCredential?.label ?? "Choose Server")
                            .foregroundStyle(selectedCredential == nil ? .secondary : .primary)
                    }
                }

                NavigationLink {
                    TerminalShortcutThemeSelectionScreen(selectedThemeKey: $selectedThemeKey, settingsStore: settingsStore)
                } label: {
                    LabeledContent("Theme Override") {
                        Text(settingsStore.themeDisplayName(for: selectedThemeKey))
                            .foregroundStyle(.primary)
                    }
                }

                ColorPicker("Shortcut Color", selection: $color, supportsOpacity: false)
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: UIFloat(4)) {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shortcut Preview" : name)
                        .font(.headline)
                    Text(selectedCredential.map { "\($0.username)@\($0.host)" } ?? "No server selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, UIFloat(2))
            }

            Section("Startup Script (Optional)") {
                TextEditor(text: $startupScript)
                    .font(.system(size: UIFloat(13), weight: .regular, design: .monospaced))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: UIFloat(180))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(existingShortcut == nil ? "New Shortcut" : "Edit Shortcut")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if let onRequestClose {
                        onRequestClose()
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCredential == nil)
            }
        }
    }

    private var selectedCredential: Credential? {
        guard let key = selectedCredentialKey else { return nil }
        return credentials.first(where: { $0.key == key })
    }

    private func save() {
        guard let credential = selectedCredential else { return }
        let resolvedTitle = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? credential.label : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedScript = startupScript.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorHex = UIColor(color).hexString

        Task {
            let shortcut = TerminalLaunchShortcut(
                id: existingShortcut?.id ?? UUID().uuidString,
                credentialKey: credential.key,
                title: resolvedTitle,
                startupScript: resolvedScript,
                colorHex: colorHex,
                themeSelectionKey: selectedThemeKey,
                lastUse: .now
            )
            try? await shortcut.write(to: SharedDatabase.db)
            await MainActor.run {
                onSaved?()
                if let onRequestClose {
                    onRequestClose()
                } else {
                    dismiss()
                }
            }
        }
    }
}

private struct TerminalShortcutServerSelectionScreen: View {
    let credentials: [Credential]
    @Binding var selectedCredentialKey: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(credentials, id: \.key) { credential in
            Button {
                selectedCredentialKey = credential.key
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: UIFloat(2)) {
                        Text(credential.label)
                            .foregroundStyle(.primary)
                        Text("\(credential.username)@\(credential.host)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedCredentialKey == credential.key {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .navigationTitle("Select Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TerminalShortcutThemeSelectionScreen: View {
    @Binding var selectedThemeKey: String?
    let settingsStore: TerminalSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button {
                selectedThemeKey = nil
                dismiss()
            } label: {
                HStack {
                    Text("Use App Default Theme")
                    Spacer()
                    if selectedThemeKey == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }

            Section("Presets") {
                ForEach(TerminalThemePreset.all) { preset in
                    let key = settingsStore.themeSelectionKey(for: .preset(id: preset.id))
                    Button {
                        selectedThemeKey = key
                        dismiss()
                    } label: {
                        HStack {
                            Text(preset.name)
                            Spacer()
                            if selectedThemeKey == key {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }

            if !settingsStore.state.customThemes.isEmpty {
                Section("Custom") {
                    ForEach(settingsStore.state.customThemes) { custom in
                        let key = settingsStore.themeSelectionKey(for: .custom(id: custom.id))
                        Button {
                            selectedThemeKey = key
                            dismiss()
                        } label: {
                            HStack {
                                Text(custom.name)
                                Spacer()
                            if selectedThemeKey == key {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        }
        .navigationTitle("Shortcut Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Snippet Picker

@MainActor
final class TerminalSnippetPickerViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case main
    }

    private let database: Blackbird.Database
    private let credentialKey: String?
    private let onSelectSnippet: (Snippet) -> Void

    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private let emptyStateLabel = UILabel()

    private var snippets: [Snippet] = []

    init(database: Blackbird.Database, credentialKey: String?, onSelectSnippet: @escaping (Snippet) -> Void) {
        self.database = database
        self.credentialKey = credentialKey
        self.onSelectSnippet = onSelectSnippet

        let layout = TerminalSnippetPickerViewController.makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureUI()
        loadSnippets()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSnippets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
        emptyStateLabel.frame = view.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(40),
            left: UIFloat(24),
            bottom: UIFloat(40),
            right: UIFloat(24)
        ))
    }

    // MARK: Setup

    private func configureUI() {
        view.backgroundColor = UIColor.systemBackground

        navigationItem.title = "Insert Snippet"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .prominent,
            target: self,
            action: #selector(didTapDone)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Manage",
            style: .plain,
            target: self,
            action: #selector(didTapManage)
        )

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.register(TerminalSnippetCell.self, forCellWithReuseIdentifier: TerminalSnippetCell.reuseID)
        view.addSubview(collectionView)

        emptyStateLabel.text = "No snippets yet.\nOpen Manage to add one or generate with AI."
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.textColor = UIColor.secondaryLabel
        emptyStateLabel.font = UIFont.systemFont(ofSize: UIFloat(15), weight: .regular)
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)
    }

    // MARK: Data

    private func loadSnippets() {
        Task {
            await Snippet.purgeLegacyDefaults(in: database)
            let rows = (try? await Snippet.read(
                from: database,
                matching: .all,
                orderBy: .descending(\.$lastUse),
                limit: 200
            )) ?? []
            let filteredRows = rows.filter { snippet in
                let key = snippet.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if key.isEmpty { return true }
                return key == credentialKey
            }

            await MainActor.run {
                self.snippets = filteredRows
                var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
                snapshot.appendSections([.main])
                snapshot.appendItems(filteredRows.map(\.id), toSection: .main)
                self.dataSource.apply(snapshot, animatingDifferences: true)
                self.emptyStateLabel.isHidden = !filteredRows.isEmpty
            }
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, String> {
        UICollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] collectionView, indexPath, itemID in
            guard let self,
                  let snippet = self.snippets.first(where: { $0.id == itemID }),
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: TerminalSnippetCell.reuseID,
                    for: indexPath
                  ) as? TerminalSnippetCell
            else {
                return UICollectionViewCell()
            }

            cell.apply(command: snippet.command, comment: snippet.comment)
            return cell
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(TerminalUIMetrics.snippetCellHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(TerminalUIMetrics.snippetCellHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = UIFloat(8)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: TerminalUIMetrics.sectionTopInset,
                leading: UIFloat(8),
                bottom: TerminalUIMetrics.sectionBottomInset,
                trailing: UIFloat(8)
            )
            return section
        }
    }

    // MARK: Actions

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }

    @objc
    private func didTapManage() {
        let manage = TerminalManageSnippetsViewController(database: database, credentialKey: credentialKey)
        navigationController?.pushViewController(manage, animated: true)
    }
}

extension TerminalSnippetPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < snippets.count else { return }

        let snippet = snippets[indexPath.item]
        onSelectSnippet(snippet)

        Task {
            var updated = snippet
            updated.lastUse = .now
            try? await updated.write(to: database)
        }

        dismiss(animated: true)
    }
}

// MARK: - Snippet Manager

@MainActor
final class TerminalManageSnippetsViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case main
    }

    private let database: Blackbird.Database
    private let credentialKey: String?
    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private let emptyStateContainer = UIStackView()
    private let emptyStateTitleLabel = UILabel()
    private let emptyStateSubtitleLabel = UILabel()
    private let addSnippetButton = UIButton(type: .system)
    private let askAIButton = UIButton(type: .system)

    private var snippets: [Snippet] = []
    private let relativeFormatter = RelativeDateTimeFormatter()

    init(database: Blackbird.Database, credentialKey: String? = nil) {
        self.database = database
        self.credentialKey = credentialKey
        let layout = TerminalManageSnippetsViewController.makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureUI()
        loadSnippets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
        emptyStateContainer.frame = view.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(40),
            left: UIFloat(24),
            bottom: UIFloat(40),
            right: UIFloat(24)
        ))
    }

    // MARK: Setup

    private func configureUI() {
        view.backgroundColor = UIColor.systemBackground

        navigationItem.title = "Snippets"
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(didTapAdd)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "sparkles"),
                style: .plain,
                target: self,
                action: #selector(didTapAskAI)
            )
        ]

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.register(TerminalSnippetManageCell.self, forCellWithReuseIdentifier: TerminalSnippetManageCell.reuseID)
        view.addSubview(collectionView)

        emptyStateContainer.axis = .vertical
        emptyStateContainer.alignment = .center
        emptyStateContainer.distribution = .fill
        emptyStateContainer.spacing = UIFloat(12)
        emptyStateContainer.isHidden = true
        view.addSubview(emptyStateContainer)

        emptyStateTitleLabel.text = "No snippets yet"
        emptyStateTitleLabel.font = UIFont.systemFont(ofSize: UIFloat(22), weight: .semibold)
        emptyStateTitleLabel.textAlignment = .center
        emptyStateTitleLabel.textColor = UIColor.label
        emptyStateContainer.addArrangedSubview(emptyStateTitleLabel)

        emptyStateSubtitleLabel.text = "Add your own snippet or let AI draft one from a task."
        emptyStateSubtitleLabel.font = UIFont.systemFont(ofSize: UIFloat(15), weight: .regular)
        emptyStateSubtitleLabel.textAlignment = .center
        emptyStateSubtitleLabel.textColor = UIColor.secondaryLabel
        emptyStateSubtitleLabel.numberOfLines = 0
        emptyStateContainer.addArrangedSubview(emptyStateSubtitleLabel)

        configureEmptyStateButton(addSnippetButton, title: "Add Snippet", filled: true, action: #selector(didTapAdd))
        configureEmptyStateButton(askAIButton, title: "Ask AI", filled: false, action: #selector(didTapAskAI))
        emptyStateContainer.addArrangedSubview(addSnippetButton)
        emptyStateContainer.addArrangedSubview(askAIButton)
    }

    // MARK: Data

    private func loadSnippets() {
        Task {
            await Snippet.purgeLegacyDefaults(in: database)
            let rows = (try? await Snippet.read(
                from: database,
                matching: .all,
                orderBy: .descending(\.$lastUse),
                limit: 400
            )) ?? []
            let filteredRows = rows.filter { snippet in
                let key = snippet.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if key.isEmpty { return true }
                return key == credentialKey
            }

            await MainActor.run {
                self.snippets = filteredRows
                var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
                snapshot.appendSections([.main])
                snapshot.appendItems(filteredRows.map(\.id), toSection: .main)
                self.dataSource.apply(snapshot, animatingDifferences: true)
                self.emptyStateContainer.isHidden = !filteredRows.isEmpty
            }
        }
    }

    private func configureEmptyStateButton(_ button: UIButton, title: String, filled: Bool, action: Selector) {
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = title
        config.baseForegroundColor = filled ? .white : .label
        config.baseBackgroundColor = filled ? UIColor.tintColor : UIColor.tertiarySystemFill
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(
            top: UIFloat(10),
            leading: UIFloat(14),
            bottom: UIFloat(10),
            trailing: UIFloat(14)
        )
        button.configuration = config

        button.layer.cornerRadius = UIFloat(10)
        button.layer.cornerCurve = .continuous
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, String> {
        UICollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { [weak self] collectionView, indexPath, itemID in
            guard let self,
                  let snippet = self.snippets.first(where: { $0.id == itemID }),
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: TerminalSnippetManageCell.reuseID,
                    for: indexPath
                  ) as? TerminalSnippetManageCell
            else {
                return UICollectionViewCell()
            }

            let relative = self.relativeFormatter.localizedString(for: snippet.lastUse, relativeTo: Date())
            cell.apply(command: snippet.command, comment: snippet.comment, relativeTime: relative)
            cell.onDelete = { [weak self] in
                self?.deleteSnippet(snippet)
            }
            return cell
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(UIFloat(84))
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(UIFloat(84))
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = UIFloat(8)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: TerminalUIMetrics.sectionTopInset,
                leading: UIFloat(8),
                bottom: TerminalUIMetrics.sectionBottomInset,
                trailing: UIFloat(8)
            )
            return section
        }
    }

    private func deleteSnippet(_ snippet: Snippet) {
        Task {
            try? await snippet.delete(from: database)
            await MainActor.run {
                self.loadSnippets()
            }
        }
    }

    // MARK: Actions

    @objc
    private func didTapAdd() {
        presentEditor(for: nil)
    }

    @objc
    private func didTapAskAI() {
        let alert = UIAlertController(
            title: "Generate Snippet with AI",
            message: "Describe what command you want. Example: \"Show Docker containers consuming the most memory\".",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Describe your goal"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Generate", style: .default, handler: { [weak self] _ in
            guard self != nil else { return }
            let prompt = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !prompt.isEmpty else { return }
            AgenticContextBridge.shared.openAgentic(
                chatTitle: "Snippet Draft",
                draftMessage: """
                Help me draft a reusable terminal snippet.

                Goal:
                \(prompt)

                Please propose the command and a short comment.
                """
            )
        }))
        present(alert, animated: true)
    }

    private func generateSnippetWithAI(from prompt: String) {
        Task {
            let output = await LLM.generate(
                prompt: prompt,
                systemPrompt: Self.snippetGenerationSystemPrompt
            ).output

            do {
                let snippet = try Self.parseSnippetResponse(output)
                try await snippet.write(to: database)
                await MainActor.run {
                    self.loadSnippets()
                }
            } catch {
                await MainActor.run {
                    self.showErrorAlert(message: "AI returned an invalid snippet. Please try a more specific prompt.")
                }
            }
        }
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Couldn’t Generate Snippet", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static let snippetGenerationSystemPrompt = #"""
You generate reusable shell snippets for a terminal app.

Always return only JSON in this exact format:
{
  "type": "response",
  "content": {
    "command": "shell command",
    "comment": "short explanation"
  }
}

Rules:
- command must be a single command line.
- Use placeholders like <container> when user-specific values are unknown.
- comment must be concise (under 90 characters).
- Do not include markdown fences.
"""#

    private static func parseSnippetResponse(_ raw: String) throws -> Snippet {
        struct Response: Decodable {
            struct Content: Decodable {
                let command: String
                let comment: String
            }
            let type: String
            let content: Content
        }

        let cleaned = LLM.cleanLLMOutput(raw)
        let response = try JSONDecoder().decode(Response.self, from: Data(cleaned.utf8))
        guard response.type == "response" else { throw NSError(domain: "SnippetAI", code: 1) }
        let command = response.content.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = response.content.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw NSError(domain: "SnippetAI", code: 2) }

        return Snippet(command: command, comment: comment, lastUse: .now)
    }

    private func presentEditor(for snippet: Snippet?) {
        let alert = UIAlertController(
            title: snippet == nil ? "New Snippet" : "Edit Snippet",
            message: nil,
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "Command"
            textField.text = snippet?.command
        }

        alert.addTextField { textField in
            textField.placeholder = "Comment"
            textField.text = snippet?.comment
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let command = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let comment = alert.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            Task {
                var target = snippet ?? Snippet(command: command, comment: comment, lastUse: .now, credentialKey: self.credentialKey)
                target.command = command
                target.comment = comment
                if snippet == nil {
                    target.lastUse = .now
                }

                try? await target.write(to: self.database)
                await MainActor.run {
                    self.loadSnippets()
                }
            }
        }))

        present(alert, animated: true)
    }
}

extension TerminalManageSnippetsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < snippets.count else { return }
        presentEditor(for: snippets[indexPath.item])
    }
}

// MARK: - Collection Cells

private extension UIColor {
    convenience init?(hex: String) {
        let value = hex.replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = Int(value, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255.0,
            green: CGFloat((number >> 8) & 0xFF) / 255.0,
            blue: CGFloat(number & 0xFF) / 255.0,
            alpha: 1
        )
    }

    var hexString: String {
        guard let components = cgColor.components else { return "#3B82F6" }
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
            return "#3B82F6"
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

final class TerminalServerCell: UICollectionViewCell {
    static let reuseID = "TerminalServerCell"

    private let backgroundCard = UIView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let scriptLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundCard.frame = contentView.bounds

        var inner = backgroundCard.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(8),
            left: UIFloat(10),
            bottom: UIFloat(8),
            right: UIFloat(10)
        ))

        let titleSplit = inner.split(at: UIFloat(22), from: .minYEdge)
        titleLabel.frame = titleSplit.slice
        inner = titleSplit.remainder

        let hostSplit = inner.split(at: UIFloat(18), from: .minYEdge)
        hostLabel.frame = hostSplit.slice
        scriptLabel.frame = hostSplit.remainder
    }

    private func configureUI() {
        contentView.backgroundColor = .clear

        backgroundCard.backgroundColor = UIColor.tertiarySystemFill
        backgroundCard.layer.cornerRadius = UIFloat(12)
        backgroundCard.layer.cornerCurve = .continuous
        contentView.addSubview(backgroundCard)

        titleLabel.font = UIFont.systemFont(ofSize: UIFloat(14), weight: .semibold)
        titleLabel.textColor = UIColor.label
        backgroundCard.addSubview(titleLabel)

        hostLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .regular)
        hostLabel.textColor = UIColor.secondaryLabel
        backgroundCard.addSubview(hostLabel)

        scriptLabel.font = UIFont.monospacedSystemFont(ofSize: UIFloat(11), weight: .regular)
        scriptLabel.textColor = UIColor.secondaryLabel
        scriptLabel.numberOfLines = 2
        scriptLabel.lineBreakMode = .byTruncatingTail
        backgroundCard.addSubview(scriptLabel)
    }

    func apply(title: String, host: String, startupScript: String, colorHex: String) {
        titleLabel.text = title
        hostLabel.text = host
        let trimmed = startupScript.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptLabel.text = trimmed.isEmpty ? "No startup script" : trimmed
        let accent = UIColor(hex: colorHex) ?? .systemBlue
        backgroundCard.backgroundColor = accent.withAlphaComponent(0.20)
        backgroundCard.layer.borderWidth = UIFloat(1)
        backgroundCard.layer.borderColor = accent.withAlphaComponent(0.45).cgColor
    }
}

final class TerminalSnippetCell: UICollectionViewCell {
    static let reuseID = "TerminalSnippetCell"

    private let backgroundCard = UIView()
    private let commandLabel = UILabel()
    private let commentLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundCard.frame = contentView.bounds

        var inner = backgroundCard.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(8),
            left: UIFloat(10),
            bottom: UIFloat(8),
            right: UIFloat(10)
        ))

        let commandSplit = inner.split(at: UIFloat(24), from: .minYEdge)
        commandLabel.frame = commandSplit.slice
        inner = commandSplit.remainder
        commentLabel.frame = inner
    }

    private func configureUI() {
        contentView.backgroundColor = .clear

        backgroundCard.backgroundColor = UIColor.tertiarySystemFill
        backgroundCard.layer.cornerRadius = UIFloat(12)
        backgroundCard.layer.cornerCurve = .continuous
        contentView.addSubview(backgroundCard)

        commandLabel.font = UIFont.monospacedSystemFont(ofSize: UIFloat(13), weight: .regular)
        commandLabel.textColor = UIColor.label
        commandLabel.lineBreakMode = .byTruncatingTail
        backgroundCard.addSubview(commandLabel)

        commentLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .regular)
        commentLabel.textColor = UIColor.secondaryLabel
        commentLabel.numberOfLines = 2
        commentLabel.lineBreakMode = .byTruncatingTail
        backgroundCard.addSubview(commentLabel)
    }

    func apply(command: String, comment: String) {
        commandLabel.text = command
        commentLabel.text = comment
    }
}

final class TerminalSnippetManageCell: UICollectionViewCell {
    static let reuseID = "TerminalSnippetManageCell"

    var onDelete: (() -> Void)?

    private let backgroundCard = UIView()
    private let commandLabel = UILabel()
    private let commentLabel = UILabel()
    private let relativeLabel = UILabel()
    private let deleteButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundCard.frame = contentView.bounds

        var inner = backgroundCard.bounds.inset(by: UIEdgeInsets(
            top: UIFloat(8),
            left: UIFloat(10),
            bottom: UIFloat(8),
            right: UIFloat(10)
        ))

        let trailingSplit = inner.split(at: UIFloat(36), from: .maxXEdge)
        deleteButton.frame = trailingSplit.slice
        inner = trailingSplit.remainder

        let topSplit = inner.split(at: UIFloat(24), from: .minYEdge)
        commandLabel.frame = topSplit.slice
        inner = topSplit.remainder

        let bottomSplit = inner.split(at: UIFloat(20), from: .maxYEdge)
        relativeLabel.frame = bottomSplit.slice
        commentLabel.frame = bottomSplit.remainder
    }

    private func configureUI() {
        contentView.backgroundColor = .clear

        backgroundCard.backgroundColor = UIColor.tertiarySystemFill
        backgroundCard.layer.cornerRadius = UIFloat(12)
        backgroundCard.layer.cornerCurve = .continuous
        contentView.addSubview(backgroundCard)

        commandLabel.font = UIFont.monospacedSystemFont(ofSize: UIFloat(13), weight: .regular)
        commandLabel.textColor = UIColor.label
        backgroundCard.addSubview(commandLabel)

        commentLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .regular)
        commentLabel.textColor = UIColor.secondaryLabel
        commentLabel.numberOfLines = 2
        backgroundCard.addSubview(commentLabel)

        relativeLabel.font = UIFont.systemFont(ofSize: UIFloat(11), weight: .regular)
        relativeLabel.textColor = UIColor.tertiaryLabel
        backgroundCard.addSubview(relativeLabel)

        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = UIColor.systemRed
        deleteButton.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
        backgroundCard.addSubview(deleteButton)
    }

    func apply(command: String, comment: String, relativeTime: String) {
        commandLabel.text = command
        commentLabel.text = comment
        relativeLabel.text = relativeTime
    }

    @objc
    private func didTapDelete() {
        onDelete?()
    }
}
