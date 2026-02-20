import Foundation
import ObjectiveC.runtime
import SwiftUI
import UIKit
import WebKit

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
            let item = subview.inputAssistantItem
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
        guard hasActiveSelection, let editMenuInteraction else {
            return
        }

        becomeFirstResponder()
        didPresentSelectionMenu = true
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
        editMenuInteraction.presentEditMenu(with: config)
    }

    private func dismissSelectionMenu() {
        editMenuInteraction?.dismissMenu()
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
        var insertionIndex = 0
        if (hasActiveSelection || didPresentSelectionMenu), !containsCopyAction(in: suggestedActions) {
            let copyAction = UIAction(title: "Copy") { [weak self] _ in
                self?.copy(nil)
            }
            actions.insert(copyAction, at: insertionIndex)
            insertionIndex += 1
        }

        if hasActiveSelection || didPresentSelectionMenu {
            let askAIAction = UIAction(title: "Ask AI", image: UIImage(systemName: "sparkles")) { [weak self] _ in
                self?.askAIAboutSelection()
            }
            actions.insert(askAIAction, at: insertionIndex)
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

    private func askAIAboutSelection() {
        guard let selection = effectiveSelectionText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selection.isEmpty else {
            return
        }

        let sheet = UIHostingController(
            rootView: TerminalSelectionAIView(selectedText: String(selection.prefix(8000)))
        )
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
        }

        findTopViewController()?.present(sheet, animated: true)
    }

    private func findTopViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                var top = viewController
                while let presented = top.presentedViewController {
                    top = presented
                }
                return top
            }
            responder = next
        }
        return nil
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

private struct TerminalSelectionAIView: View {
    struct AIResponse: Decodable {
        struct Snippet: Decodable, Identifiable {
            let title: String?
            let language: String
            let code: String
            var id: String { "\(title ?? "")|\(language)|\(code)" }
        }

        let summary: [String]
        let whatItMeans: [String]
        let nextSteps: [String]
        let codeSnippets: [Snippet]
    }

    let selectedText: String
    @Environment(\.dismiss) private var dismiss
    @State private var response: AIResponse?
    @State private var fallbackText: String?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: UIFloat(14)) {
                    Group {
                        Text("Selected Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedText)
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(UIFloat(12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: UIFloat(10)))
                    }

                    if isLoading {
                        HStack(spacing: UIFloat(10)) {
                            ProgressView()
                            Text("Asking AI...")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, UIFloat(8))
                    } else if let response {
                        bulletsSection("Summary", items: response.summary)
                        bulletsSection("What It Means", items: response.whatItMeans)
                        bulletsSection("What To Do Next", items: response.nextSteps)

                        if !response.codeSnippets.isEmpty {
                            Text("Code Snippets")
                                .font(.headline)
                                .padding(.top, UIFloat(8))

                            ForEach(response.codeSnippets) { snippet in
                                VStack(alignment: .leading, spacing: UIFloat(8)) {
                                    HStack {
                                        Text(snippet.title?.isEmpty == false ? snippet.title! : snippet.language.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Copy") {
                                            UIPasteboard.general.string = snippet.code
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    ScrollView(.horizontal) {
                                        Text(snippet.code)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(UIFloat(10))
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: UIFloat(10)))
                                }
                            }
                        }
                    } else if let fallbackText {
                        Text("AI Explanation")
                            .font(.headline)
                        Text(fallbackText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(UIFloat(16))
            }
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }
            }
            .task {
                await generateExplanation()
            }
        }
    }

    private func generateExplanation() async {
        let prompt = """
Explain the selected terminal text and respond ONLY with JSON.
Use this exact schema:
{
  "summary": ["..."],
  "whatItMeans": ["..."],
  "nextSteps": ["..."],
  "codeSnippets": [
    {
      "title": "Optional short title",
      "language": "bash",
      "code": "command here"
    }
  ]
}

Rules:
- Do not include markdown fences.
- Do not include extra keys.
- Keep each bullet concise.
- Include at least one snippet in codeSnippets when a command is useful.

Selected text:
```
\(selectedText)
```
"""

        let output = await LLM.generate(
            prompt: prompt,
            systemPrompt: "You are a terminal assistant. Return valid JSON only and exactly follow the requested schema."
        ).output

        let cleaned = LLM.cleanLLMOutput(output).trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            if cleaned.isEmpty {
                errorMessage = "AI returned an empty response."
            } else {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let data = cleaned.data(using: .utf8),
                   let decoded = try? decoder.decode(AIResponse.self, from: data) {
                    response = decoded
                } else {
                    fallbackText = cleaned
                    errorMessage = "AI response did not match the expected JSON format."
                }
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func bulletsSection(_ title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: UIFloat(6)) {
                Text(title)
                    .font(.headline)
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
