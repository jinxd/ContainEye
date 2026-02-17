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
}

@MainActor
@Observable
final class XTermSessionController: Identifiable {
    let id: UUID
    let credentialKey: String
    var title: String

    var connectionStatus: TerminalConnectionStatus = .idle
    var shellIntegrationStatus: ShellIntegrationStatus = .unknown
    var cwd: String = "~"
    var promptBegin: PromptPosition?
    var promptEnd: PromptPosition?
    var activeCommand: ActiveCommandLifecycle?
    var suggestions: [CommandSuggestion] = []
    var history: [String] = []
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
    private var bypassSFTPEditPromptOnce = false

    private static let sftpEditPromptNeverShowKey = "terminal.sftpEditorPrompt.neverShow"

    init(
        id: UUID = UUID(),
        credentialKey: String,
        title: String,
        suggestionEngine: CommandSuggestionProviding,
        documentIndex: RemoteDocumentTreeIndex
    ) {
        self.id = id
        self.credentialKey = credentialKey
        self.title = title
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

        let stream = XTermSSHStream(credential: credential)
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

    func sendInput(_ data: String) {
        guard !data.isEmpty else {
            return
        }

        if consumeArmedControlModifierIfNeeded(from: data) {
            return
        }

        // Accept top suggestion on tab when available.
        if data == "\t", let first = suggestions.first {
            applySuggestion(first.text)
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
                Task { [documentIndex, credentialKey, cwd] in
                    await documentIndex.bootstrap(credentialKey: credentialKey, cwd: cwd)
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

        case .selectionChanged:
            let text = event.payload["selection"] as? String ?? ""
            let explicitFlag = event.payload["hasSelection"] as? Bool
            selectedText = text
            hasSelection = explicitFlag ?? !text.isEmpty

        case .selectionHint:
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
        if let host {
            host.write(output)
        } else {
            outputBacklog += output
            if outputBacklog.utf8.count > maxBacklogBytes {
                let cut = outputBacklog.index(outputBacklog.endIndex, offsetBy: -maxBacklogBytes)
                outputBacklog = String(outputBacklog[cut...])
            }
        }
    }

    private func flushBacklog() {
        guard !outputBacklog.isEmpty else {
            return
        }

        host?.write(outputBacklog)
        outputBacklog.removeAll(keepingCapacity: false)
    }

    private func bootstrapShellIntegrationIfNeeded() {
        guard !didSendShellBootstrap else {
            return
        }

        didSendShellBootstrap = true
        stream?.write("stty -echo\n")
        stream?.write(ShellIntegrationBootstrap.encodedInstallCommand())
        stream?.write("\n")
        stream?.write("stty echo\n")
        stream?.write("printf '\\r\\033[2K'\n")
    }

    private func startShellIntegrationProbe() {
        shellIntegrationProbeTask?.cancel()
        shellIntegrationProbeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }
            if shellIntegrationStatus == .unknown {
                shellIntegrationStatus = .warning
                if lastShellIntegrationWarning == nil {
                    lastShellIntegrationWarning = "Shell integration not detected (running in degraded terminal mode)."
                }
            }
        }
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
                self.history = deduped
            }
        }
    }

    private func updateInputBuffer(with data: String) {
        for scalar in data.unicodeScalars {
            switch scalar.value {
            case 0x7f, 0x08: // Backspace
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                }
            case 0x0d, 0x0a: // Enter
                inputBuffer.removeAll(keepingCapacity: true)
            case 0x15: // Ctrl+U
                inputBuffer.removeAll(keepingCapacity: true)
            default:
                if !CharacterSet.controlCharacters.contains(scalar) {
                    inputBuffer.unicodeScalars.append(scalar)
                }
            }
        }
        inputBuffer = sanitizeBracketedPasteArtifacts(in: inputBuffer)
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
            history: history
        )

        suggestionTask = Task { [suggestionEngine] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let values = await suggestionEngine.suggest(input: input, context: context)
            await MainActor.run {
                self.suggestions = values
            }
        }
    }
}

final class XTermSSHStream {
    var onOutput: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?

    private let credential: Credential
    private var shell: SSHShell?
    private let queue = DispatchQueue(label: "ContainEye.XTermSSHStream")

    init(credential: Credential) {
        self.credential = credential
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
                self.onConnected?()
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
