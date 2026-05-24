import Foundation
import Observation
import UIKit
import SwiftSH

struct TerminalSFTPEditPrompt: Identifiable, Equatable {
    let id: UUID
    let command: String
    let path: String
    let cwd: String

    init(command: String, path: String, cwd: String) {
        self.id = UUID()
        self.command = command
        self.path = path
        self.cwd = cwd
    }
}

@MainActor
protocol XTermTerminalHost: AnyObject {
    func write(_ text: String)
    func applySuggestion(_ text: String)
    func focusTerminal()
    func selectAll()
    func clearSelection()
    func submitEnter()
    func setFontSize(_ size: Int)
    func setTheme(_ payload: [String: String])
    func getCursorScreenPosition() async -> (point: CGPoint, cellHeight: CGFloat)?
    func getCommandLine() async -> String?
}

@MainActor
@Observable
final class XTermSessionController: Identifiable {
    let id: UUID
    let credentialKey: String
    var title: String
    private let tmuxSessionName: String?
    private let tmuxAttachOnly: Bool
    private let disableAutoPersistentSession: Bool

    var connectionStatus: TerminalConnectionStatus = .idle
    var shellIntegrationStatus: ShellIntegrationStatus = .unknown
    var cwd: String = "~"
    var promptBegin: PromptPosition?
    var promptEnd: PromptPosition?
    var activeCommand: ActiveCommandLifecycle?
    var suggestions: [CommandSuggestion] = []
    var selectedSuggestionIndex: Int = 0
    var history: [String] = []
    private var rawHistory: [String] = []
    var lastShellIntegrationWarning: String?
    var selectedText: String = ""
    var hasSelection: Bool = false
    var pendingSFTPEditPrompt: TerminalSFTPEditPrompt?
    var controlModifierArmed = false

    private weak var host: XTermTerminalHost?
    @ObservationIgnored
    private var retainedHostView: XTermWebHostView?
    private var stream: XTermSSHStream?
    private let suggestionEngine: CommandSuggestionProviding
    private let documentIndex: RemoteDocumentTreeIndex
    private var outputBacklog = ""
    private let maxBacklogBytes = 256_000

    private var inputBuffer = ""
    private var suggestionTask: Task<Void, Never>?
    private var shellIntegrationProbeTask: Task<Void, Never>?
    private var didSendShellBootstrap = false
    // Bootstrap output filter — active from preamble send until cwdChanged fires or 1 s after payload was sent.
    private var isFilteringBootstrap = false
    private var bootstrapLinePending = ""
    // Set when the filter stops — unblocks startup scripts.
    private var bootstrapPayloadSettled = false
    private var isAutoReloading = false
    private var autoReloadWindowStart: Date?
    private var autoReloadAttempts = 0
    private var lastAutoReloadAt: Date?
    private var bypassSFTPEditPromptOnce = false

    private static let sftpEditPromptNeverShowKey = "terminal.sftpEditorPrompt.neverShow"
    private static let autoReloadCooldown: TimeInterval = 2
    private static let autoReloadWindow: TimeInterval = 15
    private static let maxAutoReloadAttemptsPerWindow = 3
    static let autoTmuxSessionPrefix = "containeye-tab-"

    var currentInputBuffer: String {
        inputBuffer
    }

    /// True until bootstrap payload has settled.
    /// Use this to delay startup commands without waiting for shell integration to respond.
    var isBootstrapPending: Bool {
        !bootstrapPayloadSettled
    }

    init(
        id: UUID = UUID(),
        credentialKey: String,
        title: String,
        tmuxSessionName: String? = nil,
        tmuxAttachOnly: Bool = false,
        disableAutoPersistentSession: Bool = false,
        suggestionEngine: CommandSuggestionProviding,
        documentIndex: RemoteDocumentTreeIndex
    ) {
        self.id = id
        self.credentialKey = credentialKey
        self.title = title
        self.tmuxSessionName = tmuxSessionName
        self.tmuxAttachOnly = tmuxAttachOnly
        self.disableAutoPersistentSession = disableAutoPersistentSession
        self.suggestionEngine = suggestionEngine
        self.documentIndex = documentIndex
    }

    func makeOrReuseHostView() -> XTermWebHostView {
        if let retainedHostView {
            retainedHostView.bind(controller: self)
            return retainedHostView
        }
        let view = XTermWebHostView(controller: self)
        retainedHostView = view
        return view
    }

    func attach(host: XTermTerminalHost) {
        if self.host === host { return }
        self.host = host
        flushBacklog()
    }

    func detach(host: XTermTerminalHost) {
        if self.host === host {
            self.host = nil
        }
    }

    func connect() {
        guard stream == nil else {
            return
        }

        guard let credential = keychain().getCredential(for: credentialKey) else {
            connectionStatus = .failed
            lastShellIntegrationWarning = "Missing credential for key \(credentialKey)"
            return
        }

        connectionStatus = .connecting

        let stream = XTermSSHStream(
            credential: credential,
            startupCommand: makeSessionStartupCommand()
        )
        self.stream = stream

        stream.onOutput = { [weak self] output in
            Task { @MainActor in
                self?.handleShellOutput(output)
            }
        }

        stream.onConnected = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.connectionStatus = .connected
                self.isAutoReloading = false
                self.bootstrapShellIntegrationIfNeeded()
                self.loadHistoryIfNeeded()
                self.startShellIntegrationProbe()
            }
        }

        stream.onDisconnected = { [weak self] reason in
            Task { @MainActor in
                guard let self else { return }
                self.connectionStatus = .disconnected
                if let reason {
                    self.lastShellIntegrationWarning = reason
                }
                self.scheduleAutoReloadIfNeeded(reason: "disconnected")
            }
        }

        stream.connect()
    }

    func disconnect() {
        suggestionTask?.cancel()
        suggestionTask = nil
        shellIntegrationProbeTask?.cancel()
        shellIntegrationProbeTask = nil
        pendingSFTPEditPrompt = nil
        retainedHostView?.teardown()
        retainedHostView = nil
        stream?.disconnect()
        stream = nil
        connectionStatus = .disconnected
    }

    private func makeSessionStartupCommand() -> String? {
        let configuredSessionName: String
        let attachOnly: Bool

        if let explicit = tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            configuredSessionName = explicit
            attachOnly = tmuxAttachOnly
        } else {
            guard !disableAutoPersistentSession else { return nil }
            let mode = TerminalSettingsStore.shared.state.session.persistenceMode
            guard mode == .tmuxPerTab else { return nil }
            configuredSessionName = Self.persistentTmuxSessionName(forTabID: id)
            attachOnly = false
        }

        let quotedSessionName = Self.shellSingleQuoted(configuredSessionName)
        if attachOnly {
            return "if command -v tmux >/dev/null 2>&1; then tmux attach-session -t \(quotedSessionName); fi\r"
        }
        return "if command -v tmux >/dev/null 2>&1; then tmux new-session -A -s \(quotedSessionName); fi\r"
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    static func persistentTmuxSessionName(forTabID id: UUID) -> String {
        autoTmuxSessionPrefix + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    func sendInput(_ data: String) {
        guard !data.isEmpty else {
            return
        }

        if consumeArmedControlModifierIfNeeded(from: data) {
            return
        }

        // Accept selected suggestion on tab when available.
        if data == "\t", !suggestions.isEmpty {
            let index = suggestions.indices.contains(selectedSuggestionIndex) ? selectedSuggestionIndex : 0
            applySuggestion(suggestions[index].text)
            return
        }

        let submittedCommand = extractSubmittedCommand(from: data)

        if bypassSFTPEditPromptOnce, submittedCommand != nil {
            bypassSFTPEditPromptOnce = false
        } else if shouldShowSFTPEditPrompt,
                  let commandLine = submittedCommand,
                  maybePrepareSFTPEditPrompt(for: commandLine) {
            let forwardedScalars = data.unicodeScalars.filter { $0.value != 0x0d && $0.value != 0x0a }
            if !forwardedScalars.isEmpty {
                let forwarded = String(String.UnicodeScalarView(forwardedScalars))
                updateInputBuffer(with: forwarded)
                stream?.write(forwarded)
                scheduleSuggestionRefresh()
            }
            return
        }

        updateInputBuffer(with: data)
        stream?.write(data)
        scheduleSuggestionRefresh()
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else {
            return
        }
        stream?.resize(cols: cols, rows: rows)
    }

    func applySuggestion(_ suggestion: String) {
        inputBuffer = suggestion
        suggestions = []
        host?.applySuggestion(suggestion)
    }

    func focus() {
        host?.focusTerminal()
    }

    func cursorScreenPosition() async -> (point: CGPoint, cellHeight: CGFloat)? {
        await host?.getCursorScreenPosition()
    }

    func selectAll() {
        host?.selectAll()
    }

    func clearSelection() {
        host?.clearSelection()
        selectedText = ""
        hasSelection = false
    }

    func copySelectionToPasteboard() {
        guard hasSelection, !selectedText.isEmpty else {
            return
        }
        UIPasteboard.general.string = selectedText
    }

    func sendArrowUp() {
        clearControlModifier()
        stream?.write("\u{1B}[A")
    }

    func sendArrowDown() {
        clearControlModifier()
        stream?.write("\u{1B}[B")
    }

    func sendArrowLeft() {
        clearControlModifier()
        stream?.write("\u{1B}[D")
    }

    func sendArrowRight() {
        clearControlModifier()
        stream?.write("\u{1B}[C")
    }

    func sendPageUp() {
        clearControlModifier()
        stream?.write("\u{1B}[5~")
    }

    func sendPageDown() {
        clearControlModifier()
        stream?.write("\u{1B}[6~")
    }

    func sendInterrupt() {
        clearControlModifier()
        stream?.write("\u{3}")
    }

    func sendEscape() {
        clearControlModifier()
        stream?.write("\u{1B}")
    }

    func sendTabKey() {
        clearControlModifier()
        sendInput("\t")
    }

    func sendBackspace() {
        clearControlModifier()
        sendInput("\u{7F}")
    }

    func sendEnter() {
        clearControlModifier()
        sendInput("\r")
    }

    func toggleControlModifier() {
        controlModifierArmed.toggle()
    }

    func clearControlModifier() {
        controlModifierArmed = false
    }

    func openPendingFileInSFTP() {
        guard let pending = pendingSFTPEditPrompt else {
            return
        }

        // Clear the currently typed shell line since we intercepted Enter.
        sendControlCharacter(0x15)
        inputBuffer.removeAll(keepingCapacity: true)
        suggestions = []

        TerminalNavigationManager.shared.navigateToSFTPEditor(
            credentialKey: credentialKey,
            path: pending.path,
            cwd: pending.cwd
        )
        pendingSFTPEditPrompt = nil
    }

    func continuePendingSFTPEditInTerminal() {
        guard pendingSFTPEditPrompt != nil else {
            return
        }
        pendingSFTPEditPrompt = nil
        bypassSFTPEditPromptOnce = true
        host?.submitEnter()
    }

    func dismissPendingSFTPEditPrompt(neverShowAgain: Bool) {
        if neverShowAgain {
            UserDefaults.standard.set(true, forKey: Self.sftpEditPromptNeverShowKey)
        }
        pendingSFTPEditPrompt = nil
    }

    func handleBridgeEvent(_ event: XTermBridgeEvent) {
        switch event.type {
        case .terminalReady:
            connect()
            if let cols = event.cols, let rows = event.rows {
                resize(cols: cols, rows: rows)
            }

        case .terminalData:
            if let data = event.data {
                sendInput(data)
            }

        case .terminalResized:
            if let cols = event.cols, let rows = event.rows {
                resize(cols: cols, rows: rows)
            }

        case .cwdChanged:
            if let cwd = event.cwd {
                self.cwd = cwd
                shellIntegrationStatus = .active
                shellIntegrationProbeTask?.cancel()
                shellIntegrationProbeTask = nil
                stopBootstrapFilter()
                Task { [documentIndex, credentialKey, cwd, keychain] in
                    await documentIndex.bootstrap(credentialKey: credentialKey, cwd: cwd)
                    guard let credential = keychain().getCredential(for: credentialKey) else { return }
                    let escapedDir = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
                    let command = "cd \(escapedDir) 2>/dev/null && ls -1Ap 2>/dev/null | head -n 200"
                    guard let output = try? await SSHClientActor.shared.execute(command, on: credential) else { return }
                    let entries = output.split(whereSeparator: \.isNewline)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
                    await documentIndex.populate(credentialKey: credentialKey, directory: cwd, entries: entries)
                }
            }

        case .promptBegins:
            if let row = event.payload["row"] as? Int,
               let col = event.payload["col"] as? Int {
                promptBegin = .init(row: row, col: col)
            }

        case .promptEnds:
            if let row = event.payload["row"] as? Int,
               let col = event.payload["col"] as? Int {
                promptEnd = .init(row: row, col: col)
            }

        case .commandStarted:
            if let command = event.command {
                activeCommand = ActiveCommandLifecycle(command: command, startedAtMs: Date().timeIntervalSince1970 * 1000)
            }

        case .commandExited:
            if var current = activeCommand {
                current.exitCode = event.exitCode
                current.endedAtMs = Date().timeIntervalSince1970 * 1000
                activeCommand = current
            }

        case .shellIntegrationError:
            shellIntegrationStatus = .warning
            shellIntegrationProbeTask?.cancel()
            shellIntegrationProbeTask = nil
            if let reason = event.payload["reason"] as? String {
                let details = event.payload["details"] as? String ?? ""
                lastShellIntegrationWarning = details.isEmpty ? reason : "\(reason): \(details)"
            }
            scheduleAutoReloadIfNeeded(reason: "shell_integration_error")

        case .selectionChanged:
            let text = event.payload["selection"] as? String ?? ""
            let explicitFlag = event.payload["hasSelection"] as? Bool
            selectedText = text
            hasSelection = explicitFlag ?? !text.isEmpty

        case .selectionHint, .copySelection, .contextMenuRequested:
            break

        case .openExternalLink:
            if let raw = event.payload["url"] as? String,
               let url = URL(string: raw) {
                UIApplication.shared.open(url)
            }

        case .editorCommandEntered:
            let line = event.editorCommandLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if shouldShowSFTPEditPrompt, maybePrepareSFTPEditPrompt(for: line) {
                break
            }
            // If prompt is disabled or parsing failed, continue with normal Enter behavior.
            bypassSFTPEditPromptOnce = true
            host?.submitEnter()
        }
    }

    private func handleShellOutput(_ output: String) {
        let visible = isFilteringBootstrap ? applyBootstrapFilter(output) : output
        guard !visible.isEmpty else { return }
        if let host {
            host.write(visible)
        } else {
            outputBacklog += visible
            if outputBacklog.utf8.count > maxBacklogBytes {
                let cut = outputBacklog.index(outputBacklog.endIndex, offsetBy: -maxBacklogBytes)
                outputBacklog = String(outputBacklog[cut...])
            }
        }
    }

    /// Line-based filter active during the bootstrap window.
    /// Drops complete lines that contain bootstrap-injection patterns before they reach xterm.js.
    private func applyBootstrapFilter(_ output: String) -> String {
        bootstrapLinePending += output
        var result = ""

        // Process every complete line (terminated by \n).
        while let nlIdx = bootstrapLinePending.firstIndex(of: "\n") {
            let line = String(bootstrapLinePending[..<nlIdx])
            bootstrapLinePending = String(bootstrapLinePending[bootstrapLinePending.index(after: nlIdx)...])

            if isBootstrapNoise(line) {
                continue // drop this bootstrap line
            }
            result += line + "\n"
        }

        // Pass through the incomplete tail unless it already contains a bootstrap marker —
        // in that case hold it; the rest of the line (and its \n) will arrive in the next chunk.
        if !bootstrapLinePending.isEmpty {
            let tail = bootstrapLinePending
            if !isBootstrapNoise(tail) {
                result += tail
                bootstrapLinePending = ""
            }
            // else: keep in bootstrapLinePending until \n arrives
        }

        return result
    }

    private func stopBootstrapFilter() {
        guard isFilteringBootstrap else { return }
        isFilteringBootstrap = false
        bootstrapPayloadSettled = true
        // Flush any buffered non-bootstrap content so real output is not lost.
        guard !bootstrapLinePending.isEmpty else { return }
        var flushed = ""
        while let nlIdx = bootstrapLinePending.firstIndex(of: "\n") {
            let line = String(bootstrapLinePending[..<nlIdx])
            bootstrapLinePending = String(bootstrapLinePending[bootstrapLinePending.index(after: nlIdx)...])
            if !isBootstrapNoise(line) {
                flushed += line + "\n"
            }
        }
        if !bootstrapLinePending.isEmpty && !isBootstrapNoise(bootstrapLinePending) {
            flushed += bootstrapLinePending
        }
        bootstrapLinePending = ""
        if !flushed.isEmpty { host?.write(flushed) }
    }

    private func isBootstrapNoise(_ text: String) -> Bool {
        text.contains("__ce_shell_integration_payload=")
            || text.contains("__CE_OSC4545_INSTALLED")
    }

    private func flushBacklog() {
        guard !outputBacklog.isEmpty else {
            return
        }

        host?.write(outputBacklog)
        outputBacklog.removeAll(keepingCapacity: false)
    }

    private func bootstrapShellIntegrationIfNeeded() {
        if launchesIntoTmux {
            // Keep tmux sessions untouched so existing pane output is not disturbed by bootstrap commands.
            bootstrapPayloadSettled = true
            return
        }

        guard !didSendShellBootstrap else {
            return
        }
        didSendShellBootstrap = true
        isFilteringBootstrap = true
        bootstrapLinePending = ""
        stream?.write(ShellIntegrationBootstrap.installCommand())
        // Stop filtering shortly after the payload write.
        // cwdChanged (shell integration active) will stop the filter even sooner.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            await MainActor.run { self.stopBootstrapFilter() }
        }
    }

    private var launchesIntoTmux: Bool {
        if let explicit = tmuxSessionName?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return true
        }
        guard !disableAutoPersistentSession else { return false }
        return TerminalSettingsStore.shared.state.session.persistenceMode == .tmuxPerTab
    }

    private func startShellIntegrationProbe() {
        shellIntegrationProbeTask?.cancel()
        shellIntegrationProbeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }
            // Timeout is not fatal — shell integration simply isn't available on this server.
        }
    }

    private func scheduleAutoReloadIfNeeded(reason: String) {
        let now = Date()
        if let last = lastAutoReloadAt,
           now.timeIntervalSince(last) < Self.autoReloadCooldown {
            return
        }

        if let windowStart = autoReloadWindowStart,
           now.timeIntervalSince(windowStart) <= Self.autoReloadWindow {
            if autoReloadAttempts >= Self.maxAutoReloadAttemptsPerWindow {
                return
            }
        } else {
            autoReloadWindowStart = now
            autoReloadAttempts = 0
        }

        guard !isAutoReloading else {
            return
        }

        isAutoReloading = true
        autoReloadAttempts += 1
        lastAutoReloadAt = now
        terminalDebug("auto-reload scheduled (\(reason), attempt \(autoReloadAttempts))")

        shellIntegrationProbeTask?.cancel()
        shellIntegrationProbeTask = nil
        didSendShellBootstrap = false
        bootstrapPayloadSettled = false
        shellIntegrationStatus = .unknown
        stopBootstrapFilter()

        stream?.disconnect()
        stream = nil
        connect()
    }

    private func terminalDebug(_ message: String) {
        let shortID = id.uuidString.prefix(6)
        print("TerminalDebug[\(shortID)] \(message)")
    }

    private func loadHistoryIfNeeded() {
        guard history.isEmpty else {
            return
        }

        guard let credential = keychain().getCredential(for: credentialKey) else {
            return
        }

        Task.detached(priority: .background) {
            let command = #"(cat ~/.bash_history 2>/dev/null; [ -f ~/.bash_history ] && echo ""; cat ~/.zsh_history 2>/dev/null) | tail -n 500"#
            let output = (try? await SSHClientActor.shared.execute(command, on: credential)) ?? ""
            let parsed = output
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let deduped = Array(NSOrderedSet(array: parsed).array as? [String] ?? parsed)

            await MainActor.run {
                self.rawHistory = parsed
                self.history = deduped
            }
        }
    }

    private func updateInputBuffer(with data: String) {
        let scalars = Array(data.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            // Detect ESC + DEL (Option+Backspace = delete word)
            if scalar.value == 0x1B,
               i + 1 < scalars.count,
               scalars[i + 1].value == 0x7F {
                deleteWordBackward()
                i += 2
                continue
            }
            switch scalar.value {
            case 0x7f, 0x08: // Backspace
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                }
            case 0x0d, 0x0a: // Enter
                inputBuffer.removeAll(keepingCapacity: true)
                suggestions = []
                selectedSuggestionIndex = 0
            case 0x15: // Ctrl+U
                inputBuffer.removeAll(keepingCapacity: true)
                suggestions = []
                selectedSuggestionIndex = 0
            default:
                if !CharacterSet.controlCharacters.contains(scalar) {
                    inputBuffer.unicodeScalars.append(scalar)
                }
            }
            i += 1
        }
        inputBuffer = sanitizeBracketedPasteArtifacts(in: inputBuffer)
    }

    private func deleteWordBackward() {
        guard !inputBuffer.isEmpty else { return }
        while inputBuffer.last?.isWhitespace == true {
            inputBuffer.removeLast()
        }
        while !inputBuffer.isEmpty && inputBuffer.last?.isWhitespace != true {
            inputBuffer.removeLast()
        }
    }

    private func sendControlCharacter(_ code: UInt8, clearInputBuffer: Bool = false) {
        guard let scalar = UnicodeScalar(Int(code)) else {
            return
        }
        controlModifierArmed = false
        stream?.write(String(scalar))
        if clearInputBuffer {
            inputBuffer.removeAll(keepingCapacity: true)
            suggestions = []
        }
    }

    private var shouldShowSFTPEditPrompt: Bool {
        !UserDefaults.standard.bool(forKey: Self.sftpEditPromptNeverShowKey)
    }

    private func extractSubmittedCommand(from data: String) -> String? {
        var buffer = inputBuffer
        for scalar in data.unicodeScalars {
            switch scalar.value {
            case 0x7f, 0x08: // Backspace
                if !buffer.isEmpty {
                    buffer.removeLast()
                }
            case 0x15: // Ctrl+U
                buffer.removeAll(keepingCapacity: true)
            case 0x0d, 0x0a: // Enter
                let command = sanitizeBracketedPasteArtifacts(in: buffer)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return command.isEmpty ? nil : command
            default:
                if !CharacterSet.controlCharacters.contains(scalar) {
                    buffer.unicodeScalars.append(scalar)
                }
            }
        }
        return nil
    }

    private func sanitizeBracketedPasteArtifacts(in value: String) -> String {
        value
            .replacingOccurrences(of: "\u{1B}[200~", with: "")
            .replacingOccurrences(of: "\u{1B}[201~", with: "")
            .replacingOccurrences(of: "[200~", with: "")
            .replacingOccurrences(of: "[201~", with: "")
    }

    private func consumeArmedControlModifierIfNeeded(from data: String) -> Bool {
        guard controlModifierArmed else {
            return false
        }

        defer { controlModifierArmed = false }

        guard data.unicodeScalars.count == 1,
              let scalar = data.unicodeScalars.first,
              let code = controlCode(for: scalar)
        else {
            return false
        }

        let clearsBuffer = (code == 0x03 || code == 0x04 || code == 0x1A)
        sendControlCharacter(code, clearInputBuffer: clearsBuffer)
        return true
    }

    private func controlCode(for scalar: UnicodeScalar) -> UInt8? {
        let value = scalar.value

        if value >= 97, value <= 122 { // a-z
            return UInt8(value - 96)
        }
        if value >= 65, value <= 90 { // A-Z
            return UInt8(value - 64)
        }

        switch value {
        case 32, 64: // Space or @ -> NUL
            return 0x00
        case 91: // [
            return 0x1B
        case 92: // \
            return 0x1C
        case 93: // ]
            return 0x1D
        case 94: // ^
            return 0x1E
        case 95: // _
            return 0x1F
        case 63: // ?
            return 0x7F
        default:
            return nil
        }
    }

    @discardableResult
    private func maybePrepareSFTPEditPrompt(for commandLine: String) -> Bool {
        guard pendingSFTPEditPrompt == nil else {
            return false
        }

        guard let parsed = parseSFTPEditCommand(commandLine) else {
            return false
        }

        pendingSFTPEditPrompt = TerminalSFTPEditPrompt(
            command: parsed.command,
            path: parsed.path,
            cwd: cwd
        )
        return true
    }

    private func parseSFTPEditCommand(_ line: String) -> (command: String, path: String)? {
        var tokens = tokenizeShellLine(line)
        guard !tokens.isEmpty else {
            return nil
        }

        if tokens.first == "sudo" {
            tokens.removeFirst()
            while let first = tokens.first, first.hasPrefix("-") {
                tokens.removeFirst()
                if first == "-u", !tokens.isEmpty {
                    tokens.removeFirst()
                }
            }
        }

        guard let command = tokens.first else {
            return nil
        }

        guard ["open", "nano", "vim", "nvim"].contains(command) else {
            return nil
        }

        let args = Array(tokens.dropFirst())
        guard let path = extractPathArgument(args, command: command) else {
            return nil
        }

        return (command: command, path: path)
    }

    private func extractPathArgument(_ args: [String], command: String) -> String? {
        var stopOptionParsing = false
        var candidate: String?

        for arg in args {
            if !stopOptionParsing, arg == "--" {
                stopOptionParsing = true
                continue
            }

            if !stopOptionParsing {
                if arg.hasPrefix("-") {
                    continue
                }
                if (command == "vim" || command == "nvim"), arg.hasPrefix("+") {
                    continue
                }
            }

            let normalized = normalizePathCandidate(arg)
            if !normalized.isEmpty {
                candidate = normalized
            }
        }

        return candidate
    }

    private func normalizePathCandidate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed == "-" {
            return ""
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return ""
        }

        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed), url.isFileURL {
            return url.path
        }

        return trimmed
    }

    private func tokenizeShellLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for char in line {
            if escaping {
                current.append(char)
                escaping = false
                continue
            }

            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    if char == "\\", activeQuote == "\"" {
                        escaping = true
                        continue
                    }
                    current.append(char)
                }
                continue
            }

            if char == "\\" {
                escaping = true
                continue
            }

            if char == "'" || char == "\"" {
                quote = char
                continue
            }

            if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(char)
        }

        if escaping {
            current.append("\\")
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private func scheduleSuggestionRefresh() {
        suggestionTask?.cancel()

        let input = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty,
              let credential = keychain().getCredential(for: credentialKey)
        else {
            suggestions = []
            return
        }

        let context = CommandSuggestionContext(
            input: input,
            credential: credential,
            currentDirectory: cwd,
            history: history,
            rawHistory: rawHistory
        )

        suggestionTask = Task { [suggestionEngine] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let values = await suggestionEngine.suggest(input: input, context: context)
            await MainActor.run {
                self.suggestions = values
                self.selectedSuggestionIndex = 0
            }
        }
    }
}

final class XTermSSHStream {
    var onOutput: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?

    private let credential: Credential
    private let startupCommand: String?
    private var shell: SSHShell?
    private let queue = DispatchQueue(label: "ContainEye.XTermSSHStream")

    init(credential: Credential, startupCommand: String? = nil) {
        self.credential = credential
        self.startupCommand = startupCommand
    }

    func connect() {
        let challenge: AuthenticationChallenge

        switch credential.effectiveAuthMethod {
        case .password:
            challenge = .byPassword(username: credential.username, password: credential.password)
        case .privateKey:
            challenge = .byPublicKeyFromMemory(
                username: credential.username,
                password: "",
                publicKey: nil,
                privateKey: credential.privateKey?.data(using: .utf8) ?? Data()
            )
        case .privateKeyWithPassphrase:
            challenge = .byPublicKeyFromMemory(
                username: credential.username,
                password: credential.passphrase ?? credential.password,
                publicKey: nil,
                privateKey: credential.privateKey?.data(using: .utf8) ?? Data()
            )
        }

        let shell = try? SSHShell(
            sshLibrary: Libssh2.self,
            host: credential.host,
            port: UInt16(credential.port),
            environment: [Environment(name: "LANG", variable: "en_US.UTF-8")],
            terminal: "xterm-256color"
        )

        guard let shell else {
            onDisconnected?("Failed to initialize SSH shell")
            return
        }

        self.shell = shell
        shell.log.enabled = false
        shell.setCallbackQueue(queue: queue)

        shell.withCallback { [weak self] data, error in
            guard let self else { return }
            if let data {
                let text = String(decoding: data, as: UTF8.self)
                self.onOutput?(text)
            }
            if let error, !error.isEmpty {
                let message = String(decoding: error, as: UTF8.self)
                self.onDisconnected?(message)
            }
        }
        .connect()
        .authenticate(challenge)
        .open { [weak self] error in
            guard let self else { return }
            if let error {
                self.onDisconnected?("SSH open error: \(error)")
            } else {
                if let startupCommand, !startupCommand.isEmpty {
                    self.write(startupCommand)
                    self.queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.onConnected?()
                    }
                } else {
                    self.onConnected?()
                }
            }
        }
    }

    func write(_ text: String) {
        shell?.write(Data(text.utf8)) { _ in }
    }

    func resize(cols: Int, rows: Int) {
        shell?.setTerminalSize(width: UInt(cols), height: UInt(rows))
    }

    func disconnect() {
        shell?.close { [weak self] in
            self?.onDisconnected?(nil)
        }
        shell = nil
    }
}
