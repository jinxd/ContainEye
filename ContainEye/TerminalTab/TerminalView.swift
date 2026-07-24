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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        TerminalWorkspaceNavigationHost()
            .ignoresSafeArea(.container, edges: .bottom)
            .trackView("terminal/workspace")
            .onAppear {
                // Bridge UIKit terminal chrome to SwiftUI multi-window support so a
                // session can be popped out into its own window on iPad/Mac.
                TerminalWindowRouter.shared.openTerminalWindow = { target in
                    openWindow(value: target)
                }
                TerminalWindowRouter.shared.dismissTerminalWindow = { target in
                    dismissWindow(value: target)
                }
            }
    }
}

#Preview(traits: .sampleData) {
    RemoteTerminalView()
}

struct TerminalWorkspaceNavigationHost: UIViewControllerRepresentable {
    var workspace: TerminalWorkspaceStore = .shared
    var windowID: String = TerminalWorkspaceStore.mainWindowID

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = TerminalWorkspaceViewController(workspace: workspace, windowID: windowID)
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
    static let paneHeaderHeight = UIFloat(48)
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
    static let tabChromeFocused = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.16)
        }
        return UIColor.white.withAlphaComponent(0.92)
    }
    static let tabChromeUnfocused = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.08)
        }
        return UIColor.black.withAlphaComponent(0.05)
    }
    static let tabChromeStroke = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.2)
        }
        return UIColor.black.withAlphaComponent(0.1)
    }
    static let tabTitleFocused = UIColor.label
    static let tabTitleUnfocused = UIColor.secondaryLabel
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

// MARK: - SSH Timeout Helper

/// Resumes a continuation exactly once from whichever finishes first:
/// the SSH work or the timeout. The abandoned work keeps running in the
/// background (SSH calls are not cancellation-aware) and its result is dropped.
private final class TerminalSSHTimeoutResumeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(with continuation: CheckedContinuation<T?, Never>, value: T?) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}

/// Runs an SSH operation with an upper time bound so one unreachable server
/// cannot stall discovery or session operations for the remaining servers.
/// Returns `nil` on timeout.
nonisolated private func withTerminalSSHTimeout<T: Sendable>(
    seconds: UInt64 = 15,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withCheckedContinuation { continuation in
        let box = TerminalSSHTimeoutResumeBox<T>()
        Task {
            let value = await operation()
            box.resume(with: continuation, value: value)
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            box.resume(with: continuation, value: nil)
        }
    }
}

/// Fixed palette used to color-code tmux sessions that don't inherit a shortcut color.
enum TerminalSessionPalette {
    static let colors = [
        "#10B981", "#3B82F6", "#8B5CF6", "#EC4899", "#F59E0B",
        "#EF4444", "#14B8A6", "#6366F1", "#84CC16", "#F97316"
    ]

    nonisolated static func color(for key: String) -> String {
        var hash = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

// MARK: - Workspace View Controller

@MainActor
final class TerminalWorkspaceViewController: UIViewController, UIGestureRecognizerDelegate {
    private let workspace: TerminalWorkspaceStore
    private let terminalManager = TerminalNavigationManager.shared
    private let hardwareInput = TerminalHardwareInputController()
    private let shakeInput = TerminalShakeInputController()
    private let settingsStore = TerminalSettingsStore.shared

    private enum InputConfirmationKeys {
        static let didConfirmVolumeInput = "terminal.hardware.confirmed.volume"
        static let didConfirmShakeInput = "terminal.hardware.confirmed.shake"
    }

    private let navigationTitleMenuButton = UIButton(type: .system)
    private lazy var tabBarCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = UIFloat(4)
        layout.minimumLineSpacing = UIFloat(4)
        layout.sectionInset = UIEdgeInsets(top: UIFloat(4), left: UIFloat(4), bottom: UIFloat(4), right: UIFloat(4))
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceHorizontal = true
        return cv
    }()
    private lazy var tabBarDataSource = makeTabBarDataSource()
    private let tabBarNewButton = UIButton(type: .system)
    private let tabBarCollapseButton = UIButton(type: .system)
    private let tabBarHeight = UIFloat(40)
    private let paneContainerView = UIView()
    private let keyboardBarView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let keyboardSuggestionsContainerView = UIView()
    private let keyboardControlsContainer = UIView()
    private let keyboardStackView = UIStackView()
    private let messageLabel = UILabel()
    private let completionOverlayView = TerminalCompletionOverlayView()
    private lazy var swipeLeftRecognizer: UISwipeGestureRecognizer = {
        let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(didSwipePane(_:)))
        recognizer.direction = .left
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var swipeRightRecognizer: UISwipeGestureRecognizer = {
        let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(didSwipePane(_:)))
        recognizer.direction = .right
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    private var paneControllers: [UUID: TerminalPaneViewController] = [:]

    private var keyboardVisible = false
    private var activeControllerIDForKeyboard: UUID?
    private var pendingCursorAnchor: CGPoint?
    private var pendingCursorCellHeight: CGFloat = 0
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

    /// The OS window this workspace renders. Each window shows only its own tabs.
    private let windowID: String

    /// The single pane backing this window.
    private var windowPaneID: UUID {
        workspace.paneID(forWindow: windowID)
    }

    @MainActor
    init(workspace: TerminalWorkspaceStore, windowID: String = TerminalWorkspaceStore.mainWindowID) {
        self.workspace = workspace
        self.windowID = windowID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        navigationController?.setNavigationBarHidden(true, animated: false)
        configureHardwareInputs()
        refreshNavigationChrome()
        processPendingRequests()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Tag this window's scene so we can identify it when it's closed.
        if let session = view.window?.windowScene?.session {
            var info = session.userInfo ?? [:]
            info["terminalWindowID"] = windowID
            session.userInfo = info
        }
        TerminalWindowRouter.shared.installSceneDisconnectObserverIfNeeded()
        // A window always has at least one tab (macOS-style); an empty tab shows
        // the shortcuts view until a session is launched into it.
        workspace.ensureAtLeastOneTab(inWindow: windowID)
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
        handleEmptyWindowIfNeeded()
    }

    /// Closing the last tab closes the window. The main window can't close, so it
    /// gets a fresh empty tab instead (macOS-style).
    private func handleEmptyWindowIfNeeded() {
        guard workspace.tabStates(in: windowPaneID).isEmpty else { return }
        if windowID == TerminalWorkspaceStore.mainWindowID {
            workspace.ensureAtLeastOneTab(inWindow: windowID)
        } else if let session = view.window?.windowScene?.session {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
        }
    }

    // MARK: Setup

    private func configureBaseUI() {
        view.backgroundColor = TerminalUIColors.workspaceBackground

        configureTabBar()

        // Accept tabs dragged in from other windows.
        view.addInteraction(UIDropInteraction(delegate: self))

        paneContainerView.backgroundColor = .clear
        view.addSubview(paneContainerView)
        paneContainerView.addGestureRecognizer(swipeLeftRecognizer)
        paneContainerView.addGestureRecognizer(swipeRightRecognizer)

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

        completionOverlayView.isHidden = true
        view.addSubview(completionOverlayView)
    }

    private func configureNavigationItems() {
        navigationItem.titleView = nil
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItems = nil
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
            _ = self.workspace.activeController(inWindow: self.windowID)?.id
            _ = self.workspace.activeController(inWindow: self.windowID)?.controlModifierArmed
            _ = self.workspace.activeController(inWindow: self.windowID)?.suggestions
            _ = self.workspace.activeController(inWindow: self.windowID)?.currentInputBuffer
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
        return
    }

    private func titleTextForFocusedPane() -> String {
        if let active = workspace.activeTab(in: windowPaneID) {
            return active.title
        }
        return "Terminal"
    }

    private func makeTitleMenu() -> UIMenu {
        var actions: [UIMenuElement] = [
            UIAction(title: "New Tab", image: UIImage(systemName: "plus")) { [weak self] _ in
                guard let self else { return }
                self.workspace.beginNewTab(inWindow: self.windowID)
            }
        ]

        let tabActions = paneSwitchActions()
        if !tabActions.isEmpty {
            actions.append(UIMenu(title: "", options: .displayInline, children: tabActions))
        }

        if workspace.windowIDsWithTabs().count > 1 {
            actions.append(UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: "Merge All Windows Here", image: UIImage(systemName: "arrow.down.right.and.arrow.up.left.rectangle")) { [weak self] _ in
                    self?.collapseWindows()
                }
            ]))
        }

        return UIMenu(children: actions)
    }

    private func paneSwitchActions() -> [UIAction] {
        let selectedTabID = workspace.activeTab(in: windowPaneID)?.id

        return workspace.tabStates(in: windowPaneID).map { tab in
            let isSelected = tab.id == selectedTabID
            return UIAction(
                title: tab.title,
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.workspace.setActiveTab(tabID: tab.id, in: self.windowPaneID)
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

        // Reserve the tab strip at the top of the workspace area. Shown on iPad/Mac
        // regardless of window size (iPad windows resize); iPhone keeps its
        // swipe/overview UX.
        let hasTabs = !workspace.tabStates(in: windowPaneID).isEmpty
        let showTabBar = hasTabs && traitCollection.userInterfaceIdiom != .phone
        if showTabBar {
            let tabRect = CGRect(x: layoutRect.minX, y: layoutRect.minY, width: layoutRect.width, height: tabBarHeight)
            tabBarCollectionView.isHidden = false
            tabBarNewButton.isHidden = false
            layoutTabBar(in: tabRect)
            layoutRect = CGRect(x: layoutRect.minX, y: tabRect.maxY + UIFloat(4), width: layoutRect.width, height: max(0, layoutRect.height - tabBarHeight - UIFloat(4)))
        } else {
            tabBarCollectionView.isHidden = true
            tabBarNewButton.isHidden = true
            tabBarCollapseButton.isHidden = true
        }

        paneContainerView.frame = layoutRect
        layoutPaneControllers(in: paneContainerView.bounds)

        if !completionOverlayView.isHidden {
            let count = workspace.activeController(inWindow: self.windowID)?.suggestions.prefix(8).count ?? 0
            let overlayHeight = TerminalCompletionOverlayView.preferredHeight(for: count)
            let overlayWidth = TerminalCompletionOverlayView.preferredWidth

            // Use the focused pane's frame for positioning, not the entire pane container.
            let focusedPaneFrame: CGRect = {
                if let focusedID = workspace.focusedPaneID,
                   let paneVC = paneControllers[focusedID] {
                    return paneVC.view.convert(paneVC.view.bounds, to: view)
                }
                return paneContainerView.frame
            }()

            if let anchor = pendingCursorAnchor {
                let sourceView: UIView = {
                    if let focusedID = workspace.focusedPaneID,
                       let paneVC = paneControllers[focusedID],
                       let hostView = paneVC.activeHostView {
                        return hostView
                    }
                    return paneContainerView
                }()
                let anchorInView = sourceView.convert(anchor, to: view)
                let gap = UIFloat(4)
                let cellH = pendingCursorCellHeight > 0 ? pendingCursorCellHeight : TerminalCompletionOverlayView.itemHeight
                var x = anchorInView.x
                // Default: place below the cursor line
                var y = anchorInView.y + gap
                x = max(focusedPaneFrame.minX + TerminalUIMetrics.pageInset, min(x, focusedPaneFrame.maxX - overlayWidth - TerminalUIMetrics.pageInset))
                // If overlay would go below the focused pane, flip above the cursor line
                if y + overlayHeight > focusedPaneFrame.maxY - TerminalUIMetrics.pageInset {
                    y = anchorInView.y - cellH - gap - overlayHeight
                }
                // If flipping above pushed it past the top, just place at the top of the pane
                if y < focusedPaneFrame.minY + TerminalUIMetrics.pageInset {
                    y = focusedPaneFrame.minY + TerminalUIMetrics.pageInset
                }
                completionOverlayView.frame = CGRect(x: x, y: y, width: overlayWidth, height: overlayHeight)
            } else {
                completionOverlayView.frame = CGRect(
                    x: focusedPaneFrame.minX + TerminalUIMetrics.pageInset,
                    y: focusedPaneFrame.maxY - overlayHeight - TerminalUIMetrics.pageInset,
                    width: overlayWidth,
                    height: overlayHeight
                )
            }
        }
    }

    private func layoutPaneControllers(in bounds: CGRect) {
        // One pane per window — it fills the pane container (split removed).
        paneControllers[windowPaneID]?.view.frame = bounds
    }

    // MARK: Tab Bar

    private func configureTabBar() {
        tabBarCollectionView.delegate = self
        tabBarCollectionView.dragDelegate = self
        tabBarCollectionView.dropDelegate = self
        tabBarCollectionView.dragInteractionEnabled = true
        _ = tabBarDataSource
        view.addSubview(tabBarCollectionView)

        tabBarNewButton.setImage(UIImage(systemName: "plus"), for: .normal)
        tabBarNewButton.tintColor = .label
        tabBarNewButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.workspace.beginNewTab(inWindow: self.windowID)
        }, for: .touchUpInside)
        view.addSubview(tabBarNewButton)

        tabBarCollapseButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left.rectangle"), for: .normal)
        tabBarCollapseButton.tintColor = .label
        tabBarCollapseButton.addAction(UIAction { [weak self] _ in
            self?.collapseWindows()
        }, for: .touchUpInside)
        view.addSubview(tabBarCollapseButton)
    }

    private func makeTabBarDataSource() -> UICollectionViewDiffableDataSource<Int, UUID> {
        let registration = UICollectionView.CellRegistration<TerminalTabBarCell, UUID> { [weak self] cell, _, tabID in
            guard let self, let tab = self.workspace.tabState(id: tabID) else { return }
            let isActive = self.workspace.activeTab(in: self.windowPaneID)?.id == tabID
            cell.configure(title: tab.title, colorHex: tab.shortcutColorHex, isActive: isActive)
            cell.onClose = { [weak self] in self?.workspace.closeTab(tabID: tabID) }
        }
        return UICollectionViewDiffableDataSource<Int, UUID>(collectionView: tabBarCollectionView) { collectionView, indexPath, tabID in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: tabID)
        }
    }

    private func collapseWindows() {
        // Merge every window's tabs into this window, then dismiss the others.
        let otherWindowIDs = workspace.windowIDsWithTabs().filter { $0 != windowID }
        workspace.collapseAllWindows(into: windowID)
        for otherWindowID in otherWindowIDs {
            TerminalWindowRouter.shared.dismiss(TerminalWindowTarget(windowID: otherWindowID))
        }
        // Fallback for windows the system opened (not value-backed) that
        // dismissWindow(value:) can't target.
        TerminalWindowRouter.shared.closeSecondaryWindows()
    }

    private func moveTabToNewWindow(tabID: UUID) {
        guard TerminalWindowRouter.shared.supportsMultipleWindows else { return }
        let newWindowID = UUID().uuidString
        workspace.moveTab(tabID: tabID, toWindow: newWindowID)
        TerminalWindowRouter.shared.open(TerminalWindowTarget(windowID: newWindowID))
    }

    private func layoutTabBar(in topRect: CGRect) {
        let buttonWidth = UIFloat(40)
        let showCollapse = workspace.windowIDsWithTabs().count > 1
        tabBarCollapseButton.isHidden = !showCollapse
        let collapseWidth = showCollapse ? buttonWidth : 0

        tabBarNewButton.frame = CGRect(x: topRect.maxX - buttonWidth, y: topRect.minY, width: buttonWidth, height: topRect.height)
        tabBarCollapseButton.frame = CGRect(x: topRect.maxX - buttonWidth - collapseWidth, y: topRect.minY, width: collapseWidth, height: topRect.height)

        tabBarCollectionView.frame = CGRect(
            x: topRect.minX,
            y: topRect.minY,
            width: max(0, topRect.width - buttonWidth - collapseWidth),
            height: topRect.height
        )
        tabBarCollectionView.collectionViewLayout.invalidateLayout()
    }

    func refreshTabBar() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(workspace.tabStates(in: windowPaneID).map(\.id), toSection: 0)
        tabBarDataSource.apply(snapshot, animatingDifferences: false)
        // Refresh active-state styling on existing cells.
        var reconfigure = tabBarDataSource.snapshot()
        if !reconfigure.itemIdentifiers.isEmpty {
            reconfigure.reconfigureItems(reconfigure.itemIdentifiers)
            tabBarDataSource.apply(reconfigure, animatingDifferences: false)
        }
        view.setNeedsLayout()
    }

    private func tabContextMenu(for tab: TerminalTabState) -> UIMenu {
        var actions: [UIMenuElement] = []
        if TerminalWindowRouter.shared.supportsMultipleWindows {
            actions.append(UIAction(title: "Open in New Window", image: UIImage(systemName: "macwindow.badge.plus")) { [weak self] _ in
                self?.moveTabToNewWindow(tabID: tab.id)
            })
            let otherWindows = self.workspace.windowIDsWithTabs().filter { $0 != self.windowID }
            for otherWindow in otherWindows {
                let name = otherWindow == TerminalWorkspaceStore.mainWindowID ? "Main Window" : "Other Window"
                actions.append(UIAction(title: "Move to \(name)", image: UIImage(systemName: "arrow.right.square")) { [weak self] _ in
                    self?.workspace.moveTab(tabID: tab.id, toWindow: otherWindow)
                })
            }
            if self.workspace.windowIDsWithTabs().count > 1 {
                actions.append(UIAction(title: "Merge All Windows Here", image: UIImage(systemName: "arrow.down.right.and.arrow.up.left.rectangle")) { [weak self] _ in
                    self?.collapseWindows()
                })
            }
        }
        actions.append(UIAction(title: "Close Tab", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in
            self?.workspace.closeTab(tabID: tab.id)
        })
        return UIMenu(children: actions)
    }

    // MARK: Pane Sync

    private func syncPaneControllers() {
        let visiblePaneIDs: Set<UUID> = [windowPaneID]

        let idsToRemove = Set(paneControllers.keys).subtracting(visiblePaneIDs)
        for paneID in idsToRemove {
            guard let controller = paneControllers[paneID] else { continue }
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            paneControllers[paneID] = nil
        }

        let controller: TerminalPaneViewController
        if let existing = paneControllers[windowPaneID] {
            controller = existing
        } else {
            let created = TerminalPaneViewController(paneID: windowPaneID, workspace: workspace)
            created.delegate = self
            addChild(created)
            paneContainerView.addSubview(created.view)
            created.didMove(toParent: self)
            paneControllers[windowPaneID] = created
            controller = created
        }

        controller.refreshFromWorkspace()
        controller.applyDisplaySettings(fontSize: settingsStore.state.display.fontSize)
        paneContainerView.bringSubviewToFront(controller.view)

        refreshTabBar()
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

    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac
    }

    /// Whether this VC's window is the focused one. The keyboard bar and
    /// suggestions must only appear in the active window, not every open window.
    private var isWindowActive: Bool {
        guard let scene = view.window?.windowScene else { return true }
        return scene.activationState == .foregroundActive
    }

    private var shouldShowKeyboardBar: Bool {
        isWindowActive && keyboardVisible && workspace.activeController(inWindow: self.windowID) != nil
    }

    private var shouldShowCompletionOverlay: Bool {
        guard isWindowActive else { return false }
        let keyboardAbsent = isRunningOnMac || !keyboardVisible
        guard keyboardAbsent, let controller = workspace.activeController(inWindow: self.windowID) else {
            return false
        }
        return !controller.suggestions.isEmpty
    }

    private func updateKeyboardBarVisibility() {
        updateKeyboardSuggestionButtons()
        keyboardBarView.isHidden = !shouldShowKeyboardBar
        updateKeyboardButtonsState()
        updateCompletionOverlay()
        view.setNeedsLayout()
    }

    private func updateCompletionOverlay() {
        guard shouldShowCompletionOverlay, let controller = workspace.activeController(inWindow: self.windowID) else {
            if !completionOverlayView.isHidden {
                pendingCursorAnchor = nil
                UIView.animate(withDuration: 0.15, animations: {
                    self.completionOverlayView.alpha = 0
                }, completion: { _ in
                    self.completionOverlayView.isHidden = true
                    self.completionOverlayView.alpha = 1
                })
            }
            return
        }

        let suggestions = Array(controller.suggestions.prefix(8))
        let typedInput = controller.currentInputBuffer
        let selectedIndex = min(controller.selectedSuggestionIndex, max(0, suggestions.count - 1))
        completionOverlayView.onSelectionChanged = { [weak controller] newIndex in
            controller?.selectedSuggestionIndex = newIndex
        }
        completionOverlayView.update(
            suggestions: suggestions,
            typedInput: typedInput,
            selectedIndex: selectedIndex
        ) { [weak self, weak controller] suggestion in
            controller?.applySuggestion(suggestion.text)
            controller?.focus()
            self?.view.setNeedsLayout()
        }

        if completionOverlayView.isHidden {
            completionOverlayView.alpha = 0
            completionOverlayView.isHidden = false
            UIView.animate(withDuration: 0.15) { self.completionOverlayView.alpha = 1 }
        }

        // Fetch cursor position for Xcode-style popover positioning.
        Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            if let cursorInfo = await controller.cursorScreenPosition() {
                self.pendingCursorAnchor = cursorInfo.point
                self.pendingCursorCellHeight = cursorInfo.cellHeight
            } else {
                self.pendingCursorAnchor = nil
            }
            self.view.setNeedsLayout()
        }
    }

    private func updateKeyboardSuggestionButtons() {
        let wasVisible = !keyboardSuggestionButtons.isEmpty

        guard let controller = workspace.activeController(inWindow: self.windowID) else {
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
        guard let controller = workspace.activeController(inWindow: self.windowID) else {
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
        guard let controller = workspace.activeController(inWindow: self.windowID) else {
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

    // MARK: Hardware Keyboard Arrow Navigation

    override var keyCommands: [UIKeyCommand]? {
        guard !completionOverlayView.isHidden else { return nil }
        let up = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(completionArrowUp))
        let down = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(completionArrowDown))
        up.wantsPriorityOverSystemBehavior = true
        down.wantsPriorityOverSystemBehavior = true
        return [up, down]
    }

    @objc private func completionArrowUp() {
        guard let controller = workspace.activeController(inWindow: self.windowID) else { return }
        completionOverlayView.moveSelection(by: -1, count: min(controller.suggestions.count, 8))
    }

    @objc private func completionArrowDown() {
        guard let controller = workspace.activeController(inWindow: self.windowID) else { return }
        completionOverlayView.moveSelection(by: 1, count: min(controller.suggestions.count, 8))
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
                guard let self, let controller = self.workspace.activeController(inWindow: self.windowID) else { return }
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
            workspace.openTab(credentialKey: request.credentialKey, windowID: windowID)
            showMessage("Connected to \(request.label)")
        }

        terminalManager.showingDeeplinkConfirmation = false
    }

    // MARK: Actions

    @objc
    private func didTapAddPane() {
        workspace.beginNewTab(inWindow: windowID)
    }

    @objc
    private func didTapSnippets() {
        let currentCredentialKey = workspace.activeController(inWindow: self.windowID)?.credentialKey
        let picker = TerminalSnippetPickerViewController(
            database: SharedDatabase.db,
            credentialKey: currentCredentialKey
        ) { [weak self] snippet in
            guard let self else { return }
            self.workspace.activeController(inWindow: self.windowID)?.applySuggestion(snippet.command)
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
              let controller = workspace.activeController(inWindow: self.windowID)
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

    @objc
    private func didSwipePane(_ recognizer: UISwipeGestureRecognizer) {
        // Switch between this window's tabs (Safari-style).
        let tabIDs = workspace.tabStates(in: windowPaneID).map(\.id)
        guard tabIDs.count > 1 else { return }
        let activeID = workspace.activeTab(in: windowPaneID)?.id
        let currentIndex = activeID.flatMap { tabIDs.firstIndex(of: $0) } ?? 0

        let nextIndex: Int
        switch recognizer.direction {
        case .left:
            guard currentIndex < tabIDs.count - 1 else { return }
            nextIndex = currentIndex + 1
        case .right:
            guard currentIndex > 0 else { return }
            nextIndex = currentIndex - 1
        default:
            return
        }

        workspace.setActiveTab(tabID: tabIDs[nextIndex], in: windowPaneID)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === swipeLeftRecognizer || gestureRecognizer === swipeRightRecognizer else {
            return true
        }

        // Keep terminal interactions untouched: only treat swipes that start in the compact header strip.
        let point = touch.location(in: paneContainerView)
        let headerActivationHeight = TerminalUIMetrics.paneHeaderHeight + UIFloat(18)
        return point.y <= headerActivationHeight
    }
}

// MARK: - Workspace Delegate

extension TerminalWorkspaceViewController: TerminalPaneViewControllerDelegate {
    func terminalPane(_ pane: TerminalPaneViewController, didRequestMessage message: String) {
        showMessage(message)
    }
}

extension TerminalWorkspaceViewController: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil && droppedTabID(from: session) != nil
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: droppedTabID(from: session) != nil ? .move : .cancel)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let tabID = droppedTabID(from: session) else { return }
        workspace.moveTab(tabID: tabID, toWindow: windowID)
    }

    private func droppedTabID(from session: UIDropSession) -> UUID? {
        for item in session.items {
            if let value = item.localObject as? String, let id = UUID(uuidString: value) {
                return id
            }
        }
        return nil
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
final class TerminalPaneViewController: UIViewController, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
    weak var delegate: TerminalPaneViewControllerDelegate?

    private let paneID: UUID
    private let workspace: TerminalWorkspaceStore
    private let settingsStore = TerminalSettingsStore.shared

    private let headerView = UIView()
    private let contentView = UIView()
    private let leadingChromeView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let centerChromeView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let trailingChromeView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let tabTitleLabel = UILabel()
    private let cwdLabel = UILabel()
    private let warningLabel = UILabel()
    private let allTabsButton = UIButton(type: .system)
    private let overflowButton = UIButton(type: .system)

    private(set) var activeHostView: XTermWebHostView?
    private var serverPickerController: TerminalServerPickerViewController?
    private var observedControllerID: UUID?
    private var lastPresentedPromptID: UUID?
    private var pinchBaseFontSize: Int = 13
    private var pinchLastDeltaSteps = 0
    private var pendingEdgeSwipeDirection: UISwipeGestureRecognizer.Direction?
    private var pendingEdgeSwipeExpiry: Date?

    init(paneID: UUID, workspace: TerminalWorkspaceStore) {
        self.paneID = paneID
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    private var paneWindowID: String {
        workspace.windowID(forPane: paneID) ?? TerminalWorkspaceStore.mainWindowID
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

        headerView.backgroundColor = .clear
        view.addSubview(headerView)

        contentView.backgroundColor = .clear
        view.addSubview(contentView)

        [leadingChromeView, centerChromeView, trailingChromeView].forEach { chrome in
            chrome.layer.cornerCurve = .continuous
            chrome.layer.borderWidth = UIFloat(1)
            chrome.layer.borderColor = TerminalUIColors.tabChromeStroke.cgColor
            chrome.clipsToBounds = true
            headerView.addSubview(chrome)
        }
        leadingChromeView.layer.cornerRadius = UIFloat(20)
        centerChromeView.layer.cornerRadius = UIFloat(20)
        trailingChromeView.layer.cornerRadius = UIFloat(20)

        tabTitleLabel.font = UIFont.systemFont(ofSize: UIFloat(12), weight: .semibold)
        tabTitleLabel.textColor = TerminalUIColors.tabTitleUnfocused
        tabTitleLabel.lineBreakMode = .byTruncatingTail
        centerChromeView.contentView.addSubview(tabTitleLabel)

        cwdLabel.font = UIFont.systemFont(ofSize: UIFloat(10), weight: .regular)
        cwdLabel.textColor = TerminalUIColors.secondaryText
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        headerView.addSubview(cwdLabel)

        warningLabel.font = UIFont.systemFont(ofSize: UIFloat(10), weight: .regular)
        warningLabel.textColor = UIColor.systemRed
        warningLabel.lineBreakMode = .byTruncatingTail
        warningLabel.isHidden = true
        headerView.addSubview(warningLabel)

        allTabsButton.setImage(UIImage(systemName: "square.grid.2x2"), for: .normal)
        allTabsButton.tintColor = UIColor.secondaryLabel
        allTabsButton.addTarget(self, action: #selector(didTapAllTabsButton), for: .touchUpInside)
        leadingChromeView.contentView.addSubview(allTabsButton)

        overflowButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        overflowButton.tintColor = UIColor.secondaryLabel
        overflowButton.showsMenuAsPrimaryAction = true
        overflowButton.menu = makeOverflowMenu()
        trailingChromeView.contentView.addSubview(overflowButton)

        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeCompactBar(_:)))
        swipeLeft.direction = .left
        centerChromeView.addGestureRecognizer(swipeLeft)
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeCompactBar(_:)))
        swipeRight.direction = .right
        centerChromeView.addGestureRecognizer(swipeRight)
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeUpOnCompactBar(_:)))
        swipeUp.direction = .up
        centerChromeView.addGestureRecognizer(swipeUp)

        let contextInteraction = UIContextMenuInteraction(delegate: self)
        centerChromeView.addInteraction(contextInteraction)
    }

    // MARK: Refresh

    func refreshFromWorkspace() {
        let focused = workspace.focusedPaneID == paneID
        let activeTab = workspace.activeTab(in: paneID)
        overflowButton.menu = makeOverflowMenu()

        updateCompactTabChrome(isFocused: focused, activeTab: activeTab)

        guard let activeTab,
              let controller = workspace.controller(for: activeTab.id)
        else {
            observedControllerID = nil
            tabTitleLabel.text = "Choose a server"
            cwdLabel.text = ""
            warningLabel.isHidden = true
            allTabsButton.alpha = 1
            showServerPicker()
            view.setNeedsLayout()
            return
        }

        allTabsButton.alpha = 1
        tabTitleLabel.text = activeTab.title
        cwdLabel.text = controller.cwd
        if controller.shellIntegrationStatus == .warning, let warning = controller.lastShellIntegrationWarning {
            warningLabel.text = warning
            warningLabel.isHidden = false
        } else {
            warningLabel.isHidden = true
        }

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
            _ = controller.lastShellIntegrationWarning
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
        var inner = view.bounds.inset(by: UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: 0
        ))

        // iPad/Mac use the top tab bar instead of this compact bottom chrome.
        let usesTopTabBar = traitCollection.userInterfaceIdiom != .phone
        headerView.isHidden = usesTopTabBar
        let headerHeight = usesTopTabBar ? 0 : TerminalUIMetrics.paneHeaderHeight

        let headerSplit = inner.split(at: headerHeight, from: .maxYEdge)
        headerView.frame = headerSplit.slice
        inner = headerSplit.remainder

        contentView.frame = inner

        if !usesTopTabBar {
            layoutHeaderViews(in: headerView.bounds)
        }
        activeHostView?.frame = contentView.bounds
        serverPickerController?.view.frame = contentView.bounds
    }

    private func layoutHeaderViews(in bounds: CGRect) {
        let buttonSize = UIFloat(40)
        let chromeHeight = UIFloat(40)
        let spacing = UIFloat(10)
        let y = (bounds.height - chromeHeight) / 2

        leadingChromeView.frame = CGRect(x: 0, y: y, width: buttonSize, height: buttonSize)
        trailingChromeView.frame = CGRect(x: bounds.width - buttonSize, y: y, width: buttonSize, height: buttonSize)
        centerChromeView.frame = CGRect(
            x: leadingChromeView.frame.maxX + spacing,
            y: y,
            width: max(UIFloat(120), trailingChromeView.frame.minX - (leadingChromeView.frame.maxX + spacing * 2)),
            height: chromeHeight
        )

        allTabsButton.frame = leadingChromeView.bounds.insetBy(dx: UIFloat(10), dy: UIFloat(10))
        overflowButton.frame = trailingChromeView.bounds.insetBy(dx: UIFloat(10), dy: UIFloat(10))
        tabTitleLabel.textAlignment = .center
        tabTitleLabel.frame = centerChromeView.bounds.insetBy(dx: UIFloat(14), dy: UIFloat(8))
        cwdLabel.frame = .zero
        warningLabel.frame = .zero
    }

    private func updateCompactTabChrome(isFocused: Bool, activeTab: TerminalTabState?) {
        if isFocused {
            centerChromeView.contentView.backgroundColor = TerminalUIColors.tabChromeFocused
            leadingChromeView.contentView.backgroundColor = TerminalUIColors.tabChromeFocused
            trailingChromeView.contentView.backgroundColor = TerminalUIColors.tabChromeFocused
            tabTitleLabel.textColor = TerminalUIColors.tabTitleFocused
        } else {
            centerChromeView.contentView.backgroundColor = TerminalUIColors.tabChromeUnfocused
            leadingChromeView.contentView.backgroundColor = TerminalUIColors.tabChromeUnfocused
            trailingChromeView.contentView.backgroundColor = TerminalUIColors.tabChromeUnfocused
            tabTitleLabel.textColor = TerminalUIColors.tabTitleUnfocused
        }
        if let hex = activeTab?.shortcutColorHex, let accent = UIColor(hex: hex) {
            [leadingChromeView, centerChromeView, trailingChromeView].forEach {
                $0.layer.borderColor = accent.withAlphaComponent(0.55).cgColor
            }
        } else {
            [leadingChromeView, centerChromeView, trailingChromeView].forEach {
                $0.layer.borderColor = TerminalUIColors.tabChromeStroke.cgColor
            }
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
        picker.windowID = paneWindowID
        picker.excludedSessionKeys = workspace.sessionKeysBoundToOtherWindows(excluding: paneWindowID)
        picker.onSelection = { [weak self] selection in
            guard let self else { return }
            self.workspace.focusPane(paneID: self.paneID)
            // Launch into the current empty tab in place, rather than a new tab.
            let emptyTabID = self.workspace.activeTab(in: self.paneID)
                .flatMap { self.workspace.isTabEmpty($0.id) ? $0.id : nil }
            switch selection {
            case let .shortcut(shortcut):
                let tmuxSessionName = TerminalServerPickerViewController.newTmuxSessionName(for: shortcut)
                if let emptyTabID {
                    self.workspace.fillTab(
                        tabID: emptyTabID,
                        credentialKey: shortcut.credentialKey,
                        preferredTitle: shortcut.title,
                        themeOverrideSelectionKey: shortcut.themeSelectionKey,
                        shortcutColorHex: shortcut.colorHex,
                        tmuxSessionName: tmuxSessionName,
                        tmuxAttachOnly: false,
                        disableAutoPersistentSession: true
                    )
                } else {
                    self.workspace.openTab(
                        credentialKey: shortcut.credentialKey,
                        preferredTitle: shortcut.title,
                        windowID: self.paneWindowID,
                        themeOverrideSelectionKey: shortcut.themeSelectionKey,
                        shortcutColorHex: shortcut.colorHex,
                        tmuxSessionName: tmuxSessionName,
                        tmuxAttachOnly: false,
                        disableAutoPersistentSession: true
                    )
                }
                self.launchStartupScriptIfNeeded(shortcut.startupScript, credentialKey: shortcut.credentialKey)
            case let .tmuxSession(target):
                if let emptyTabID {
                    self.workspace.fillTab(
                        tabID: emptyTabID,
                        credentialKey: target.credentialKey,
                        preferredTitle: target.title,
                        shortcutColorHex: target.colorHex ?? "#10B981",
                        tmuxSessionName: target.sessionName,
                        tmuxAttachOnly: true
                    )
                } else {
                    self.workspace.openTab(
                        credentialKey: target.credentialKey,
                        preferredTitle: target.title,
                        windowID: self.paneWindowID,
                        themeOverrideSelectionKey: nil,
                        shortcutColorHex: target.colorHex ?? "#10B981",
                        tmuxSessionName: target.sessionName,
                        tmuxAttachOnly: true
                    )
                }
            }
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
        host.layer.cornerRadius = 0
        host.clipsToBounds = false

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

        Task { [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self else { return }
                guard let controller = self.workspace.activeController(inWindow: self.paneWindowID) else { continue }
                guard controller.credentialKey == credentialKey else { continue }
                guard controller.connectionStatus == .connected else { continue }
                guard !controller.isBootstrapPending else { continue }

                if !trimmed.isEmpty {
                    controller.sendInput(trimmed)
                }
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
    private func didTapAllTabsButton() {
        presentAllTabs()
    }

    private func makeOverflowMenu() -> UIMenu {
        var actions: [UIAction] = [
            UIAction(title: "New Tab", image: UIImage(systemName: "plus")) { [weak self] _ in
                guard let self else { return }
                self.workspace.beginNewTab(inWindow: self.paneWindowID)
            },
            UIAction(title: "View All Tabs", image: UIImage(systemName: "square.grid.2x2")) { [weak self] _ in
                self?.presentAllTabs()
            },
        ]

        if let active = workspace.activeTab(in: paneID),
           let session = active.tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !session.isEmpty {
            actions.append(UIAction(title: "Rename Session", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.promptRenameActiveSession(sessionName: session, credentialKey: active.credentialKey)
            })
            actions.append(UIAction(
                title: "Close Session",
                image: UIImage(systemName: "xmark.circle"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.closeSession(credentialKey: active.credentialKey, sessionName: session)
            })
        }
        return UIMenu(children: actions)
    }

    @objc
    private func didSwipeUpOnCompactBar(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.direction == .up else { return }
        presentAllTabs()
    }

    @objc
    private func didSwipeCompactBar(_ recognizer: UISwipeGestureRecognizer) {
        let tabIDs = workspace.tabStates(in: paneID).map(\.id)
        guard !tabIDs.isEmpty else {
            handleEdgeSwipeForNewTab(direction: recognizer.direction)
            return
        }
        let activeID = workspace.activeTab(in: paneID)?.id
        let currentIndex = activeID.flatMap { tabIDs.firstIndex(of: $0) } ?? 0

        let nextIndex: Int
        if recognizer.direction == .left {
            guard currentIndex < tabIDs.count - 1 else {
                handleEdgeSwipeForNewTab(direction: .left)
                return
            }
            nextIndex = currentIndex + 1
        } else if recognizer.direction == .right {
            guard currentIndex > 0 else {
                handleEdgeSwipeForNewTab(direction: .right)
                return
            }
            nextIndex = currentIndex - 1
        } else {
            return
        }
        pendingEdgeSwipeDirection = nil
        pendingEdgeSwipeExpiry = nil
        workspace.setActiveTab(tabID: tabIDs[nextIndex], in: paneID)
    }

    private func handleEdgeSwipeForNewTab(direction: UISwipeGestureRecognizer.Direction) {
        let now = Date()
        if pendingEdgeSwipeDirection == direction,
           let expiry = pendingEdgeSwipeExpiry,
           now <= expiry {
            pendingEdgeSwipeDirection = nil
            pendingEdgeSwipeExpiry = nil
            workspace.beginNewTab(inWindow: paneWindowID)
            delegate?.terminalPane(self, didRequestMessage: "Created new tab")
            return
        }
        pendingEdgeSwipeDirection = direction
        pendingEdgeSwipeExpiry = now.addingTimeInterval(1.4)
        delegate?.terminalPane(self, didRequestMessage: "Swipe again to create a new tab")
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }
            var actions: [UIAction] = []

            actions.append(UIAction(title: "View All Tabs", image: UIImage(systemName: "square.grid.2x2")) { _ in
                self.presentAllTabs()
            })
            actions.append(UIAction(title: "New Tab", image: UIImage(systemName: "plus")) { _ in
                self.workspace.beginNewTab(inWindow: self.paneWindowID)
            })
            if let active = self.workspace.activeTab(in: self.paneID),
               let session = active.tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !session.isEmpty {
                actions.append(UIAction(title: "Rename Session", image: UIImage(systemName: "pencil")) { _ in
                    self.promptRenameActiveSession(sessionName: session, credentialKey: active.credentialKey)
                })
                actions.append(UIAction(title: "Close Session", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in
                    self.closeSession(credentialKey: active.credentialKey, sessionName: session)
                })
            }
            return UIMenu(children: actions)
        }
    }

    private func promptRenameActiveSession(sessionName: String, credentialKey: String) {
        let alert = UIAlertController(title: "Rename session", message: sessionName, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = sessionName
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default, handler: { _ in
            let newName = XTermSessionController.normalizeTmuxSessionName(alert.textFields?.first?.text ?? "")
            guard !newName.isEmpty else { return }
            self.renameSession(credentialKey: credentialKey, oldName: sessionName, newName: newName)
        }))
        present(alert, animated: true)
    }

    private func renameSession(credentialKey: String, oldName: String, newName: String) {
        guard let credential = keychain().getCredential(for: credentialKey) else { return }
        let oldEscaped = XTermSessionController.normalizeTmuxSessionName(oldName).replacingOccurrences(of: "'", with: "'\"'\"'")
        let newEscaped = XTermSessionController.normalizeTmuxSessionName(newName).replacingOccurrences(of: "'", with: "'\"'\"'")
        let command = """
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if ! command -v tmux >/dev/null 2>&1; then
  echo "__CE_TMUX_ERROR__: tmux is not installed"
elif tmux has-session -t '\(oldEscaped)' 2>/dev/null; then
  if tmux rename-session -t '\(oldEscaped)' '\(newEscaped)' 2>/dev/null; then
    echo "__CE_TMUX_OK__"
  else
    echo "__CE_TMUX_ERROR__: failed to rename session"
  fi
else
  echo "__CE_TMUX_ERROR__: session not found"
fi
"""
        Task {
            let output = await withTerminalSSHTimeout {
                (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            } ?? "__CE_TMUX_ERROR__: Timed out — server unreachable"
            await MainActor.run {
                if output.contains("__CE_TMUX_OK__") {
                    TerminalWorkspaceStore.shared.renameTabsBoundToTmuxSession(
                        credentialKey: credentialKey,
                        oldSessionName: oldName,
                        newSessionName: newName
                    )
                    self.refreshFromWorkspace()
                } else {
                    self.showTmuxOperationError(title: "Couldn’t rename session", output: output)
                }
            }
        }
    }

    private func closeSession(credentialKey: String, sessionName: String) {
        guard let credential = keychain().getCredential(for: credentialKey) else { return }
        let normalizedSessionName = XTermSessionController.normalizeTmuxSessionName(sessionName)
        guard !normalizedSessionName.isEmpty else { return }
        workspace.clearPaneToServerPicker(paneID: paneID)
        presentAllTabs()

        let escaped = normalizedSessionName.replacingOccurrences(of: "'", with: "'\"'\"'")
        let command = """
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if ! command -v tmux >/dev/null 2>&1; then
  echo "__CE_TMUX_ERROR__: tmux is not installed"
elif tmux has-session -t '\(escaped)' 2>/dev/null; then
  if tmux kill-session -t '\(escaped)' 2>/dev/null; then
    echo "__CE_TMUX_OK__"
  else
    echo "__CE_TMUX_ERROR__: failed to kill session"
  fi
else
  echo "__CE_TMUX_ERROR__: session not found"
fi
"""
        Task {
            let output = (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            await MainActor.run {
                if output.contains("__CE_TMUX_OK__") {
                    TerminalWorkspaceStore.shared.closeTabsBoundToTmuxSession(credentialKey: credentialKey, sessionName: sessionName)
                    self.refreshFromWorkspace()
                } else {
                    self.showTmuxOperationError(title: "Couldn’t close \(normalizedSessionName)", output: output)
                }
            }
        }
    }

    private func showTmuxOperationError(title: String, output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if let line = trimmed.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0.contains("__CE_TMUX_ERROR__:") }) {
            message = line.replacingOccurrences(of: "__CE_TMUX_ERROR__:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.isEmpty {
            message = "Unknown error"
        } else {
            message = trimmed
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentAllTabs() {
        let overview = TerminalTabOverviewViewController(workspace: workspace)
        overview.windowID = paneWindowID
        overview.onSelectSession = { [weak self] credentialKey, sessionName, title, colorHex in
            guard let self else { return }
            self.workspace.openTab(
                credentialKey: credentialKey,
                preferredTitle: title,
                windowID: self.paneWindowID,
                themeOverrideSelectionKey: nil,
                shortcutColorHex: colorHex ?? "#10B981",
                tmuxSessionName: sessionName,
                tmuxAttachOnly: true
            )
        }
        overview.modalPresentationStyle = .overFullScreen
        overview.modalTransitionStyle = .crossDissolve
        present(overview, animated: true)
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
    struct TmuxSessionTarget {
        let credentialKey: String
        let sessionName: String
        let title: String
        var colorHex: String?
    }

    enum SelectionTarget {
        case shortcut(TerminalLaunchShortcut)
        case tmuxSession(TmuxSessionTarget)
    }

    var onSelection: ((SelectionTarget) -> Void)?

    /// The window this picker belongs to; sessions open in other windows are hidden.
    var windowID: String = TerminalWorkspaceStore.mainWindowID
    /// Session keys ("credentialKey|session") open in other windows, to be excluded.
    var excludedSessionKeys: Set<String> = []

    private enum Section: Int, CaseIterable {
        case main
    }

    private struct TmuxSessionSummary: Hashable {
        let sessionName: String
        let displayName: String
        let windowsCount: Int?
        let isAttached: Bool?
    }

    private enum ItemKind: Hashable {
        case shortcut(shortcutID: String)
        case tmuxSession(credentialKey: String, sessionName: String)
        case divider
    }

    private struct Item: Hashable {
        let id: String
        let kind: ItemKind
        let credentialKey: String
        let title: String
        let host: String
        let detailText: String
        let colorHex: String

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
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
        collectionView.register(TerminalSectionDividerCell.self, forCellWithReuseIdentifier: TerminalSectionDividerCell.reuseID)
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
            let shortcutSessionTitleMap = Self.makeShortcutSessionTitleMap(shortcuts: shortcuts)
            let shortcutSessionColorMap = Self.makeShortcutSessionColorMap(shortcuts: shortcuts)
            let credentialMap = Dictionary(uniqueKeysWithValues: credentials.map { ($0.key, $0) })
            let shortcutItems = shortcuts.compactMap { shortcut -> Item? in
                guard let credential = credentialMap[shortcut.credentialKey] else { return nil }
                return Item(
                    id: "shortcut:\(shortcut.id)",
                    kind: .shortcut(shortcutID: shortcut.id),
                    credentialKey: shortcut.credentialKey,
                    title: shortcut.title,
                    host: credential.host,
                    detailText: {
                        let trimmed = shortcut.startupScript.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No startup script" : trimmed
                    }(),
                    colorHex: shortcut.colorHex ?? "#3B82F6"
                )
            }

            // The shortcuts view shows shortcuts only — never active sessions.
            _ = shortcutSessionTitleMap
            _ = shortcutSessionColorMap
            await MainActor.run {
                self.items = shortcutItems
                var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
                snapshot.appendSections([.main])
                snapshot.appendItems(self.buildOrderedItems(sessions: [], shortcuts: self.items), toSection: .main)
                self.dataSource.apply(snapshot, animatingDifferences: true)
                self.emptyStateLabel.isHidden = !self.items.isEmpty
            }
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            if case .divider = item.kind {
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: TerminalSectionDividerCell.reuseID,
                    for: indexPath
                ) as? TerminalSectionDividerCell else {
                    return UICollectionViewCell()
                }
                return cell
            }
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TerminalServerCell.reuseID,
                for: indexPath
            ) as? TerminalServerCell else {
                return UICollectionViewCell()
            }

            cell.apply(
                title: item.title,
                host: item.host,
                detailText: item.detailText,
                colorHex: item.colorHex
            )
            return cell
        }
    }

    private func buildOrderedItems(sessions: [Item], shortcuts: [Item]) -> [Item] {
        guard !sessions.isEmpty, !shortcuts.isEmpty else { return sessions + shortcuts }
        let divider = Item(
            id: "divider",
            kind: .divider,
            credentialKey: "",
            title: "",
            host: "",
            detailText: "",
            colorHex: "#000000"
        )
        return sessions + [divider] + shortcuts
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

    nonisolated private static func discoverTmuxSessions(for credential: Credential) async -> [TmuxSessionSummary] {
        let command = """
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if command -v tmux >/dev/null 2>&1; then tmux list-sessions -F '#{session_name}|#{session_windows}|#{?session_attached,1,0}' 2>/dev/null || true; fi
"""
        let output = await withTerminalSSHTimeout {
            (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
        } ?? ""
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seenSessionNames = Set<String>()
        return lines.compactMap { line in
            let components = line.components(separatedBy: "|")
            guard let first = components.first else { return nil }
            let session = XTermSessionController.normalizeTmuxSessionName(first)
            guard !session.isEmpty else { return nil }
            guard seenSessionNames.insert(session).inserted else { return nil }

            let windowsCount: Int?
            if components.count > 1 {
                windowsCount = Int(components[1].trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                windowsCount = nil
            }

            let isAttached: Bool?
            if components.count > 2 {
                let value = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                isAttached = value == "1"
            } else {
                isAttached = nil
            }

            return TmuxSessionSummary(
                sessionName: session,
                displayName: session.count > 96 ? String(session.prefix(96)) : session,
                windowsCount: windowsCount,
                isAttached: isAttached
            )
        }
    }

    nonisolated private static func tmuxDetailText(for session: TmuxSessionSummary) -> String {
        var parts: [String] = []
        parts.append("tmux session")
        if let windowsCount = session.windowsCount {
            let suffix = windowsCount == 1 ? "window" : "windows"
            parts.append("\(windowsCount) \(suffix)")
        }
        if let attached = session.isAttached {
            parts.append(attached ? "attached" : "detached")
        }
        return parts.joined(separator: " • ")
    }

    nonisolated static func newTmuxSessionName(for shortcut: TerminalLaunchShortcut) -> String {
        // Human-readable, short session names: e.g. "containeye-shortcut-web-server-3fa9c12e".
        // The slug is used to resolve the display title back to the shortcut; the 8-hex
        // suffix keeps every launch a distinct tmux session.
        let slug = shortcutTitleSlug(shortcut.title)
        let unique = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
        return "containeye-shortcut-\(slug)-\(unique)"
    }

    /// A lowercase, dash-separated slug derived from a shortcut title, safe for tmux session names.
    nonisolated static func shortcutTitleSlug(_ title: String) -> String {
        var slug = ""
        var lastWasDash = false
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count > 24 {
            slug = String(slug.prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return slug.isEmpty ? "terminal" : slug
    }

    nonisolated static func shortcutSessionSuffix(for shortcutID: String) -> String {
        shortcutID.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    nonisolated static func makeShortcutSessionTitleMap(shortcuts: [TerminalLaunchShortcut]) -> [String: [String: String]] {
        var map: [String: [String: String]] = [:]
        for shortcut in shortcuts {
            // Key by the title slug (new naming scheme) and the legacy id-hash suffix so
            // sessions created by any app version still resolve to their shortcut title.
            let slug = shortcutTitleSlug(shortcut.title)
            if !slug.isEmpty {
                map[shortcut.credentialKey, default: [:]][slug] = shortcut.title
            }
            let legacySuffix = shortcutSessionSuffix(for: shortcut.id)
            if !legacySuffix.isEmpty {
                map[shortcut.credentialKey, default: [:]][legacySuffix] = shortcut.title
            }
        }
        return map
    }

    nonisolated static func resolveTmuxDisplayTitle(
        sessionName: String,
        credentialKey: String,
        shortcutSessionTitleMap: [String: [String: String]]
    ) -> String {
        let prefix = "containeye-shortcut-"
        guard sessionName.hasPrefix(prefix) else { return sessionName }
        let remainder = String(sessionName.dropFirst(prefix.count))
        guard let splitIndex = remainder.lastIndex(of: "-") else { return sessionName }
        let suffix = String(remainder[..<splitIndex])
        if let mapped = shortcutSessionTitleMap[credentialKey]?[suffix], !mapped.isEmpty {
            return mapped
        }
        // Fallback for unresolvable prefixed names (e.g. the shortcut was deleted):
        // prettify a readable slug, but never surface an opaque id-hash blob.
        if suffix.count <= 24, !suffix.allSatisfy({ $0.isHexDigit }) {
            let pretty = suffix.replacingOccurrences(of: "-", with: " ").capitalized
            if !pretty.isEmpty { return pretty }
        }
        return "Terminal Session"
    }

    /// Maps a session's shortcut suffix to the shortcut's chosen color (both the new
    /// slug scheme and the legacy id-hash), so sessions inherit their shortcut's color.
    nonisolated static func makeShortcutSessionColorMap(shortcuts: [TerminalLaunchShortcut]) -> [String: [String: String]] {
        var map: [String: [String: String]] = [:]
        for shortcut in shortcuts {
            guard let color = shortcut.colorHex, !color.isEmpty else { continue }
            let slug = shortcutTitleSlug(shortcut.title)
            if !slug.isEmpty {
                map[shortcut.credentialKey, default: [:]][slug] = color
            }
            let legacySuffix = shortcutSessionSuffix(for: shortcut.id)
            if !legacySuffix.isEmpty {
                map[shortcut.credentialKey, default: [:]][legacySuffix] = color
            }
        }
        return map
    }

    /// A stable, distinct color for a session: its shortcut color when known,
    /// otherwise a deterministic hash into a fixed palette so each session reads
    /// as a distinct, consistent color across launches.
    nonisolated static func resolveTmuxSessionColorHex(
        sessionName: String,
        credentialKey: String,
        shortcutSessionColorMap: [String: [String: String]]
    ) -> String {
        let prefix = "containeye-shortcut-"
        if sessionName.hasPrefix(prefix) {
            let remainder = String(sessionName.dropFirst(prefix.count))
            if let splitIndex = remainder.lastIndex(of: "-") {
                let suffix = String(remainder[..<splitIndex])
                if let mapped = shortcutSessionColorMap[credentialKey]?[suffix], !mapped.isEmpty {
                    return mapped
                }
            }
        }
        return TerminalSessionPalette.color(for: "\(credentialKey)|\(sessionName)")
    }

    nonisolated private static func disambiguateSessionTitles(_ sessions: [Item]) -> [Item] {
        var counts: [String: Int] = [:]
        return sessions.map { item in
            guard case .tmuxSession = item.kind else { return item }
            let key = "\(item.credentialKey)|\(item.title)"
            counts[key, default: 0] += 1
            let index = counts[key] ?? 1
            guard index > 1 else { return item }
            return Item(
                id: item.id,
                kind: item.kind,
                credentialKey: item.credentialKey,
                title: "\(item.title) (\(index))",
                host: item.host,
                detailText: item.detailText,
                colorHex: item.colorHex
            )
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
        switch item.kind {
        case .divider:
            return
        case let .shortcut(shortcutID):
            Task {
                let shortcuts = await TerminalLaunchShortcut.all(in: SharedDatabase.db)
                guard var selected = shortcuts.first(where: { $0.id == shortcutID }) else { return }
                selected.lastUse = .now
                try? await selected.write(to: SharedDatabase.db)
                await MainActor.run {
                    self.onSelection?(.shortcut(selected))
                }
            }
        case let .tmuxSession(credentialKey, sessionName):
            let target = TmuxSessionTarget(
                credentialKey: credentialKey,
                sessionName: sessionName,
                title: item.title,
                colorHex: item.colorHex
            )
            onSelection?(.tmuxSession(target))
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

            switch item.kind {
            case .divider:
                return UIMenu()
            case let .shortcut(shortcutID):
                let edit = UIAction(title: "Edit Shortcut", image: UIImage(systemName: "pencil")) { _ in
                    self.presentShortcutEditor(for: shortcutID)
                }

                let delete = UIAction(
                    title: "Delete Shortcut",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self.deleteShortcut(shortcutID: shortcutID)
                }

                return UIMenu(children: [edit, delete])

            case let .tmuxSession(credentialKey, sessionName):
                let rename = UIAction(
                    title: "Rename Session",
                    image: UIImage(systemName: "pencil")
                ) { _ in
                    self.promptRenameTmuxSession(
                        credentialKey: credentialKey,
                        sessionName: sessionName
                    )
                }
                let close = UIAction(
                    title: "Close Session",
                    image: UIImage(systemName: "xmark.circle"),
                    attributes: .destructive
                ) { _ in
                    self.confirmAndCloseTmuxSession(
                        credentialKey: credentialKey,
                        sessionName: sessionName
                    )
                }
                return UIMenu(children: [rename, close])
            }
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

    private func confirmAndCloseTmuxSession(credentialKey: String, sessionName: String) {
        let alert = UIAlertController(
            title: "Close tmux session?",
            message: "This will run `tmux kill-session -t \(sessionName)` on the server.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Close Session", style: .destructive, handler: { [weak self] _ in
            self?.closeTmuxSession(credentialKey: credentialKey, sessionName: sessionName)
        }))
        present(alert, animated: true)
    }

    private func promptRenameTmuxSession(credentialKey: String, sessionName: String) {
        let alert = UIAlertController(
            title: "Rename tmux session",
            message: "Current name: \(sessionName)",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = sessionName
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default, handler: { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text
            else { return }
            let newName = XTermSessionController.normalizeTmuxSessionName(raw)
            guard !newName.isEmpty else { return }
            self.renameTmuxSession(
                credentialKey: credentialKey,
                oldSessionName: sessionName,
                newSessionName: newName
            )
        }))
        present(alert, animated: true)
    }

    private func renameTmuxSession(credentialKey: String, oldSessionName: String, newSessionName: String) {
        guard let credential = keychain().getCredential(for: credentialKey) else { return }
        let oldNormalized = XTermSessionController.normalizeTmuxSessionName(oldSessionName)
        let newNormalized = XTermSessionController.normalizeTmuxSessionName(newSessionName)
        guard !oldNormalized.isEmpty, !newNormalized.isEmpty else { return }
        guard oldNormalized != newNormalized else { return }

        let oldEscaped = oldNormalized.replacingOccurrences(of: "'", with: "'\"'\"'")
        let newEscaped = newNormalized.replacingOccurrences(of: "'", with: "'\"'\"'")
        let command = """
if ! command -v tmux >/dev/null 2>&1; then
  echo "__CE_TMUX_ERROR__: tmux is not installed"
elif tmux has-session -t '\(oldEscaped)' 2>/dev/null; then
  if tmux rename-session -t '\(oldEscaped)' '\(newEscaped)' 2>/dev/null; then
    echo "__CE_TMUX_OK__"
  else
    echo "__CE_TMUX_ERROR__: failed to rename session"
  fi
else
  echo "__CE_TMUX_ERROR__: session not found"
fi
"""

        Task {
            let output = await withTerminalSSHTimeout {
                (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            } ?? "__CE_TMUX_ERROR__: Timed out — server unreachable"
            await MainActor.run {
                if output.contains("__CE_TMUX_OK__") {
                    TerminalWorkspaceStore.shared.renameTabsBoundToTmuxSession(
                        credentialKey: credentialKey,
                        oldSessionName: oldNormalized,
                        newSessionName: newNormalized
                    )
                    self.reloadCredentials()
                } else {
                    self.showTmuxCloseError(output: output, sessionName: oldNormalized)
                }
            }
        }
    }

    private func closeTmuxSession(credentialKey: String, sessionName: String) {
        guard let credential = keychain().getCredential(for: credentialKey) else { return }
        let normalizedSessionName = XTermSessionController.normalizeTmuxSessionName(sessionName)
        guard !normalizedSessionName.isEmpty else { return }
        removeDisplayedTmuxSession(credentialKey: credentialKey, sessionName: normalizedSessionName)
        TerminalWorkspaceStore.shared.closeTabsBoundToTmuxSession(
            credentialKey: credentialKey,
            sessionName: normalizedSessionName
        )

        let escapedSessionName = normalizedSessionName.replacingOccurrences(of: "'", with: "'\"'\"'")
        let command = """
if ! command -v tmux >/dev/null 2>&1; then
  echo "__CE_TMUX_ERROR__: tmux is not installed"
elif tmux has-session -t '\(escapedSessionName)' 2>/dev/null; then
  if tmux kill-session -t '\(escapedSessionName)' 2>/dev/null; then
    echo "__CE_TMUX_OK__"
  else
    echo "__CE_TMUX_ERROR__: failed to kill session"
  fi
else
  echo "__CE_TMUX_ERROR__: session not found"
fi
"""

        Task {
            let output = (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            await MainActor.run {
                self.reloadCredentials()
                if output.contains("__CE_TMUX_OK__") {
                    return
                } else {
                    self.showTmuxCloseError(output: output, sessionName: normalizedSessionName)
                }
            }
        }
    }

    private func removeDisplayedTmuxSession(credentialKey: String, sessionName: String) {
        items.removeAll { item in
            guard case let .tmuxSession(itemCredentialKey, itemSessionName) = item.kind else {
                return false
            }
            if itemCredentialKey != credentialKey {
                return false
            }
            return XTermSessionController.normalizeTmuxSessionName(itemSessionName) == sessionName
        }

        let sessions = items.filter {
            if case .tmuxSession = $0.kind { return true }
            return false
        }
        let shortcuts = items.filter {
            if case .shortcut = $0.kind { return true }
            return false
        }
        items = buildOrderedItems(sessions: sessions, shortcuts: shortcuts)

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyStateLabel.isHidden = !items.isEmpty
    }

    private func showTmuxCloseError(output: String, sessionName: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if let line = trimmed.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0.contains("__CE_TMUX_ERROR__:") }) {
            message = line.replacingOccurrences(of: "__CE_TMUX_ERROR__:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.isEmpty {
            message = "Unknown error"
        } else {
            message = trimmed
        }

        let alert = UIAlertController(
            title: "Couldn’t close \(sessionName)",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

@MainActor
final class TerminalTabOverviewViewController: UIViewController {
    struct Item: Hashable {
        let id: String
        let credentialKey: String
        let sessionName: String
        let displayTitle: String
        let host: String
        let previewText: String
        // True when previewText is a meta summary (e.g. "2 windows • attached")
        // rather than actual captured terminal output.
        let previewIsPlaceholder: Bool
        let isActive: Bool
        let colorHex: String?

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        /// Whether the visible content (not just identity) matches — used to decide
        /// which items need a cell reconfigure during an incremental reload.
        func hasSameContent(as other: Item) -> Bool {
            displayTitle == other.displayTitle
            && host == other.host
            && previewText == other.previewText
            && previewIsPlaceholder == other.previewIsPlaceholder
            && isActive == other.isActive
            && colorHex == other.colorHex
        }
    }

    var onSelectSession: ((String, String, String, String?) -> Void)?

    /// The window this overview belongs to; sessions open in other windows are hidden.
    var windowID: String = TerminalWorkspaceStore.mainWindowID

    private let workspace: TerminalWorkspaceStore
    private var items: [Item] = []
    private let settingsStore = TerminalSettingsStore.shared

    private enum Section: Int, CaseIterable {
        case main
    }

    private struct TmuxSessionSummary: Hashable {
        let sessionName: String
        let windowsCount: Int?
        let isAttached: Bool?
        // Last non-empty lines captured from the session's active pane.
        let previewLines: [String]
    }

    private let collectionView: UICollectionView
    private lazy var dataSource = makeDataSource()
    private let backgroundBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let topBarView = UIView()
    private let settingsButton = UIButton(type: .system)
    private let selectButton = UIButton(type: .system)
    private let bottomBarView = UIView()
    private let addButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let tabCountView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let tabCountLabel = UILabel()
    private var isSelectionMode = false
    private var selectedSessionIDs = Set<String>()
    // Bumped on every reload so results from a superseded reload are discarded.
    private var reloadGeneration = 0

    init(workspace: TerminalWorkspaceStore) {
        self.workspace = workspace
        let layout = UICollectionViewCompositionalLayout { _, environment -> NSCollectionLayoutSection? in
            let width = environment.container.effectiveContentSize.width
            let sideInset = max(UIFloat(2), min(UIFloat(8), width * 0.03))

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(width > UIFloat(740) ? 0.5 : 1.0),
                heightDimension: .fractionalHeight(1)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: UIFloat(3), bottom: 0, trailing: UIFloat(3))

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(UIFloat(196))
            )
            let groupItems: [NSCollectionLayoutItem] = width > UIFloat(740) ? [item, item] : [item]
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: groupItems)

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
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backgroundBlurView.frame = view.bounds
        backgroundBlurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundBlurView)

        topBarView.backgroundColor = .clear
        view.addSubview(topBarView)

        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.tintColor = .white
        settingsButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        settingsButton.layer.cornerRadius = UIFloat(20)
        settingsButton.layer.cornerCurve = .continuous
        settingsButton.showsMenuAsPrimaryAction = true
        settingsButton.menu = makeSettingsMenu()
        topBarView.addSubview(settingsButton)
        selectButton.setImage(UIImage(systemName: "checklist"), for: .normal)
        selectButton.tintColor = .white
        selectButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        selectButton.layer.cornerRadius = UIFloat(20)
        selectButton.layer.cornerCurve = .continuous
        selectButton.addTarget(self, action: #selector(didTapSelectMode), for: .touchUpInside)
        topBarView.addSubview(selectButton)

        bottomBarView.backgroundColor = .clear
        view.addSubview(bottomBarView)

        [addButton, doneButton].forEach { button in
            button.tintColor = .white
            button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
            button.layer.cornerRadius = UIFloat(24)
            button.layer.cornerCurve = .continuous
            bottomBarView.addSubview(button)
        }
        addButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addButton.addTarget(self, action: #selector(didTapNewTab), for: .touchUpInside)
        doneButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        doneButton.backgroundColor = UIColor.systemBlue
        doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)

        tabCountView.layer.cornerRadius = UIFloat(22)
        tabCountView.layer.cornerCurve = .continuous
        tabCountView.clipsToBounds = true
        bottomBarView.addSubview(tabCountView)
        tabCountLabel.font = UIFont.systemFont(ofSize: UIFloat(16), weight: .semibold)
        tabCountLabel.textColor = .white
        tabCountLabel.textAlignment = .center
        tabCountView.contentView.addSubview(tabCountLabel)

        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = false
        collectionView.register(TerminalAllTabsCell.self, forCellWithReuseIdentifier: TerminalAllTabsCell.reuseID)
        view.addSubview(collectionView)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let topBarHeight = UIFloat(44)
        topBarView.frame = CGRect(x: UIFloat(12), y: safe.top + UIFloat(6), width: view.bounds.width - UIFloat(24), height: topBarHeight)
        settingsButton.frame = CGRect(x: 0, y: UIFloat(2), width: UIFloat(40), height: UIFloat(40))
        selectButton.frame = CGRect(x: settingsButton.frame.maxX + UIFloat(8), y: UIFloat(2), width: UIFloat(40), height: UIFloat(40))

        let bottomHeight = UIFloat(64)
        bottomBarView.frame = CGRect(
            x: UIFloat(12),
            y: view.bounds.height - safe.bottom - bottomHeight - UIFloat(8),
            width: view.bounds.width - UIFloat(24),
            height: bottomHeight
        )
        addButton.frame = CGRect(x: 0, y: UIFloat(8), width: UIFloat(48), height: UIFloat(48))
        doneButton.frame = CGRect(x: bottomBarView.bounds.width - UIFloat(48), y: UIFloat(8), width: UIFloat(48), height: UIFloat(48))
        tabCountView.frame = CGRect(
            x: addButton.frame.maxX + UIFloat(12),
            y: UIFloat(10),
            width: max(UIFloat(120), doneButton.frame.minX - (addButton.frame.maxX + UIFloat(24))),
            height: UIFloat(44)
        )
        tabCountLabel.frame = tabCountView.bounds

        collectionView.frame = CGRect(
            x: 0,
            y: safe.top + UIFloat(54),
            width: view.bounds.width,
            height: bottomBarView.frame.minY - (safe.top + UIFloat(54))
        )
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: TerminalAllTabsCell.reuseID,
                for: indexPath
            ) as? TerminalAllTabsCell else {
                return UICollectionViewCell()
            }
            cell.onClose = { [weak self] in
                self?.closeSession(credentialKey: item.credentialKey, sessionName: item.sessionName)
            }
            cell.swipeToCloseEnabled = { [weak self] in
                self?.isSelectionMode == false
            }
            cell.apply(
                title: item.displayTitle,
                subtitle: item.host,
                previewText: item.previewText,
                previewIsPlaceholder: item.previewIsPlaceholder,
                isActive: item.isActive,
                accentHex: item.colorHex
            )
            return cell
        }
    }

    private func reload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        Task {
            let credentials = keychain()
                .allKeys()
                .compactMap { keychain().getCredential(for: $0) }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            let shortcuts = await TerminalLaunchShortcut.all(in: SharedDatabase.db)
            let shortcutSessionTitleMap = TerminalServerPickerViewController.makeShortcutSessionTitleMap(shortcuts: shortcuts)
            let shortcutSessionColorMap = TerminalServerPickerViewController.makeShortcutSessionColorMap(shortcuts: shortcuts)
            // Sessions already open as tabs in other windows don't belong here.
            let excludedSessionKeys = workspace.sessionKeysBoundToOtherWindows(excluding: windowID)

            // Accumulate results per server. Apply incrementally as each server
            // answers so healthy servers show immediately even while another is
            // slow or unreachable (each discovery is time-bounded).
            var itemsByID: [String: Item] = [:]

            await withTaskGroup(of: [Item].self, returning: Void.self) { group in
                for credential in credentials {
                    group.addTask {
                        let sessions = await Self.discoverTmuxSessions(for: credential)
                        return sessions
                            .filter { !excludedSessionKeys.contains("\(credential.key)|\($0.sessionName)") }
                            .map { session in
                                Self.makeItem(
                                    credentialKey: credential.key,
                                    host: credential.host,
                                    session: session,
                                    shortcutSessionTitleMap: shortcutSessionTitleMap,
                                    shortcutSessionColorMap: shortcutSessionColorMap
                                )
                            }
                    }
                }

                for await partial in group {
                    for item in partial {
                        itemsByID[item.id] = item
                    }
                    let sorted = Self.sortedDisambiguated(Array(itemsByID.values))
                    await MainActor.run {
                        self.applyDiscovered(sorted, generation: generation)
                    }
                }
            }

            // Final apply so a run that discovered zero sessions still clears the list.
            let sorted = Self.sortedDisambiguated(Array(itemsByID.values))
            await MainActor.run {
                self.applyDiscovered(sorted, generation: generation)
            }
        }
    }

    private func applyDiscovered(_ discovered: [Item], generation: Int) {
        guard generation == reloadGeneration else { return }
        // Items whose identity is unchanged but content differs need an explicit
        // reconfigure — diffable equality is id-only and would otherwise skip them.
        let changedIDs = discovered
            .filter { new in items.contains { $0.id == new.id && !$0.hasSameContent(as: new) } }
            .map(\.id)
        items = discovered
        if !isSelectionMode {
            tabCountLabel.text = "\(discovered.count) Tabs"
        }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(discovered, toSection: .main)
        if !changedIDs.isEmpty {
            let changedItems = discovered.filter { changedIDs.contains($0.id) }
            snapshot.reconfigureItems(changedItems)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    nonisolated private static func makeItem(
        credentialKey: String,
        host: String,
        session: TmuxSessionSummary,
        shortcutSessionTitleMap: [String: [String: String]],
        shortcutSessionColorMap: [String: [String: String]]
    ) -> Item {
        let previewIsPlaceholder = session.previewLines.isEmpty
        let previewText: String
        if previewIsPlaceholder {
            var parts: [String] = []
            if let windows = session.windowsCount {
                parts.append("\(windows) \(windows == 1 ? "window" : "windows")")
            }
            if let attached = session.isAttached {
                parts.append(attached ? "attached" : "detached")
            }
            previewText = parts.isEmpty ? "No output yet" : parts.joined(separator: " • ")
        } else {
            previewText = session.previewLines.joined(separator: "\n")
        }
        return Item(
            id: "tmux:\(credentialKey):\(session.sessionName)",
            credentialKey: credentialKey,
            sessionName: session.sessionName,
            displayTitle: TerminalServerPickerViewController.resolveTmuxDisplayTitle(
                sessionName: session.sessionName,
                credentialKey: credentialKey,
                shortcutSessionTitleMap: shortcutSessionTitleMap
            ),
            host: host,
            previewText: previewText,
            previewIsPlaceholder: previewIsPlaceholder,
            isActive: session.isAttached ?? false,
            colorHex: TerminalServerPickerViewController.resolveTmuxSessionColorHex(
                sessionName: session.sessionName,
                credentialKey: credentialKey,
                shortcutSessionColorMap: shortcutSessionColorMap
            )
        )
    }

    private static func sortedDisambiguated(_ items: [Item]) -> [Item] {
        var discovered = disambiguateDisplayTitles(items)
        discovered.sort {
            if $0.host == $1.host {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
        }
        return discovered
    }

    private func makeSettingsMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Settings", image: UIImage(systemName: "gearshape")) { [weak self] _ in
                self?.presentSettings()
            },
            UIAction(title: "Snippets", image: UIImage(systemName: "ellipsis.curlybraces")) { [weak self] _ in
                self?.presentSnippets()
            }
        ])
    }

    private func presentSettings() {
        let settings = TerminalSettingsViewController()
        let navigation = UINavigationController(rootViewController: settings)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    private func presentSnippets() {
        let currentCredentialKey = workspace.activeController(inWindow: windowID)?.credentialKey
        let picker = TerminalSnippetPickerViewController(
            database: SharedDatabase.db,
            credentialKey: currentCredentialKey
        ) { [weak self] snippet in
            guard let self else { return }
            self.workspace.activeController(inWindow: self.windowID)?.applySuggestion(snippet.command)
        }

        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    @objc
    private func didTapDone() {
        guard isSelectionMode else {
            dismiss(animated: true)
            return
        }
        guard !selectedSessionIDs.isEmpty else { return }
        let selectedItems = items.filter { selectedSessionIDs.contains($0.id) }
        for item in selectedItems {
            closeSession(credentialKey: item.credentialKey, sessionName: item.sessionName)
        }
        selectedSessionIDs.removeAll()
        tabCountLabel.text = "Select sessions to close"
        doneButton.alpha = 0.75
    }

    @objc
    private func didTapNewTab() {
        if isSelectionMode {
            didTapSelectMode()
            return
        }
        workspace.beginNewTab(inWindow: TerminalWorkspaceStore.mainWindowID)
        dismiss(animated: true)
    }

    @objc
    private func didTapSelectMode() {
        isSelectionMode.toggle()
        selectedSessionIDs.removeAll()
        collectionView.allowsMultipleSelection = isSelectionMode
        if !isSelectionMode {
            for selected in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: selected, animated: false)
            }
        }
        selectButton.backgroundColor = isSelectionMode ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.14)
        addButton.setImage(UIImage(systemName: isSelectionMode ? "xmark" : "plus"), for: .normal)
        addButton.backgroundColor = isSelectionMode ? UIColor.systemOrange : UIColor.white.withAlphaComponent(0.14)
        doneButton.setImage(UIImage(systemName: isSelectionMode ? "trash" : "checkmark"), for: .normal)
        tabCountLabel.text = isSelectionMode ? "Select sessions to close" : "\(items.count) Tabs"
        doneButton.alpha = isSelectionMode ? 0.75 : 1
    }

    private func closeSession(credentialKey: String, sessionName: String) {
        guard let credential = keychain().getCredential(for: credentialKey) else { return }
        let normalized = XTermSessionController.normalizeTmuxSessionName(sessionName)
        guard !normalized.isEmpty else { return }
        let escaped = normalized.replacingOccurrences(of: "'", with: "'\"'\"'")
        let removed = removeDisplayedSession(credentialKey: credentialKey, sessionName: normalized)
        let command = """
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if ! command -v tmux >/dev/null 2>&1; then
  echo "__CE_TMUX_ERROR__: tmux is not installed"
elif tmux has-session -t '\(escaped)' 2>/dev/null; then
  if tmux kill-session -t '\(escaped)' 2>/dev/null; then
    echo "__CE_TMUX_OK__"
  else
    echo "__CE_TMUX_ERROR__: failed to kill session"
  fi
else
  echo "__CE_TMUX_ERROR__: session not found"
fi
"""
        Task {
            let output = await withTerminalSSHTimeout {
                (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            }
            await MainActor.run {
                if output?.contains("__CE_TMUX_OK__") == true {
                    TerminalWorkspaceStore.shared.closeTabsBoundToTmuxSession(credentialKey: credentialKey, sessionName: sessionName)
                    self.reload()
                } else {
                    // Restore the optimistically-removed card, unless a concurrent
                    // reload already re-added it (avoids duplicate diffable identifiers).
                    if let removed, !self.items.contains(where: { $0.id == removed.id }) {
                        self.items.append(removed)
                        self.reloadSnapshot()
                    } else {
                        self.reload()
                    }
                    self.showCloseError(sessionName: normalized, output: output ?? "__CE_TMUX_ERROR__: Timed out — server unreachable")
                }
            }
        }
    }

    private func removeDisplayedSession(credentialKey: String, sessionName: String) -> Item? {
        guard let idx = items.firstIndex(where: {
            $0.credentialKey == credentialKey && XTermSessionController.normalizeTmuxSessionName($0.sessionName) == sessionName
        }) else { return nil }
        let removed = items.remove(at: idx)
        reloadSnapshot()
        return removed
    }

    private func reloadSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        tabCountLabel.text = "\(items.count) Tabs"
    }

    private func showCloseError(sessionName: String, output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if let line = trimmed.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0.contains("__CE_TMUX_ERROR__:") }) {
            message = line.replacingOccurrences(of: "__CE_TMUX_ERROR__:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.isEmpty {
            message = "Unknown error"
        } else {
            message = trimmed
        }
        let alert = UIAlertController(title: "Couldn’t close \(sessionName)", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    nonisolated private static func discoverTmuxSessions(for credential: Credential) async -> [TmuxSessionSummary] {
        // One SSH exec per server: for each tmux session emit a header, a meta line
        // (windows|attached) and the last non-empty lines of its active pane, so the
        // overview cards can show a real mini-preview instead of a generic summary.
        let command = """
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if command -v tmux >/dev/null 2>&1; then
tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r __ce_s; do
  [ -z "$__ce_s" ] && continue
  printf '__CE_SESSION__|%s\\n' "$__ce_s"
  tmux display-message -p -t "$__ce_s" '#{session_windows}|#{?session_attached,1,0}' 2>/dev/null
  tmux capture-pane -p -t "$__ce_s" 2>/dev/null | sed 's/[[:space:]]*$//' | awk 'NF' | tail -n 3
  printf '__CE_END__\\n'
done
fi
"""
        let output = await withTerminalSSHTimeout {
            (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
        } ?? ""
        return parseDiscoveryOutput(output)
    }

    nonisolated private static func parseDiscoveryOutput(_ output: String) -> [TmuxSessionSummary] {
        var sessions: [TmuxSessionSummary] = []
        var seenSessionNames = Set<String>()

        var currentName: String?
        var windowsCount: Int?
        var isAttached: Bool?
        var previewLines: [String] = []
        var sawMetaLine = false

        func flush() {
            guard let name = currentName else { return }
            if seenSessionNames.insert(name).inserted {
                sessions.append(TmuxSessionSummary(
                    sessionName: name,
                    windowsCount: windowsCount,
                    isAttached: isAttached,
                    previewLines: previewLines
                ))
            }
            currentName = nil
            windowsCount = nil
            isAttached = nil
            previewLines = []
            sawMetaLine = false
        }

        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            if currentName == nil {
                // Only recognise a header when between sessions, so pane content that
                // happens to contain a marker can't fabricate a phantom session.
                guard rawLine.hasPrefix("__CE_SESSION__|") else { continue }
                let name = XTermSessionController.normalizeTmuxSessionName(
                    String(rawLine.dropFirst("__CE_SESSION__|".count))
                )
                currentName = name.isEmpty ? nil : name
                continue
            }

            if rawLine == "__CE_END__" {
                flush()
                continue
            }
            // Ignore stray markers appearing inside captured pane output.
            if rawLine.hasPrefix("__CE_SESSION__|") { continue }

            if !sawMetaLine {
                sawMetaLine = true
                let parts = rawLine.components(separatedBy: "|")
                if parts.count == 2, let windows = Int(parts[0]), parts[1] == "0" || parts[1] == "1" {
                    windowsCount = windows
                    isAttached = parts[1] == "1"
                    continue
                }
                // display-message produced no usable meta line (session vanished mid-loop):
                // treat this line as the first preview line instead.
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                previewLines.append(trimmed)
            }
        }
        flush()
        return sessions
    }

    nonisolated private static func disambiguateDisplayTitles(_ sessions: [Item]) -> [Item] {
        var counts: [String: Int] = [:]
        return sessions.map { item in
            let key = "\(item.credentialKey)|\(item.displayTitle)"
            counts[key, default: 0] += 1
            let index = counts[key] ?? 1
            guard index > 1 else { return item }
            return Item(
                id: item.id,
                credentialKey: item.credentialKey,
                sessionName: item.sessionName,
                displayTitle: "\(item.displayTitle) (\(index))",
                host: item.host,
                previewText: item.previewText,
                previewIsPlaceholder: item.previewIsPlaceholder,
                isActive: item.isActive,
                colorHex: item.colorHex
            )
        }
    }
}

extension TerminalTabOverviewViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        let item = items[indexPath.item]
        if isSelectionMode {
            selectedSessionIDs.insert(item.id)
            tabCountLabel.text = selectedSessionIDs.isEmpty ? "Select sessions to close" : "\(selectedSessionIDs.count) selected • tap trash"
            doneButton.alpha = selectedSessionIDs.isEmpty ? 0.75 : 1
            return
        }
        onSelectSession?(item.credentialKey, item.sessionName, item.displayTitle, item.colorHex)
        dismiss(animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isSelectionMode, indexPath.item < items.count else { return }
        selectedSessionIDs.remove(items[indexPath.item].id)
        tabCountLabel.text = selectedSessionIDs.isEmpty ? "Select sessions to close" : "\(selectedSessionIDs.count) selected • tap trash"
        doneButton.alpha = selectedSessionIDs.isEmpty ? 0.75 : 1
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
            var actions: [UIMenuElement] = [
                UIAction(title: "Open Session", image: UIImage(systemName: "arrow.right.circle")) { _ in
                    self.onSelectSession?(item.credentialKey, item.sessionName, item.displayTitle, item.colorHex)
                    self.dismiss(animated: true)
                }
            ]
            if TerminalWindowRouter.shared.supportsMultipleWindows {
                actions.append(UIAction(title: "Open in New Window", image: UIImage(systemName: "macwindow.badge.plus")) { _ in
                    let newWindowID = UUID().uuidString
                    self.workspace.openTab(
                        credentialKey: item.credentialKey,
                        preferredTitle: item.displayTitle,
                        windowID: newWindowID,
                        shortcutColorHex: item.colorHex,
                        tmuxSessionName: item.sessionName,
                        tmuxAttachOnly: true
                    )
                    TerminalWindowRouter.shared.open(TerminalWindowTarget(windowID: newWindowID))
                    self.dismiss(animated: true)
                })
            }
            actions.append(contentsOf: [
                UIAction(title: "Rename Session", image: UIImage(systemName: "pencil")) { _ in
                    self.promptRenameSession(credentialKey: item.credentialKey, sessionName: item.sessionName)
                },
                UIAction(title: self.selectedSessionIDs.contains(item.id) ? "Deselect" : "Select", image: UIImage(systemName: "checkmark.circle")) { _ in
                    self.isSelectionMode = true
                    self.selectButton.backgroundColor = UIColor.systemBlue
                    self.collectionView.allowsMultipleSelection = true
                    if self.selectedSessionIDs.contains(item.id) {
                        self.selectedSessionIDs.remove(item.id)
                        if let selectedIndex = self.items.firstIndex(of: item) {
                            self.collectionView.deselectItem(at: IndexPath(item: selectedIndex, section: 0), animated: true)
                        }
                    } else {
                        self.selectedSessionIDs.insert(item.id)
                        if let selectedIndex = self.items.firstIndex(of: item) {
                            self.collectionView.selectItem(at: IndexPath(item: selectedIndex, section: 0), animated: true, scrollPosition: [])
                        }
                    }
                    self.addButton.setImage(UIImage(systemName: "xmark"), for: .normal)
                    self.addButton.backgroundColor = UIColor.systemOrange
                    self.doneButton.setImage(UIImage(systemName: "trash"), for: .normal)
                    self.tabCountLabel.text = self.selectedSessionIDs.isEmpty ? "Select sessions to close" : "\(self.selectedSessionIDs.count) selected • tap trash"
                    self.doneButton.alpha = self.selectedSessionIDs.isEmpty ? 0.75 : 1
                },
                UIAction(title: "Close Session", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in
                    self.closeSession(credentialKey: item.credentialKey, sessionName: item.sessionName)
                },
            ])
            return UIMenu(children: actions)
        }
    }

    private func promptRenameSession(credentialKey: String, sessionName: String) {
        let alert = UIAlertController(title: "Rename session", message: sessionName, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = sessionName
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let raw = alert?.textFields?.first?.text else { return }
            let newName = XTermSessionController.normalizeTmuxSessionName(raw)
            guard !newName.isEmpty else { return }
            self.renameSession(credentialKey: credentialKey, oldSessionName: sessionName, newSessionName: newName)
        }))
        present(alert, animated: true)
    }

    private func renameSession(credentialKey: String, oldSessionName: String, newSessionName: String) {
        guard let credential = keychain().getCredential(for: credentialKey) else { return }
        let oldNormalized = XTermSessionController.normalizeTmuxSessionName(oldSessionName)
        let newNormalized = XTermSessionController.normalizeTmuxSessionName(newSessionName)
        guard !oldNormalized.isEmpty, !newNormalized.isEmpty, oldNormalized != newNormalized else { return }

        let oldEscaped = oldNormalized.replacingOccurrences(of: "'", with: "'\"'\"'")
        let newEscaped = newNormalized.replacingOccurrences(of: "'", with: "'\"'\"'")
        let command = """
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
if ! command -v tmux >/dev/null 2>&1; then
  echo "__CE_TMUX_ERROR__: tmux is not installed"
elif tmux has-session -t '\(oldEscaped)' 2>/dev/null; then
  if tmux rename-session -t '\(oldEscaped)' '\(newEscaped)' 2>/dev/null; then
    echo "__CE_TMUX_OK__"
  else
    echo "__CE_TMUX_ERROR__: failed to rename session"
  fi
else
  echo "__CE_TMUX_ERROR__: session not found"
fi
"""
        Task {
            let output = await withTerminalSSHTimeout {
                (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            } ?? "__CE_TMUX_ERROR__: Timed out — server unreachable"
            await MainActor.run {
                if output.contains("__CE_TMUX_OK__") {
                    TerminalWorkspaceStore.shared.renameTabsBoundToTmuxSession(
                        credentialKey: credentialKey,
                        oldSessionName: oldNormalized,
                        newSessionName: newNormalized
                    )
                    self.reload()
                } else {
                    self.showCloseError(sessionName: oldNormalized, output: output)
                }
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
                TerminalPlainTextEditor(text: $startupScript)
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

private struct TerminalPlainTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFont.monospacedSystemFont(ofSize: UIFloat(13), weight: .regular)
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.keyboardType = .asciiCapable
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: TerminalPlainTextEditor

        init(_ parent: TerminalPlainTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
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

    func apply(title: String, host: String, detailText: String, colorHex: String) {
        titleLabel.text = title
        hostLabel.text = host
        let trimmed = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        scriptLabel.text = trimmed.isEmpty ? "No startup script" : trimmed
        let accent = UIColor(hex: colorHex) ?? .systemBlue
        backgroundCard.backgroundColor = accent.withAlphaComponent(0.20)
        backgroundCard.layer.borderWidth = UIFloat(1)
        backgroundCard.layer.borderColor = accent.withAlphaComponent(0.45).cgColor
    }
}

@MainActor
final class TerminalSectionDividerCell: UICollectionViewCell {
    static let reuseID = "TerminalSectionDividerCell"

    private let lineView = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        lineView.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        contentView.addSubview(lineView)

        label.text = "Shortcuts"
        label.font = UIFont.systemFont(ofSize: UIFloat(11), weight: .semibold)
        label.textColor = UIColor.secondaryLabel
        label.textAlignment = .center
        contentView.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = bounds.midY
        lineView.frame = CGRect(x: UIFloat(10), y: y, width: max(UIFloat(0), bounds.width - UIFloat(20)), height: 1)
        label.frame = CGRect(x: UIFloat(12), y: y - UIFloat(10), width: max(UIFloat(0), bounds.width - UIFloat(24)), height: UIFloat(20))
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.78)
    }
}

@MainActor
final class TerminalAllTabsCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseID = "TerminalAllTabsCell"

    var onClose: (() -> Void)?
    /// Queried when a swipe begins; return false to disable swipe-to-close (e.g. selection mode).
    var swipeToCloseEnabled: (() -> Bool)?

    private let card = UIView()
    private let swipeBackground = UIView()
    private let swipeIcon = UIImageView()
    private let preview = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let previewLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let selectedBadge = UIImageView()
    private var accentColor: UIColor?
    private var sessionActive = false
    private var didCancelScrollForSwipe = false
    private lazy var panGesture: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSwipePan(_:)))
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        swipeBackground.backgroundColor = UIColor.systemRed
        swipeBackground.layer.cornerRadius = UIFloat(14)
        swipeBackground.layer.cornerCurve = .continuous
        swipeBackground.alpha = 0
        swipeIcon.image = UIImage(systemName: "trash.fill")
        swipeIcon.tintColor = .white
        swipeIcon.contentMode = .center
        swipeBackground.addSubview(swipeIcon)
        contentView.addSubview(swipeBackground)

        contentView.addGestureRecognizer(panGesture)

        card.backgroundColor = UIColor.secondarySystemBackground
        card.layer.cornerRadius = UIFloat(14)
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = UIFloat(1)
        card.layer.borderColor = UIColor.separator.cgColor
        contentView.addSubview(card)

        preview.backgroundColor = UIColor.black
        preview.layer.cornerRadius = UIFloat(10)
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        card.addSubview(preview)

        previewLabel.font = UIFont.monospacedSystemFont(ofSize: UIFloat(11), weight: .regular)
        previewLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        previewLabel.numberOfLines = 3
        preview.addSubview(previewLabel)

        titleLabel.font = UIFont.systemFont(ofSize: UIFloat(13), weight: .semibold)
        titleLabel.textColor = UIColor.label
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: UIFloat(11), weight: .regular)
        subtitleLabel.textColor = UIColor.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(subtitleLabel)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.secondaryLabel
        closeButton.addAction(UIAction { [weak self] _ in
            self?.onClose?()
        }, for: .touchUpInside)
        card.addSubview(closeButton)

        selectedBadge.image = UIImage(systemName: "checkmark.circle.fill")
        selectedBadge.tintColor = UIColor.systemBlue
        selectedBadge.alpha = 0
        card.addSubview(selectedBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cardFrame = contentView.bounds.inset(by: UIEdgeInsets(top: UIFloat(4), left: UIFloat(2), bottom: UIFloat(4), right: UIFloat(2)))
        // Don't stomp the frame while a swipe transform is active (transform + frame
        // changes are undefined); the transform handles positioning during the gesture.
        if card.transform.isIdentity {
            card.frame = cardFrame
        }
        swipeBackground.frame = cardFrame
        swipeIcon.frame = CGRect(x: cardFrame.width - UIFloat(52), y: 0, width: UIFloat(44), height: cardFrame.height)
        let inner = CGRect(origin: .zero, size: cardFrame.size).inset(by: UIEdgeInsets(top: UIFloat(10), left: UIFloat(10), bottom: UIFloat(10), right: UIFloat(10)))

        closeButton.frame = CGRect(x: inner.maxX - UIFloat(20), y: inner.minY, width: UIFloat(20), height: UIFloat(20))
        selectedBadge.frame = CGRect(x: inner.maxX - UIFloat(24), y: closeButton.frame.maxY + UIFloat(6), width: UIFloat(24), height: UIFloat(24))
        titleLabel.frame = CGRect(x: inner.minX, y: inner.minY, width: max(0, closeButton.frame.minX - inner.minX - UIFloat(6)), height: UIFloat(20))
        subtitleLabel.frame = CGRect(x: inner.minX, y: titleLabel.frame.maxY + UIFloat(1), width: inner.width, height: UIFloat(16))

        let previewTop = subtitleLabel.frame.maxY + UIFloat(8)
        preview.frame = CGRect(x: inner.minX, y: previewTop, width: inner.width, height: max(UIFloat(64), inner.maxY - previewTop))
        previewLabel.frame = preview.bounds.inset(by: UIEdgeInsets(top: UIFloat(8), left: UIFloat(8), bottom: UIFloat(8), right: UIFloat(8)))
    }

    func apply(title: String, subtitle: String, previewText: String, previewIsPlaceholder: Bool, isActive: Bool, accentHex: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        previewLabel.text = previewText
        // Dim meta placeholders so real captured terminal output stands out.
        previewLabel.textColor = UIColor.white.withAlphaComponent(previewIsPlaceholder ? 0.5 : 0.88)
        previewLabel.font = previewIsPlaceholder
            ? UIFont.systemFont(ofSize: UIFloat(11), weight: .regular)
            : UIFont.monospacedSystemFont(ofSize: UIFloat(11), weight: .regular)
        sessionActive = isActive

        if let accentHex, let accent = UIColor(hex: accentHex) {
            accentColor = accent
            card.layer.borderColor = accent.withAlphaComponent(0.75).cgColor
            card.layer.borderWidth = isActive ? UIFloat(2) : UIFloat(1)
        } else {
            accentColor = UIColor.tintColor
            card.layer.borderColor = (isActive ? UIColor.tintColor : UIColor.separator).cgColor
            card.layer.borderWidth = isActive ? UIFloat(2) : UIFloat(1)
        }
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        let accent = accentColor ?? UIColor.tintColor
        if isSelected {
            card.backgroundColor = accent.withAlphaComponent(0.28)
            card.layer.borderColor = accent.cgColor
            card.layer.borderWidth = UIFloat(4)
            closeButton.tintColor = accent
            selectedBadge.alpha = 1
        } else {
            card.backgroundColor = UIColor.secondarySystemBackground
            card.layer.borderColor = (sessionActive ? accent.withAlphaComponent(0.75) : UIColor.separator).cgColor
            card.layer.borderWidth = sessionActive ? UIFloat(2) : UIFloat(1)
            closeButton.tintColor = UIColor.secondaryLabel
            selectedBadge.alpha = 0
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Force-cancel any in-flight swipe and reset visual state before reuse.
        panGesture.isEnabled = false
        panGesture.isEnabled = true
        card.transform = .identity
        card.alpha = 1
        swipeBackground.alpha = 0
        didCancelScrollForSwipe = false
        onClose = nil
        swipeToCloseEnabled = nil
    }

    @objc
    private func handleSwipePan(_ recognizer: UIPanGestureRecognizer) {
        let translationX = min(0, recognizer.translation(in: contentView).x)
        switch recognizer.state {
        case .began:
            didCancelScrollForSwipe = false
        case .changed:
            // Once the drag is clearly horizontal, cancel the collection view's scroll
            // so the card slides cleanly instead of the list scrolling underneath.
            if !didCancelScrollForSwipe {
                let translation = recognizer.translation(in: contentView)
                if abs(translation.x) > UIFloat(12), abs(translation.x) > abs(translation.y) {
                    cancelEnclosingScroll()
                    didCancelScrollForSwipe = true
                }
            }
            card.transform = CGAffineTransform(translationX: translationX, y: 0)
            swipeBackground.alpha = min(1, -translationX / UIFloat(70))
        case .ended, .cancelled, .failed:
            let velocityX = recognizer.velocity(in: contentView).x
            let threshold = bounds.width * 0.35
            let shouldClose = recognizer.state == .ended && (translationX < -threshold || velocityX < -700)
            if shouldClose {
                let handler = onClose
                UIView.animate(withDuration: 0.18, animations: {
                    self.card.transform = CGAffineTransform(translationX: -self.bounds.width, y: 0)
                    self.card.alpha = 0
                    self.swipeBackground.alpha = 1
                }, completion: { _ in
                    handler?()
                })
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                    self.card.transform = .identity
                    self.swipeBackground.alpha = 0
                }
            }
            didCancelScrollForSwipe = false
        default:
            break
        }
    }

    private func cancelEnclosingScroll() {
        var view: UIView? = superview
        while let current = view {
            if let collectionView = current as? UICollectionView {
                let scrollPan = collectionView.panGestureRecognizer
                scrollPan.isEnabled = false
                scrollPan.isEnabled = true
                return
            }
            view = current.superview
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard swipeToCloseEnabled?() ?? true else { return false }
        // Only begin for a predominantly leftward drag; leave vertical drags to scrolling.
        let velocity = panGesture.velocity(in: contentView)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer
    }
}

@MainActor
final class TerminalTabBarCell: UICollectionViewCell {
    var onClose: (() -> Void)?

    private let container = UIView()
    private let titleLabel = UILabel()
    private let colorDot = UIView()
    private let closeButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        container.layer.cornerRadius = UIFloat(8)
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        contentView.addSubview(container)

        colorDot.layer.cornerRadius = UIFloat(3)
        container.addSubview(colorDot)

        titleLabel.font = .systemFont(ofSize: UIFloat(12), weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textAlignment = .center
        container.addSubview(titleLabel)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: UIFloat(9), weight: .bold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbolConfig), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        container.addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, colorHex: String?, isActive: Bool) {
        titleLabel.text = title
        let accent = colorHex.flatMap { UIColor(hex: $0) } ?? .systemGray
        colorDot.backgroundColor = accent
        container.backgroundColor = isActive ? accent.withAlphaComponent(0.22) : UIColor.secondarySystemFill
        titleLabel.textColor = isActive ? .label : .secondaryLabel
        container.layer.borderWidth = isActive ? UIFloat(1) : 0
        container.layer.borderColor = accent.withAlphaComponent(0.7).cgColor
        closeButton.tintColor = isActive ? .label : .secondaryLabel
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.frame = contentView.bounds
        colorDot.frame = CGRect(x: UIFloat(10), y: container.bounds.midY - UIFloat(3), width: UIFloat(6), height: UIFloat(6))
        closeButton.frame = CGRect(x: container.bounds.maxX - UIFloat(26), y: 0, width: UIFloat(26), height: container.bounds.height)
        titleLabel.frame = CGRect(
            x: colorDot.frame.maxX + UIFloat(4),
            y: 0,
            width: max(0, closeButton.frame.minX - colorDot.frame.maxX - UIFloat(6)),
            height: container.bounds.height
        )
    }
}

extension TerminalWorkspaceViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView === tabBarCollectionView,
              let tabID = tabBarDataSource.itemIdentifier(for: indexPath) else { return }
        workspace.setActiveTab(tabID: tabID, in: windowPaneID)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let count = max(1, workspace.tabStates(in: windowPaneID).count)
        let available = collectionView.bounds.width - UIFloat(8)
        let spacing = UIFloat(4) * CGFloat(max(0, count - 1))
        let ideal = (available - spacing) / CGFloat(count)
        // Fill width like macOS tabs when few; shrink to a floor and scroll when many.
        let width = min(UIFloat(230), max(UIFloat(120), ideal))
        return CGSize(width: width, height: max(UIFloat(28), collectionView.bounds.height - UIFloat(8)))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let tabID = tabBarDataSource.itemIdentifier(for: indexPath),
              let tab = workspace.tabState(id: tabID) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.tabContextMenu(for: tab) ?? UIMenu()
        }
    }
}

extension TerminalWorkspaceViewController: UICollectionViewDragDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard let tabID = tabBarDataSource.itemIdentifier(for: indexPath) else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider(object: tabID.uuidString as NSString))
        item.localObject = tabID.uuidString
        return [item]
    }
}

extension TerminalWorkspaceViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil
    }

    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first,
              let value = item.dragItem.localObject as? String,
              let tabID = UUID(uuidString: value) else { return }
        let destinationIndex = coordinator.destinationIndexPath?.item
        workspace.moveTab(tabID: tabID, toWindow: windowID, at: destinationIndex)
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
