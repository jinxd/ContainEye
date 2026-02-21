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
    static let suggestionHeight = UIFloat(34)
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
    static let keyboardKeyFill = UIColor.tertiarySystemFill
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

    private let navigationTitleMenuButton = UIButton(type: .system)
    private let paneContainerView = UIView()
    private let keyboardBarView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
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
    private lazy var volumeBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "plusminus.circle"),
        style: .plain,
        target: self,
        action: #selector(didTapVolumeControl)
    )
    private var useVolumeButtons = UserDefaults.standard.bool(forKey: "useVolumeButtons") {
        didSet {
            UserDefaults.standard.set(useVolumeButtons, forKey: "useVolumeButtons")
            updateVolumeButtonAppearance()
            configureVolumeButtons(enabled: useVolumeButtons)
        }
    }

    private var keyboardButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        configureBaseUI()
        configureNavigationItems()
        configureKeyboardBar()
        installObservers()

        workspace.restoreWorkspace()
        refreshUI()
        processPendingRequests()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        refreshNavigationChrome()
        processPendingRequests()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hardwareInput.stop()
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
        keyboardBarView.layer.cornerRadius = UIFloat(12)
        keyboardBarView.layer.cornerCurve = .continuous
        keyboardBarView.isHidden = true
        view.addSubview(keyboardBarView)

        keyboardControlsContainer.backgroundColor = .clear
        keyboardBarView.contentView.addSubview(keyboardControlsContainer)

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
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.baseForegroundColor = UIColor.label
            config.image = UIImage(systemName: "chevron.down")
            config.imagePlacement = .trailing
            config.imagePadding = UIFloat(6)
            config.contentInsets = .zero
            navigationTitleMenuButton.configuration = config
        }

        navigationItem.titleView = navigationTitleMenuButton
        navigationItem.leftBarButtonItem = addBarButtonItem
        navigationItem.rightBarButtonItems = [snippetBarButtonItem, volumeBarButtonItem]
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
            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.plain()
                config.contentInsets = insets
                button.configuration = config
            } else {
                button.contentEdgeInsets = UIEdgeInsets(
                    top: insets.top,
                    left: insets.leading,
                    bottom: insets.bottom,
                    right: insets.trailing
                )
            }
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
        }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.startKeyboardControllerObservation()
                self?.updateKeyboardButtonsState()
                self?.updateKeyboardBarVisibility()
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

        updateVolumeButtonAppearance()
    }

    private func titleTextForFocusedPane() -> String {
        guard let focusedID = workspace.focusedPaneID,
              let index = workspace.panes.firstIndex(where: { $0.id == focusedID })
        else {
            return "Terminal"
        }

        if let active = workspace.activeTab(in: focusedID) {
            return "Tab \(index + 1) · \(active.title)"
        }

        return "Tab \(index + 1)"
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

    private func updateVolumeButtonAppearance() {
        let image = UIImage(systemName: useVolumeButtons ? "plusminus.circle.fill" : "plusminus.circle")
        volumeBarButtonItem.image = image
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
            let barHeight = TerminalUIMetrics.keyboardBarHeight + TerminalUIMetrics.keyboardBarBottomInset
            let split = layoutRect.split(at: barHeight, from: .maxYEdge)
            keyboardBarView.frame = split.slice
            keyboardControlsContainer.frame = keyboardBarView.bounds.inset(by: UIEdgeInsets(
                top: UIFloat(4),
                left: UIFloat(6),
                bottom: UIFloat(4),
                right: UIFloat(6)
            ))
            keyboardStackView.frame = keyboardControlsContainer.bounds
            layoutRect = split.remainder
        } else {
            keyboardBarView.frame = .zero
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
        keyboardBarView.isHidden = !shouldShowKeyboardBar
        updateKeyboardButtonsState()
        view.setNeedsLayout()
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

    private func configureVolumeButtons(enabled: Bool) {
        if !enabled {
            hardwareInput.stop()
            return
        }

        hardwareInput.start(
            onVolumeDown: { [weak self] in
                self?.workspace.activeControllerInFocusedPane()?.sendArrowDown()
            },
            onVolumeUp: { [weak self] in
                self?.workspace.activeControllerInFocusedPane()?.sendArrowUp()
            }
        )
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
    private func didTapVolumeControl() {
        useVolumeButtons.toggle()
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

    private let panelView = UIView()
    private let headerView = UIView()
    private let contentView = UIView()
    private let suggestionsContainerView = UIView()

    private let tabTitleLabel = UILabel()
    private let activeTitleLabel = UILabel()
    private let cwdLabel = UILabel()
    private let warningImageView = UIImageView()
    private let closeButton = UIButton(type: .system)

    private var suggestionButtons: [UIButton] = []
    private var activeHostView: XTermWebHostView?
    private var serverPickerController: TerminalServerPickerViewController?
    private var observedControllerID: UUID?
    private var lastPresentedPromptID: UUID?

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

        suggestionsContainerView.backgroundColor = .clear
        panelView.addSubview(suggestionsContainerView)

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
        panelView.layer.borderColor = (focused ? TerminalUIColors.focusedPaneStroke : TerminalUIColors.paneStroke).cgColor

        let tabNumber = (workspace.panes.firstIndex(where: { $0.id == paneID }) ?? 0) + 1
        tabTitleLabel.text = "Tab \(tabNumber)"

        guard let activeTab = workspace.activeTab(in: paneID),
              let controller = workspace.controller(for: activeTab.id)
        else {
            observedControllerID = nil
            activeTitleLabel.text = "Choose a server"
            cwdLabel.text = ""
            warningImageView.isHidden = true
            closeButton.isHidden = true
            showServerPicker()
            setSuggestionButtons([])
            view.setNeedsLayout()
            return
        }

        closeButton.isHidden = false
        activeTitleLabel.text = activeTab.title
        cwdLabel.text = controller.cwd
        warningImageView.isHidden = controller.shellIntegrationStatus != .warning

        showTerminalHost(for: controller)
        setSuggestionButtons(Array(controller.suggestions.prefix(3)))
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

        let hasSuggestions = !suggestionButtons.isEmpty
        if hasSuggestions {
            let suggestionSplit = inner.split(at: TerminalUIMetrics.suggestionHeight, from: .maxYEdge)
            suggestionsContainerView.frame = suggestionSplit.slice
            contentView.frame = suggestionSplit.remainder
        } else {
            suggestionsContainerView.frame = .zero
            contentView.frame = inner
        }

        layoutHeaderViews(in: headerView.bounds)
        layoutSuggestions(in: suggestionsContainerView.bounds)
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

    private func layoutSuggestions(in bounds: CGRect) {
        guard !suggestionButtons.isEmpty else { return }

        let suggestionRects = splitRect(
            bounds,
            count: suggestionButtons.count,
            spacing: UIFloat(6),
            axis: .horizontal
        )

        for (index, button) in suggestionButtons.enumerated() {
            button.frame = suggestionRects[index]
        }
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
        picker.onCredentialSelected = { [weak self] credentialKey in
            guard let self else { return }
            self.workspace.focusPane(paneID: self.paneID)
            self.workspace.openTab(credentialKey: credentialKey, inFocusedPane: true)
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
        host.backgroundColor = TerminalUIColors.terminalBackground
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
    }

    private func setSuggestionButtons(_ suggestions: [CommandSuggestion]) {
        for button in suggestionButtons {
            button.removeFromSuperview()
        }
        suggestionButtons.removeAll(keepingCapacity: false)

        for suggestion in suggestions {
            let button = UIButton(type: .system)
            button.setTitle(suggestion.text, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .medium)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.contentHorizontalAlignment = .leading
            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.plain()
                config.contentInsets = NSDirectionalEdgeInsets(
                    top: UIFloat(6),
                    leading: UIFloat(8),
                    bottom: UIFloat(6),
                    trailing: UIFloat(8)
                )
                button.configuration = config
            } else {
                button.contentEdgeInsets = UIEdgeInsets(
                    top: UIFloat(6),
                    left: UIFloat(8),
                    bottom: UIFloat(6),
                    right: UIFloat(8)
                )
            }
            button.layer.cornerRadius = UIFloat(12)
            button.layer.cornerCurve = .continuous
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = suggestionColor(for: suggestion.source)
            button.accessibilityLabel = suggestion.text
            button.addAction(UIAction(handler: { [weak self] _ in
                guard let self else { return }
                guard let active = self.workspace.activeTab(in: self.paneID),
                      let controller = self.workspace.controller(for: active.id)
                else {
                    return
                }
                controller.applySuggestion(suggestion.text)
                controller.focus()
            }), for: .touchUpInside)
            suggestionsContainerView.addSubview(button)
            suggestionButtons.append(button)
        }
    }

    private func suggestionColor(for source: CommandSuggestion.Source) -> UIColor {
        switch source {
        case .documentTree:
            return .systemBlue
        case .history:
            return .systemGray
        case .snippet:
            return .systemGreen
        case .live:
            return .systemOrange
        }
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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var candidate = touch.view
        while let current = candidate {
            if current is UIControl || current is UICollectionView || current is UICollectionViewCell {
                return false
            }
            candidate = current.superview
        }
        return true
    }
}

// MARK: - Server Picker

@MainActor
final class TerminalServerPickerViewController: UIViewController {
    var onCredentialSelected: ((String) -> Void)?

    private enum Section: Int, CaseIterable {
        case main
    }

    private struct Item: Hashable {
        let key: String
        let label: String
        let host: String
    }

    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private let emptyStateLabel = UILabel()

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
        collectionView.allowsSelection = true
        collectionView.register(TerminalServerCell.self, forCellWithReuseIdentifier: TerminalServerCell.reuseID)
        collectionView.delegate = self
        view.addSubview(collectionView)

        emptyStateLabel.text = "No servers available"
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.font = UIFont.systemFont(ofSize: UIFloat(14), weight: .medium)
        emptyStateLabel.textColor = UIColor.secondaryLabel
        emptyStateLabel.numberOfLines = 2
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)
    }

    // MARK: Data

    func reloadCredentials() {
        let credentials = keychain()
            .allKeys()
            .compactMap { keychain().getCredential(for: $0) }
            .sorted { lhs, rhs in
                lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }

        items = credentials.map { credential in
            Item(key: credential.key, label: credential.label, host: credential.host)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)

        emptyStateLabel.isHidden = !items.isEmpty
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TerminalServerCell.reuseID,
                for: indexPath
            ) as? TerminalServerCell else {
                return UICollectionViewCell()
            }

            cell.apply(label: item.label, host: item.host)
            return cell
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(TerminalUIMetrics.serverCellHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(TerminalUIMetrics.serverCellHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = UIFloat(8)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: TerminalUIMetrics.sectionTopInset,
                leading: TerminalUIMetrics.sectionSideInset,
                bottom: TerminalUIMetrics.sectionBottomInset,
                trailing: TerminalUIMetrics.sectionSideInset
            )
            return section
        }
    }
}

extension TerminalServerPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        let item = items[indexPath.item]
        onCredentialSelected?(item.key)
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
        if #available(iOS 15.0, *) {
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
        } else {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: UIFloat(15), weight: .semibold)
            button.backgroundColor = filled ? UIColor.tintColor : UIColor.tertiarySystemFill
            button.setTitleColor(filled ? .white : .label, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(
                top: UIFloat(10),
                left: UIFloat(14),
                bottom: UIFloat(10),
                right: UIFloat(14)
            )
        }

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

final class TerminalServerCell: UICollectionViewCell {
    static let reuseID = "TerminalServerCell"

    private let backgroundCard = UIView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()

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
        hostLabel.frame = inner
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
    }

    func apply(label: String, host: String) {
        titleLabel.text = label
        hostLabel.text = host
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
