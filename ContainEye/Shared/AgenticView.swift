//
//  AgenticView.swift
//  ContainEye
//
//  Rebuilt Agentic tab with a simpler, stable architecture.
//

import SwiftUI
import Blackbird

struct AgenticView: View {
    @Environment(\.blackbirdDatabase) private var db
    @Environment(\.agenticBridge) private var bridge
    @StateObject private var model = AgenticViewModel()

    var body: some View {
        VStack(spacing: 0) {
            List(model.messages) { message in
                AgenticMessageRow(message: message)
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)

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
        .alert("Allow Command?", isPresented: $model.showCommandApprovalAlert, presenting: model.pendingApproval) { pending in
            Button("Allow") {
                Task { await model.resolveCommandApproval(allow: true, pending: pending) }
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
                Button {
                    model.startNewSession()
                } label: {
                    Label("New Session", systemImage: "plus.bubble")
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                } else {
                    Text(message.content)
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
}

@MainActor
final class AgenticViewModel: ObservableObject {
    @Published var messages: [AgenticTimelineMessage] = []
    @Published var input = ""
    @Published var isRunning = false
    @Published var pendingComposerContext: String?
    @Published var pendingApproval: AgenticCommandApprovalContext?
    @Published var showCommandApprovalAlert = false

    private var database: Blackbird.Database?
    private var llmHistory: [[String: Any]] = []
    private var waitingApprovalState: AgenticApprovalState?
    private let sessionStore = AgenticSessionStore()

    func configure(database: Blackbird.Database?) async {
        self.database = database
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
                        if commandRequiresApproval(command) {
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
