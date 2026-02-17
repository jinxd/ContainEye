import Foundation
import ObjectiveC.runtime
import SwiftUI
import UIKit
import WebKit

struct XTermTerminalView: UIViewRepresentable {
    let controller: XTermSessionController

    func makeUIView(context: Context) -> XTermWebHostView {
        controller.makeOrReuseHostView()
    }

    func updateUIView(_ uiView: XTermWebHostView, context: Context) {
        uiView.bind(controller: controller)
    }

    static func dismantleUIView(_ uiView: XTermWebHostView, coordinator: ()) {
        // Keep the host alive while the session controller is alive so switching tabs
        // does not reset the visible terminal state.
    }
}

@MainActor
final class XTermWebHostView: UIView, XTermTerminalHost, @preconcurrency UIEditMenuInteractionDelegate {
    private let webView: WKWebView
    private weak var controller: XTermSessionController?
    private var isReady = false
    private var commandQueue: [String] = []
    private let scriptHandler: XTermBridgeScriptHandler
    private var editMenuInteraction: UIEditMenuInteraction?
    private var hasActiveSelection = false
    private var didPresentSelectionMenu = false
    private var selectionMenuPoint: CGPoint = .zero
    private var lastSelectionText = ""
    private var hintLabel: UILabel?
    private var hintHideTask: Task<Void, Never>?

    init(controller: XTermSessionController) {
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        scriptHandler = XTermBridgeScriptHandler()

        super.init(frame: .zero)

        scriptHandler.owner = self
        contentController.add(scriptHandler, name: "terminalBridge")
        if #available(iOS 16.0, *) {
            let interaction = UIEditMenuInteraction(delegate: self)
            addInteraction(interaction)
            editMenuInteraction = interaction
        }

        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        disableInputAssistantBar()

        addSubview(webView)

        bind(controller: controller)
        loadTerminalPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func teardown() {
        dismissSelectionMenu()
        hintHideTask?.cancel()
        hintHideTask = nil
        hintLabel?.removeFromSuperview()
        hintLabel = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "terminalBridge")
        controller?.detach(host: self)
        controller = nil
    }

    func bind(controller: XTermSessionController) {
        if self.controller === controller {
            controller.attach(host: self)
            return
        }
        self.controller?.detach(host: self)
        self.controller = controller
        controller.attach(host: self)
    }

    func write(_ text: String) {
        enqueueOrRun(js: "window.terminalHost?.write(\(jsonString(text)));")
    }

    func applySuggestion(_ text: String) {
        enqueueOrRun(js: "window.terminalHost?.applySuggestion(\(jsonString(text)));")
    }

    func focusTerminal() {
        disableInputAssistantBar()
        enqueueOrRun(js: "window.terminalHost?.focus();")
    }

    func selectAll() {
        enqueueOrRun(js: "window.terminalHost?.selectAll();")
    }

    func clearSelection() {
        enqueueOrRun(js: "window.terminalHost?.clearSelection();")
        hasActiveSelection = false
        didPresentSelectionMenu = false
        lastSelectionText = ""
        dismissSelectionMenu()
    }

    func submitEnter() {
        enqueueOrRun(js: "window.terminalHost?.submitEnter?.();")
    }

    private func loadTerminalPage() {
        let subdirectories = [
            "",
            "TerminalTab/TerminalWeb",
            "TerminalWeb",
        ]

        for subdir in subdirectories {
            let effectiveSubdir: String? = subdir.isEmpty ? nil : subdir
            if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: effectiveSubdir) {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                return
            }
        }

        webView.loadHTMLString("<html><body style='background:#111;color:white;font-family:monospace'>Terminal assets missing.</body></html>", baseURL: nil)
    }

    private func enqueueOrRun(js: String) {
        guard isReady else {
            commandQueue.append(js)
            return
        }

        webView.evaluateJavaScript(js)
    }

    fileprivate func handleScriptMessage(_ message: WKScriptMessage) {
        guard let event = XTermBridgeEvent(body: message.body) else {
            return
        }

        if event.type == .selectionChanged {
            updateSelectionMenu(with: event)
        }
        if event.type == .selectionHint {
            let text = event.selectionHintMessage ?? "Press and hold, then move your finger to select"
            showSelectionHint(text)
        }

        if event.type == .terminalReady {
            isReady = true
            flushCommandQueue()
        }

        controller?.handleBridgeEvent(event)
    }

    private func flushCommandQueue() {
        guard isReady else {
            return
        }

        let pending = commandQueue
        commandQueue.removeAll(keepingCapacity: false)

        for js in pending {
            webView.evaluateJavaScript(js)
        }
    }

    private func jsonString(_ text: String) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(text), let json = String(data: data, encoding: .utf8) {
            return json
        }

        return "\"\""
    }

    private func disableInputAssistantBar() {
        let assistant = webView.inputAssistantItem
        assistant.leadingBarButtonGroups = []
        assistant.trailingBarButtonGroups = []

        for subview in webView.scrollView.subviews {
            guard let responder = subview as? UIResponder else {
                continue
            }
            let item = responder.inputAssistantItem
            item.leadingBarButtonGroups = []
            item.trailingBarButtonGroups = []
            installNoAccessoryViewClassIfNeeded(on: subview)
        }
    }

    private func installNoAccessoryViewClassIfNeeded(on view: UIView) {
        guard String(describing: type(of: view)).hasPrefix("WKContent") else {
            return
        }

        guard let currentClass: AnyClass = object_getClass(view) else {
            return
        }

        let newClassName = "\(NSStringFromClass(currentClass))_NoInputAccessory"
        if let existing = NSClassFromString(newClassName) {
            object_setClass(view, existing)
            return
        }

        guard let nameCString = (newClassName as NSString).utf8String,
              let subclass = objc_allocateClassPair(currentClass, nameCString, 0) else {
            return
        }

        let selector = #selector(getter: UIView.inputAccessoryView)
        guard let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.noInputAccessoryView)) else {
            return
        }

        class_addMethod(subclass, selector, method_getImplementation(method), method_getTypeEncoding(method))
        objc_registerClassPair(subclass)
        object_setClass(view, subclass)
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        webView.frame = bounds

        guard let hintLabel else {
            return
        }

        let insets = UIEdgeInsets(top: UIFloat(12), left: UIFloat(16), bottom: UIFloat(12), right: UIFloat(16))
        let available = bounds.inset(by: insets)
        let measured = hintLabel.sizeThatFits(CGSize(width: available.width, height: CGFloat.greatestFiniteMagnitude))
        let width = min(available.width, measured.width)
        let height = measured.height
        let x = available.midX - width / 2
        hintLabel.frame = CGRect(origin: CGPoint(x: x, y: available.minY), size: CGSize(width: width, height: height))
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) {
            return hasActiveSelection || didPresentSelectionMenu
        }

        if action == #selector(selectAll(_:)) {
            return true
        }

        return false
    }

    override func copy(_ sender: Any?) {
        if let selected = effectiveSelectionText, !selected.isEmpty {
            UIPasteboard.general.string = selected
            didPresentSelectionMenu = false
            dismissSelectionMenu()
            return
        }

        webView.evaluateJavaScript("window.terminalHost?.getSelectionText?.();") { [weak self] result, _ in
            guard let self else { return }
            if let text = result as? String, !text.isEmpty {
                UIPasteboard.general.string = text
                self.lastSelectionText = text
            }
            self.didPresentSelectionMenu = false
            self.dismissSelectionMenu()
        }
    }

    override func selectAll(_ sender: Any?) {
        selectAll()
    }

    private func updateSelectionMenu(with event: XTermBridgeEvent) {
        let hadSelection = hasActiveSelection
        let text = event.selectionText ?? ""
        let hasSelection = event.hasSelection ?? !text.isEmpty

        hasActiveSelection = hasSelection
        lastSelectionText = text

        guard hasSelection else {
            didPresentSelectionMenu = false
            dismissSelectionMenu()
            return
        }

        let fallbackPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let requestedPoint = CGPoint(x: event.menuX ?? fallbackPoint.x, y: event.menuY ?? fallbackPoint.y)
        selectionMenuPoint = clampToBounds(requestedPoint)

        if !hadSelection || !didPresentSelectionMenu {
            presentSelectionMenu(at: selectionMenuPoint)
        }
    }

    private func clampToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 8), max(bounds.width - 8, 8)),
            y: min(max(point.y, 8), max(bounds.height - 8, 8))
        )
    }

    private func presentSelectionMenu(at point: CGPoint) {
        guard hasActiveSelection else {
            return
        }

        becomeFirstResponder()
        didPresentSelectionMenu = true
        if #available(iOS 16.0, *), let editMenuInteraction {
            let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
            editMenuInteraction.presentEditMenu(with: config)
            return
        }

        let rect = CGRect(x: point.x, y: point.y, width: 2, height: 2)
        UIMenuController.shared.showMenu(from: self, rect: rect)
    }

    private func dismissSelectionMenu() {
        if #available(iOS 16.0, *), let editMenuInteraction {
            editMenuInteraction.dismissMenu()
        } else {
            UIMenuController.shared.hideMenu()
        }
    }

    private func showSelectionHint(_ text: String) {
        let label: UILabel
        if let existing = hintLabel {
            label = existing
        } else {
            let created = UILabel()
            created.numberOfLines = 0
            created.textAlignment = .center
            created.font = .systemFont(ofSize: UIFloat(14), weight: .medium)
            created.adjustsFontForContentSizeCategory = true
            created.textColor = .white
            created.backgroundColor = UIColor.black.withAlphaComponent(0.9)
            created.layer.cornerRadius = UIFloat(14)
            created.layer.masksToBounds = true
            created.alpha = 0
            addSubview(created)
            hintLabel = created
            label = created
        }

        label.text = "   \(text)   "
        setNeedsLayout()
        UIView.animate(withDuration: 0.18) {
            label.alpha = 1
        }

        hintHideTask?.cancel()
        hintHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run {
                guard let self, let label = self.hintLabel else {
                    return
                }
                UIView.animate(withDuration: 0.22, animations: {
                    label.alpha = 0
                })
            }
        }
    }

    @available(iOS 16.0, *)
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        var actions = suggestedActions
        if (hasActiveSelection || didPresentSelectionMenu), !containsCopyAction(in: suggestedActions) {
            let copyAction = UIAction(title: "Copy") { [weak self] _ in
                self?.copy(nil)
            }
            actions.insert(copyAction, at: 0)
        }
        return UIMenu(children: actions)
    }

    private var effectiveSelectionText: String? {
        if let selected = controller?.selectedText, !selected.isEmpty {
            return selected
        }
        if !lastSelectionText.isEmpty {
            return lastSelectionText
        }
        return nil
    }

    @available(iOS 16.0, *)
    private func containsCopyAction(in elements: [UIMenuElement]) -> Bool {
        for element in elements {
            if let command = element as? UICommand, command.action == #selector(copy(_:)) {
                return true
            }
            if let menu = element as? UIMenu, containsCopyAction(in: menu.children) {
                return true
            }
        }
        return false
    }
}

final class XTermBridgeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: XTermWebHostView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak owner] in
            owner?.handleScriptMessage(message)
        }
    }
}

private extension UIView {
    @objc var noInputAccessoryView: UIView? { nil }
}
