//
//  AgenticView.swift
//  ContainEye
//
//  Rebuilt Agentic tab with a simpler, stable architecture.
//

import SwiftUI
import Blackbird
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AgenticView: View {
    @Environment(\.blackbirdDatabase) private var db
    @Environment(\.agenticBridge) private var bridge
    @StateObject private var model = AgenticViewModel()
    @State private var showApprovalSettings = false

    var body: some View {
        VStack(spacing: 0) {
            List(model.messages) { message in
                AgenticMessageRow(message: message)
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
#endif

            Divider()

            composer
        }
        .navigationTitle("Agentic")
        .trackView("agentic")
        .task {
            await model.configure(database: db)
            await model.consumePendingContextIfNeeded(bridge: bridge)
        }
        .onChange(of: bridge.pendingContext?.id) {
            Task { await model.consumePendingContextIfNeeded(bridge: bridge) }
        }
        .confirmationDialog("Allow command execution?", isPresented: $model.showCommandApprovalAlert, titleVisibility: .visible, presenting: model.pendingApproval) { pending in
            Button("Allow Once") {
                Task { await model.resolveCommandApproval(allow: true, pending: pending) }
            }

            if let prefix = pending.commandPrefix {
                Button("Always Allow \"\(prefix)\" Commands") {
                    Task { await model.resolveCommandApprovalAlwaysPrefix(pending: pending) }
                }
            }

            Button("Always Allow All Commands") {
                Task { await model.resolveCommandApprovalAlwaysAll(pending: pending) }
            }

            Button("Deny", role: .destructive) {
                Task { await model.resolveCommandApproval(allow: false, pending: pending) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("\(pending.serverLabel)\n\(pending.command)")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        model.startNewSession()
                    } label: {
                        Label("New Session", systemImage: "plus.bubble")
                    }

                    Button {
                        model.copyChatHistory()
                    } label: {
                        Label("Copy Chat History", systemImage: "doc.on.doc")
                    }

                    Button {
                        showApprovalSettings = true
                    } label: {
                        Label("Command Approval Settings", systemImage: "checkmark.shield")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showApprovalSettings) {
            AgenticApprovalSettingsView(model: model)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Agent is working…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let context = model.pendingComposerContext, !context.isEmpty {
                HStack(spacing: 8) {
                    Text("Context attached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { model.clearComposerContext() }
                        .font(.caption)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the agent…", text: $model.input, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isRunning)

                Button {
                    Task { await model.send() }
                } label: {
                    if model.isRunning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning || !model.canSend)
            }
        }
        .padding(12)
    }
}

private struct AgenticApprovalSettingsView: View {
    @ObservedObject var model: AgenticViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Global") {
                    Toggle("Always allow all commands", isOn: Binding(
                        get: { model.approvalAllowAllCommands },
                        set: { model.setApprovalAllowAllCommands($0) }
                    ))
                }

                Section("Allowed prefixes") {
                    if model.approvalAllowedPrefixes.isEmpty {
                        Text("No saved prefixes.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.approvalAllowedPrefixes, id: \.self) { prefix in
                            HStack {
                                Text(prefix)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(role: .destructive) {
                                    model.removeApprovalPrefix(prefix)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section {
                    Button("Reset All Command Approvals", role: .destructive) {
                        model.resetApprovalPreferences()
                    }
                }
            }
            .navigationTitle("Command Approvals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AgenticMessageRow: View {
    let message: AgenticTimelineMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Group {
                if message.role == .thinking {
                    DisclosureGroup("Thinking") {
                        Text(message.content)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if message.role == .tool {
                    DisclosureGroup(toolPreviewLabel) {
                        Text(message.content)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(.init(message.content))
                        .font(message.role == .tool ? .system(.footnote, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .blue.opacity(0.18)
        case .assistant: return .secondary.opacity(0.12)
        case .tool: return .green.opacity(0.12)
        case .error: return .red.opacity(0.14)
        case .thinking: return .orange.opacity(0.10)
        case .status: return .gray.opacity(0.10)
        }
    }

    private var toolPreviewLabel: String {
        let firstLine = message.content.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "Tool output"
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Tool output" }
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
    }
}

@MainActor
final class AgenticViewModel: ObservableObject {
    @Published var messages: [AgenticTimelineMessage] = []
    @Published var input = ""
    @Published var isRunning = false
    @Published var pendingComposerContext: String?
    @Published var pendingApproval: AgenticCommandApprovalContext?
    @Published var showCommandApprovalAlert = false
    @Published private(set) var approvalAllowAllCommands = false
    @Published private(set) var approvalAllowedPrefixes: [String] = []

    private var database: Blackbird.Database?
    private var llmHistory: [[String: Any]] = []
    private var waitingApprovalState: AgenticApprovalState?
    private let sessionStore = AgenticSessionStore()
    private var approvalPreferences = AgenticCommandApprovalPreferences.load()

    func configure(database: Blackbird.Database?) async {
        self.database = database
        syncApprovalPublishedState()
        let restored = sessionStore.load()
        messages = restored.messages
        llmHistory = restored.llmHistory
    }

    var canSend: Bool {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = pendingComposerContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !typed.isEmpty || !context.isEmpty
    }

    func startNewSession() {
        messages = []
        llmHistory = []
        input = ""
        pendingComposerContext = nil
        sessionStore.save(messages: messages, llmHistory: llmHistory)
    }

    func clearComposerContext() {
        pendingComposerContext = nil
    }

    func copyChatHistory() {
        let transcript = messages
            .map { "[\($0.role.label)]\n\($0.content)" }
            .joined(separator: "\n\n")
#if canImport(UIKit)
        UIPasteboard.general.string = transcript
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
#endif
    }

    func consumePendingContextIfNeeded(bridge: AgenticContextBridge) async {
        guard let context = bridge.consumePendingContext() else { return }
        switch context.deliveryMode {
        case .composerDraft:
            pendingComposerContext = context.draftMessage
        case .userMessage:
            pendingComposerContext = nil
            let prompt = context.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return }
            appendMessage(role: .user, content: prompt)
            llmHistory.append(["role": "user", "content": prompt])
            if context.autoRunAgent {
                await runAgentLoop()
            }
        }
    }

    func send() async {
        guard !isRunning else { return }
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = pendingComposerContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if typed.hasPrefix("/") {
            input = ""
            pendingComposerContext = nil
            handleSlashCommand(typed)
            return
        }
        let prompt: String
        if !context.isEmpty, !typed.isEmpty {
            prompt = "\(context)\n\n\(typed)"
        } else if !context.isEmpty {
            prompt = context
        } else {
            prompt = typed
        }
        guard !prompt.isEmpty else { return }

        input = ""
        pendingComposerContext = nil
        appendMessage(role: .user, content: prompt)
        llmHistory.append(["role": "user", "content": prompt])
        await runAgentLoop()
    }

    private func handleSlashCommand(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let command = parts.first.map { String($0).lowercased() } ?? ""
        let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch command {
        case "/help", "/commands":
            appendMessage(role: .status, content: slashHelpText())
        case "/clear":
            messages = []
            llmHistory = []
            sessionStore.save(messages: messages, llmHistory: llmHistory)
        case "/compact":
            compactSession()
        case "/permissions":
            appendMessage(role: .status, content: permissionsSummary())
        case "/allow-all":
            setApprovalAllowAllCommands(true)
            appendMessage(role: .status, content: "All commands are now always allowed.")
        case "/disallow-all":
            setApprovalAllowAllCommands(false)
            appendMessage(role: .status, content: "Global allow-all disabled.")
        case "/allow-prefix":
            guard !arg.isEmpty else {
                appendMessage(role: .error, content: "Usage: /allow-prefix <prefix>")
                return
            }
            approvalPreferences.allowedCommandPrefixes.insert(arg)
            approvalPreferences.save()
            syncApprovalPublishedState()
            appendMessage(role: .status, content: "Added allowed prefix: \(arg)")
        case "/unallow-prefix":
            guard !arg.isEmpty else {
                appendMessage(role: .error, content: "Usage: /unallow-prefix <prefix>")
                return
            }
            if approvalPreferences.allowedCommandPrefixes.remove(arg) != nil {
                approvalPreferences.save()
                syncApprovalPublishedState()
                appendMessage(role: .status, content: "Removed allowed prefix: \(arg)")
            } else {
                appendMessage(role: .status, content: "Prefix not found: \(arg)")
            }
        case "/reset-permissions", "/reset-approvals":
            resetApprovalPreferences()
            appendMessage(role: .status, content: "Command approvals reset.")
        default:
            appendMessage(role: .error, content: "Unknown command \(command). Use /help.")
        }
        sessionStore.save(messages: messages, llmHistory: llmHistory)
    }

    private func compactSession() {
        let keepMessages = 40
        let keepHistory = 20
        guard messages.count > keepMessages || llmHistory.count > keepHistory else {
            appendMessage(role: .status, content: "Nothing to compact.")
            return
        }

        let droppedMessages = max(0, messages.count - keepMessages)
        let droppedHistory = max(0, llmHistory.count - keepHistory)

        if droppedMessages > 0 {
            messages = Array(messages.suffix(keepMessages))
        }
        if droppedHistory > 0 {
            llmHistory = Array(llmHistory.suffix(keepHistory))
        }

        appendMessage(role: .status, content: "Compacted session. Dropped \(droppedMessages) messages and \(droppedHistory) history items.")
    }

    private func permissionsSummary() -> String {
        let all = approvalPreferences.allowAllCommands ? "ON" : "OFF"
        let prefixes = approvalPreferences.allowedCommandPrefixes.sorted()
        let prefixText = prefixes.isEmpty ? "(none)" : prefixes.joined(separator: ", ")
        return """
        Command approvals
        - allow-all: \(all)
        - allowed prefixes: \(prefixText)
        """
    }

    private func slashHelpText() -> String {
        """
        Slash commands:
        - /help or /commands
        - /clear
        - /compact
        - /permissions
        - /allow-all
        - /disallow-all
        - /allow-prefix <prefix>
        - /unallow-prefix <prefix>
        - /reset-permissions
        """
    }

    func resolveCommandApproval(allow: Bool, pending: AgenticCommandApprovalContext) async {
        showCommandApprovalAlert = false
        pendingApproval = nil
        guard var state = waitingApprovalState,
              pending.token == state.token else { return }
        waitingApprovalState = nil

        if allow {
            let result = await state.executor.execute(call: state.call)
            appendToolSummary(result.userFacingSummary)
            state.history.append([
                "role": "tool",
                "tool_call_id": state.call.id ?? "call_\(UUID().uuidString)",
                "content": result.toolResultPayloadJSON
            ])
            llmHistory = state.history
            await runAgentLoop()
        } else {
            appendMessage(role: .status, content: "Command denied.")
            state.history.append([
                "role": "tool",
                "tool_call_id": state.call.id ?? "call_\(UUID().uuidString)",
                "content": #"{"error":"Command execution denied by user"}"#
            ])
            llmHistory = state.history
            await runAgentLoop()
        }
    }

    func resolveCommandApprovalAlwaysPrefix(pending: AgenticCommandApprovalContext) async {
        if let prefix = pending.commandPrefix, !prefix.isEmpty {
            approvalPreferences.allowedCommandPrefixes.insert(prefix)
            approvalPreferences.save()
            syncApprovalPublishedState()
        }
        await resolveCommandApproval(allow: true, pending: pending)
    }

    func resolveCommandApprovalAlwaysAll(pending: AgenticCommandApprovalContext) async {
        approvalPreferences.allowAllCommands = true
        approvalPreferences.save()
        syncApprovalPublishedState()
        await resolveCommandApproval(allow: true, pending: pending)
    }

    func setApprovalAllowAllCommands(_ enabled: Bool) {
        approvalPreferences.allowAllCommands = enabled
        approvalPreferences.save()
        syncApprovalPublishedState()
    }

    func removeApprovalPrefix(_ prefix: String) {
        approvalPreferences.allowedCommandPrefixes.remove(prefix)
        approvalPreferences.save()
        syncApprovalPublishedState()
    }

    func resetApprovalPreferences() {
        approvalPreferences = AgenticCommandApprovalPreferences(allowAllCommands: false, allowedCommandPrefixes: [])
        approvalPreferences.save()
        syncApprovalPublishedState()
    }

    private func runAgentLoop() async {
        guard !isRunning else { return }
        guard let database else {
            appendMessage(role: .error, content: "Database unavailable.")
            return
        }

        isRunning = true
        defer { isRunning = false }

        let executor = AgenticToolExecutor(database: database)
        var history = llmHistory

        for _ in 0 ..< 8 {
            let placeholderID = UUID()
            appendMessage(id: placeholderID, role: .status, content: "Thinking…")

            do {
                let response = try await AgenticLLMClient.generate(
                    systemPrompt: AgenticLLMClient.systemPrompt(
                        memory: AgenticMemoryStore.read(),
                        servers: AgenticLLMClient.serverInventorySummary()
                    ),
                    history: history
                )

                let cleaned = response.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !response.reasoningText.isEmpty {
                    appendMessage(role: .thinking, content: String(response.reasoningText.prefix(6_000)))
                }

                if response.toolCalls.isEmpty {
                    let finalText = cleaned.isEmpty ? "No response." : cleaned
                    updateMessage(id: placeholderID, content: finalText, role: .assistant)
                    history.append(["role": "assistant", "content": finalText])
                    llmHistory = history
                    sessionStore.save(messages: messages, llmHistory: llmHistory)
                    return
                }

                let toolLabel = response.toolCalls.map(\.tool).joined(separator: ", ")
                updateMessage(id: placeholderID, content: "Using tools: \(toolLabel)", role: .status)

                let assistantToolCalls: [[String: Any]] = response.toolCalls.map { call in
                    [
                        "id": call.id ?? "call_\(UUID().uuidString)",
                        "type": "function",
                        "function": [
                            "name": call.tool,
                            "arguments": AgenticJSON.stringify(call.arguments),
                        ],
                    ]
                }
                var assistantEnvelope: [String: Any] = [
                    "role": "assistant",
                    "tool_calls": assistantToolCalls,
                ]
                if !cleaned.isEmpty {
                    assistantEnvelope["content"] = cleaned
                } else {
                    assistantEnvelope["content"] = ""
                }
                if !response.reasoningDetails.isEmpty {
                    assistantEnvelope["reasoning_details"] = response.reasoningDetails
                }
                history.append(assistantEnvelope)

                for call in response.toolCalls {
                    if call.tool == "finalize_response" {
                        let rawFinal = (call.arguments["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? cleaned
                        let final = rawFinal.isEmpty ? "Done." : rawFinal
                        updateMessage(id: placeholderID, content: final, role: .assistant)
                        history.append(["role": "assistant", "content": final])
                        llmHistory = history
                        sessionStore.save(messages: messages, llmHistory: llmHistory)
                        return
                    }

                    if call.tool == "run_command" {
                        let command = (call.arguments["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if shouldRequireApproval(for: command) {
                            let serverLabel = ((call.arguments["server"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "default server"
                            let token = UUID()
                            waitingApprovalState = AgenticApprovalState(
                                token: token,
                                call: call,
                                history: history,
                                executor: executor
                            )
                            pendingApproval = AgenticCommandApprovalContext(
                                token: token,
                                serverLabel: serverLabel,
                                command: command
                            )
                            showCommandApprovalAlert = true
                            llmHistory = history
                            sessionStore.save(messages: messages, llmHistory: llmHistory)
                            return
                        }
                    }

                    let result = await executor.execute(call: call)
                    appendToolSummary(result.userFacingSummary)
                    history.append([
                        "role": "tool",
                        "tool_call_id": call.id ?? "call_\(UUID().uuidString)",
                        "content": result.toolResultPayloadJSON
                    ])
                }

                llmHistory = history
                sessionStore.save(messages: messages, llmHistory: llmHistory)
            } catch {
                updateMessage(id: placeholderID, content: "Agent error: \(error.localizedDescription)", role: .error)
                sessionStore.save(messages: messages, llmHistory: llmHistory)
                return
            }
        }

        appendMessage(role: .error, content: "Stopped after too many tool steps.")
        sessionStore.save(messages: messages, llmHistory: llmHistory)
    }

    private func appendToolSummary(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmed.count > 3_000 ? String(trimmed.prefix(3_000)) + "\n… [truncated]" : trimmed
        appendMessage(role: .tool, content: summary.isEmpty ? "(empty tool output)" : summary)
    }

    private func appendMessage(id: UUID = UUID(), role: AgenticTimelineMessage.Role, content: String) {
        messages.append(.init(id: id, role: role, content: content, createdAt: .now))
    }

    private func updateMessage(id: UUID, content: String, role: AgenticTimelineMessage.Role) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].role = role
    }

    private func commandRequiresApproval(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if commandUsesShellMetacharacters(trimmed) {
            return true
        }
        let base = trimmed.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let safeCommands: Set<String> = ["ls", "tree", "cat", "pwd", "whoami", "uname", "df", "du", "stat", "head", "tail", "wc", "find"]
        return !safeCommands.contains(base)
    }

    private func commandUsesShellMetacharacters(_ command: String) -> Bool {
        let disallowed = [";", "|", "&", ">", "<", "`", "$(", "\n", "\r"]
        return disallowed.contains { command.contains($0) }
    }

    private func shouldRequireApproval(for command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if approvalPreferences.allowAllCommands {
            return false
        }
        if approvalPreferences.allowedCommandPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return false
        }
        return commandRequiresApproval(trimmed)
    }

    private func syncApprovalPublishedState() {
        approvalAllowAllCommands = approvalPreferences.allowAllCommands
        approvalAllowedPrefixes = approvalPreferences.allowedCommandPrefixes.sorted()
    }
}

private struct AgenticApprovalState {
    let token: UUID
    var call: AgenticToolCall
    var history: [[String: Any]]
    let executor: AgenticToolExecutor
}

struct AgenticCommandApprovalContext: Identifiable {
    let token: UUID
    let serverLabel: String
    let command: String

    var id: UUID { token }

    var commandPrefix: String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
    }
}

struct AgenticTimelineMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable, Hashable {
        case user
        case assistant
        case tool
        case error
        case thinking
        case status

        var label: String {
            switch self {
            case .user: return "You"
            case .assistant: return "Agent"
            case .tool: return "Tool"
            case .error: return "Error"
            case .thinking: return "Thinking"
            case .status: return "Status"
            }
        }
    }

    var id: UUID
    var role: Role
    var content: String
    var createdAt: Date
}

private struct AgenticSessionPayload: Codable {
    var messages: [AgenticTimelineMessage]
}

private struct AgenticSessionState {
    var messages: [AgenticTimelineMessage]
    var llmHistory: [[String: Any]]
}

private final class AgenticSessionStore {
    private let messagesFileName = "agentic_messages_v2.json"
    private let historyFileName = "agentic_history_v2.json"

    func load() -> AgenticSessionState {
        let messages = loadMessages()
        let history = loadHistory()
        return .init(messages: messages, llmHistory: history)
    }

    func save(messages: [AgenticTimelineMessage], llmHistory: [[String: Any]]) {
        saveMessages(messages)
        saveHistory(llmHistory)
    }

    private func loadMessages() -> [AgenticTimelineMessage] {
        guard let url = fileURL(fileName: messagesFileName),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(AgenticSessionPayload.self, from: data) else {
            return []
        }
        return payload.messages
    }

    private func saveMessages(_ messages: [AgenticTimelineMessage]) {
        guard let url = fileURL(fileName: messagesFileName) else { return }
        do {
            let payload = AgenticSessionPayload(messages: messages)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to persist agentic messages: \(error)")
        }
    }

    private func loadHistory() -> [[String: Any]] {
        guard let url = fileURL(fileName: historyFileName),
              let data = try? Data(contentsOf: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    private func saveHistory(_ history: [[String: Any]]) {
        guard let url = fileURL(fileName: historyFileName),
              JSONSerialization.isValidJSONObject(history),
              let data = try? JSONSerialization.data(withJSONObject: history, options: []) else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to persist agentic history: \(error)")
        }
    }

    private func fileURL(fileName: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ContainEye", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName, isDirectory: false)
    }
}

private struct AgenticCommandApprovalPreferences: Codable {
    var allowAllCommands: Bool
    var allowedCommandPrefixes: Set<String>

    static let defaultsKey = "agentic_command_approval_preferences_v1"

    static func load() -> AgenticCommandApprovalPreferences {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AgenticCommandApprovalPreferences.self, from: data) else {
            return AgenticCommandApprovalPreferences(allowAllCommands: false, allowedCommandPrefixes: [])
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
