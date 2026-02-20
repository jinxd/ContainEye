//
//  MoreView.swift
//  ContainEye
//
//  Replaced with Agentic workspace.
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
    @State private var store = AgenticChatStore()
    @State private var input = ""
    @State private var isSending = false
    @State private var expandedToolBundles: Set<UUID> = []
    @State private var latestLLMRawResponses: [String] = []
    @State private var failureDebugPayload = ""
    @State private var showFailureDebugAlert = false
    @State private var failureRetryContexts: [UUID: AgenticFailureRetryContext] = [:]
    @State private var editingMessage: AgenticEditContext?
    @State private var editDraft = ""
    @State private var pendingCommandApproval: AgenticPendingCommandApproval?
    @State private var showCommandApprovalAlert = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            chatPickerBar
            Divider()
            detail
        }
        .trackView("agentic")
        .navigationTitle("Agentic")
        .alert("Agent Failure", isPresented: $showFailureDebugAlert) {
            Button("Copy Debug to Clipboard") {
                copyFailurePayloadToClipboard()
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("Copies chat history and raw model responses.")
        }
        .alert("Allow Command?", isPresented: $showCommandApprovalAlert, presenting: pendingCommandApproval) { context in
            Button("Allow") {
                Task { await handlePendingCommandApproval(allow: true, context: context) }
            }
            Button("Deny", role: .destructive) {
                Task { await handlePendingCommandApproval(allow: false, context: context) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { context in
            Text("\(context.serverLabel)\n\(context.command)")
        }
        .sheet(item: $editingMessage) { _ in
            NavigationStack {
                VStack(spacing: 12) {
                    TextEditor(text: $editDraft)
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .navigationTitle("Edit Message")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingMessage = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveEditedMessageAndContinue() }
                        }
                        .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.createChat()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New chat")
            }
        }
        .task {
            await store.configure(database: db)
            isComposerFocused = true
        }
        .onChange(of: store.selectedChatID) {
            isComposerFocused = true
        }
    }

    private var chatPickerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.chats) { chat in
                    Button {
                        store.selectedChatID = chat.id
                    } label: {
                        Text(chat.title).lineLimit(1)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(store.selectedChatID == chat.id ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .overlay(alignment: .trailing) {
            Menu {
                Button {
                    store.createChat()
                } label: {
                    Label("New Chat", systemImage: "plus")
                }

                if let selectedChat, !selectedChat.messages.isEmpty {
                    Button {
                        copyCurrentChat()
                    } label: {
                        Label("Copy Entire Chat", systemImage: "doc.on.doc")
                    }
                }

                if !store.chats.isEmpty {
                    Button(role: .destructive) {
                        if let selected = store.selectedChatID,
                           let index = store.chats.firstIndex(where: { $0.id == selected }) {
                            store.deleteChats(at: IndexSet(integer: index))
                        }
                    } label: {
                        Label("Delete Current Chat", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .padding(6)
            }
#if os(iOS)
            .buttonStyle(.glass)
#endif
            .padding(.trailing, 10)
            .padding(.vertical, 6)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            messagesView
            Divider()
            composer
        }
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let selectedChat {
                        ForEach(renderItems(for: selectedChat.messages)) { item in
                            switch item {
                            case let .message(message):
                                messageRow(message)
                                    .id(message.id)
                            case let .toolBundle(id, tool, call, output, system):
                                toolBundleRow(
                                    id: id,
                                    tool: tool,
                                    call: call,
                                    output: output,
                                    system: system
                                )
                                .id(id)
                            }
                        }
                    } else {
                        ContentUnavailableView("No chat selected", systemImage: "bubble.left.and.bubble.right")
                            .padding(.top, 80)
                    }
                }
                .padding(12)
            }
#if os(iOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .onChange(of: selectedChat?.messages.count) {
                guard let id = selectedChat?.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AgenticMessage) -> some View {
        let alignment: HorizontalAlignment = message.role == .user ? .trailing : .leading
        VStack(alignment: alignment, spacing: 4) {
            Text(label(for: message.role))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(.init(message.content))
                .textSelection(.enabled)
                .font(message.role == .tool ? .system(.footnote, design: .monospaced) : .body)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .background(backgroundColor(for: message.role), in: RoundedRectangle(cornerRadius: 12))

            if message.role == .user, let chatID = store.selectedChatID {
                Button {
                    startEditing(message: message, chatID: chatID)
                } label: {
                    Label("Edit and continue from here", systemImage: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if message.role == .error, let chatID = store.selectedChatID, failureRetryContexts[chatID] != nil {
                Button {
                    Task { await retryFromFailure(chatID: chatID) }
                } label: {
                    Label("Retry from failure point", systemImage: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask the agent to run commands, read/write files, create tests, or manage servers…", text: $input, axis: .vertical)
                .focused($isComposerFocused)
                .lineLimit(1...6)
                .disabled(isSending || selectedChat == nil)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
#if os(iOS)
                .background {
                    if #available(iOS 26, *) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                }
#else
                .textFieldStyle(.roundedBorder)
#endif

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Label("Send", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                }
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || selectedChat == nil)
#if os(iOS)
            .buttonStyle(.glass)
#endif
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .safeAreaPadding(.bottom, 8)
    }

    private var selectedChat: AgenticChat? {
        store.selectedChatID.flatMap { id in
            store.chats.first(where: { $0.id == id })
        }
    }

    private func send() async {
        guard let chat = selectedChat else { return }
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        latestLLMRawResponses = []
        input = ""
        isSending = true
        defer { isSending = false }
        isComposerFocused = false

        await store.appendMessage(AgenticMessage(role: .user, content: prompt), to: chat.id)
        do {
            try await runAgentLoop(chatID: chat.id)
            isComposerFocused = true
        } catch {
            let reason = "Agent error: \(error.localizedDescription)"
            await store.appendMessage(AgenticMessage(role: .error, content: reason), to: chat.id)
            await presentFailureDebugAlert(chatID: chat.id, reason: reason, retryHistory: store.llmHistory(for: chat.id))
            isComposerFocused = true
        }
    }

    private func runAgentLoop(chatID: UUID, seededHistory: [[String: String]]? = nil) async throws {
        guard let db else { return }
        let executor = AgenticToolExecutor(database: db)
        var workingHistory = seededHistory ?? store.llmHistory(for: chatID)

        var loopGuard = 0
        while loopGuard < 8 {
            loopGuard += 1

            let memory = AgenticMemoryStore.read()
            AgenticDebugLogger.log("loop=\(loopGuard) chat=\(chatID.uuidString) history_count=\(workingHistory.count)")
            let streamingMessageID = UUID()
            await store.appendMessage(
                AgenticMessage(id: streamingMessageID, role: .assistant, content: "Thinking..."),
                to: chatID
            )

            let llmResponse = try await AgenticLLMClient.generateStreaming(
                systemPrompt: AgenticLLMClient.systemPrompt(memory: memory),
                history: workingHistory,
                onProgress: { [chatID, streamingMessageID] accumulated in
                    let preview = AgenticStreamingPreviewParser.preview(from: accumulated)
                    guard !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    await store.updateMessage(chatID: chatID, messageID: streamingMessageID, newContent: preview)
                }
            )
            latestLLMRawResponses.append(llmResponse.rawText)
            AgenticDebugLogger.log("http_status=\(llmResponse.statusCode ?? -1)")
            AgenticDebugLogger.log("raw_response=\n\(llmResponse.rawText)")
            let cleaned = LLM.cleanLLMOutputPreservingMarkdown(llmResponse.rawText)
            AgenticDebugLogger.log("cleaned_response=\n\(cleaned)")

            if let toolCall = AgenticToolCall.parse(from: cleaned) {
                AgenticDebugLogger.log("parse=tool_call tool=\(toolCall.tool) args=\(toolCall.arguments)")
                if toolCall.tool == "run_command" {
                    let command = (toolCall.arguments["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if commandRequiresApproval(command) {
                        let serverLabel = ((toolCall.arguments["server"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "default server"
                        await MainActor.run {
                            pendingCommandApproval = AgenticPendingCommandApproval(
                                chatID: chatID,
                                serverLabel: serverLabel,
                                command: command,
                                call: toolCall,
                                history: workingHistory
                            )
                            showCommandApprovalAlert = true
                        }
                        return
                    }
                }
                let callToExecute = toolCall
                await store.updateMessage(
                    chatID: chatID,
                    messageID: streamingMessageID,
                    newContent: "Using tool: \(callToExecute.tool)"
                )
                let result = await executor.execute(call: callToExecute)
                await store.appendMessage(AgenticMessage(role: .tool, content: result.userFacingSummary), to: chatID)
                await store.appendMessage(
                    AgenticMessage(
                        role: .system,
                        content: result.toolResultEnvelope(tool: callToExecute.tool)
                    ),
                    to: chatID
                )
                workingHistory.append(["role": "model", "content": "Using tool: \(callToExecute.tool)"])
                workingHistory.append(["role": "user", "content": result.userFacingSummary])
                workingHistory.append(["role": "user", "content": result.toolResultEnvelope(tool: callToExecute.tool)])
                continue
            }

            if let final = AgenticFinalResponse.parse(from: cleaned) {
                AgenticDebugLogger.log("parse=final")
                await store.updateMessage(chatID: chatID, messageID: streamingMessageID, newContent: final.content)
                workingHistory.append(["role": "model", "content": final.content])
                let normalized = final.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "something went wrong." || normalized == "something went wrong" {
                    await presentFailureDebugAlert(
                        chatID: chatID,
                        reason: "Model returned failure response",
                        retryHistory: workingHistory
                    )
                }
            } else {
                AgenticDebugLogger.log("parse=unstructured_final")
                await store.updateMessage(chatID: chatID, messageID: streamingMessageID, newContent: cleaned)
                workingHistory.append(["role": "model", "content": cleaned])
            }
            return
        }

        let reason = "Stopped after too many tool steps. Please refine your request."
        await store.appendMessage(AgenticMessage(role: .error, content: reason), to: chatID)
        await presentFailureDebugAlert(chatID: chatID, reason: reason, retryHistory: workingHistory)
    }

    private func handlePendingCommandApproval(allow: Bool, context: AgenticPendingCommandApproval) async {
        await MainActor.run {
            showCommandApprovalAlert = false
            pendingCommandApproval = nil
        }
        guard let db else { return }
        let executor = AgenticToolExecutor(database: db)
        var history = context.history

        if allow {
            let approvedCall = context.call
            await store.appendMessage(AgenticMessage(role: .assistant, content: "Using tool: \(approvedCall.tool)"), to: context.chatID)
            let result = await executor.execute(call: approvedCall)
            await store.appendMessage(AgenticMessage(role: .tool, content: result.userFacingSummary), to: context.chatID)
            await store.appendMessage(
                AgenticMessage(role: .system, content: result.toolResultEnvelope(tool: approvedCall.tool)),
                to: context.chatID
            )
            history.append(["role": "model", "content": "Using tool: \(approvedCall.tool)"])
            history.append(["role": "user", "content": result.userFacingSummary])
            history.append(["role": "user", "content": result.toolResultEnvelope(tool: approvedCall.tool)])
        } else {
            let denial = """
            {
              "type":"tool_result",
              "tool":"run_command",
              "payload":{"error":"Command execution denied by user"}
            }
            """
            await store.appendMessage(AgenticMessage(role: .tool, content: "Command denied."), to: context.chatID)
            await store.appendMessage(AgenticMessage(role: .system, content: denial), to: context.chatID)
            history.append(["role": "user", "content": "Command denied by user"])
            history.append(["role": "user", "content": denial])
        }

        do {
            try await runAgentLoop(chatID: context.chatID, seededHistory: history)
        } catch {
            let reason = "Agent error: \(error.localizedDescription)"
            await store.appendMessage(AgenticMessage(role: .error, content: reason), to: context.chatID)
            await presentFailureDebugAlert(chatID: context.chatID, reason: reason, retryHistory: history)
        }
    }

    private func commandRequiresApproval(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if commandUsesShellMetacharacters(trimmed) {
            return true
        }
        let base = trimmed.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let safeCommands: Set<String> = ["ls", "tree", "cat", "pwd", "whoami", "uname", "df", "du", "stat", "head", "tail", "wc"]
        return !safeCommands.contains(base)
    }

    private func commandUsesShellMetacharacters(_ command: String) -> Bool {
        let disallowed = [";", "|", "&", ">", "<", "`", "$(", "\n", "\r"]
        return disallowed.contains { command.contains($0) }
    }

    private func label(for role: AgenticMessage.Role) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return "Agent"
        case .tool: return "Tool"
        case .system: return "System"
        case .error: return "Error"
        }
    }

    private func backgroundColor(for role: AgenticMessage.Role) -> Color {
        switch role {
        case .user: return .blue.opacity(0.18)
        case .assistant: return .secondary.opacity(0.12)
        case .tool: return .green.opacity(0.12)
        case .system: return .orange.opacity(0.12)
        case .error: return .red.opacity(0.14)
        }
    }

    private func copyCurrentChat() {
        guard let chat = selectedChat else { return }
        let transcript = chat.messages
            .map { "[\(label(for: $0.role))]\n\($0.content)" }
            .joined(separator: "\n\n")

#if canImport(UIKit)
        UIPasteboard.general.string = transcript
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
#endif
    }

    private func copyFailurePayloadToClipboard() {
        guard !failureDebugPayload.isEmpty else { return }
#if canImport(UIKit)
        UIPasteboard.general.string = failureDebugPayload
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(failureDebugPayload, forType: .string)
#endif
    }

    private func presentFailureDebugAlert(chatID: UUID, reason: String, retryHistory: [[String: String]]) async {
        let payload = buildFailureDebugPayload(chatID: chatID, reason: reason)
        await MainActor.run {
            failureDebugPayload = payload
            failureRetryContexts[chatID] = AgenticFailureRetryContext(history: retryHistory, reason: reason)
            showFailureDebugAlert = true
        }
    }

    private func buildFailureDebugPayload(chatID: UUID, reason: String) -> String {
        let chatText: String
        if let chat = store.chats.first(where: { $0.id == chatID }) {
            chatText = chat.messages.map { message in
                "[\(label(for: message.role))]\n\(message.content)"
            }.joined(separator: "\n\n")
        } else {
            chatText = "(chat not found)"
        }

        let rawText = latestLLMRawResponses.enumerated().map { index, value in
            "=== Raw Response \(index + 1) ===\n\(value)"
        }.joined(separator: "\n\n")

        return """
        Agentic Failure Debug Report
        Reason: \(reason)
        Log File: \(AgenticDebugLogger.filePathForDisplay)

        === Chat History ===
        \(chatText)

        === Raw Model Responses ===
        \(rawText.isEmpty ? "(none)" : rawText)
        """
    }

    private func retryFromFailure(chatID: UUID) async {
        guard let context = failureRetryContexts[chatID] else { return }
        isSending = true
        defer { isSending = false }
        latestLLMRawResponses = []
        await store.appendMessage(AgenticMessage(role: .assistant, content: "Retrying from failure point…"), to: chatID)
        do {
            try await runAgentLoop(chatID: chatID, seededHistory: context.history)
            failureRetryContexts.removeValue(forKey: chatID)
        } catch {
            let reason = "Retry error: \(error.localizedDescription)"
            await store.appendMessage(AgenticMessage(role: .error, content: reason), to: chatID)
            await presentFailureDebugAlert(chatID: chatID, reason: reason, retryHistory: context.history)
        }
    }

    private func startEditing(message: AgenticMessage, chatID: UUID) {
        editingMessage = AgenticEditContext(chatID: chatID, messageID: message.id)
        editDraft = message.content
    }

    private func saveEditedMessageAndContinue() async {
        guard let context = editingMessage else { return }
        let updated = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.isEmpty else { return }

        editingMessage = nil
        latestLLMRawResponses = []
        failureRetryContexts.removeValue(forKey: context.chatID)
        await store.updateUserMessageAndTruncate(chatID: context.chatID, messageID: context.messageID, newContent: updated)

        isSending = true
        defer { isSending = false }
        do {
            try await runAgentLoop(chatID: context.chatID)
        } catch {
            let reason = "Agent error: \(error.localizedDescription)"
            await store.appendMessage(AgenticMessage(role: .error, content: reason), to: context.chatID)
            await presentFailureDebugAlert(chatID: context.chatID, reason: reason, retryHistory: store.llmHistory(for: context.chatID))
        }
    }

    private func renderItems(for messages: [AgenticMessage]) -> [AgenticRenderItem] {
        var items: [AgenticRenderItem] = []
        var index = 0

        while index < messages.count {
            let current = messages[index]
            if current.role == .assistant,
               current.content.hasPrefix("Using tool:") {
                let tool = current.content.replacingOccurrences(of: "Using tool:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                var output: AgenticMessage?
                var system: AgenticMessage?

                if index + 1 < messages.count, messages[index + 1].role == .tool {
                    output = messages[index + 1]
                }
                if index + 2 < messages.count, messages[index + 2].role == .system {
                    system = messages[index + 2]
                }

                items.append(.toolBundle(id: current.id, tool: tool, call: current, output: output, system: system))
                index += 1
                if output != nil { index += 1 }
                if system != nil { index += 1 }
                continue
            }

            items.append(.message(current))
            index += 1
        }

        return items
    }

    @ViewBuilder
    private func toolBundleRow(id: UUID, tool: String, call: AgenticMessage, output: AgenticMessage?, system: AgenticMessage?) -> some View {
        let isExpanded = expandedToolBundles.contains(id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded {
                    expandedToolBundles.remove(id)
                } else {
                    expandedToolBundles.insert(id)
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tool: \(tool)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Group {
                    Text(call.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let output {
                        Text(output.content)
                            .textSelection(.enabled)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    if let system {
                        Text(system.content)
                            .textSelection(.enabled)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

enum AgenticRenderItem: Identifiable {
    case message(AgenticMessage)
    case toolBundle(id: UUID, tool: String, call: AgenticMessage, output: AgenticMessage?, system: AgenticMessage?)

    var id: UUID {
        switch self {
        case let .message(message):
            return message.id
        case let .toolBundle(id, _, _, _, _):
            return id
        }
    }
}

struct AgenticFailureRetryContext {
    var history: [[String: String]]
    var reason: String
}

struct AgenticPendingCommandApproval: Identifiable {
    var chatID: UUID
    var serverLabel: String
    var command: String
    var call: AgenticToolCall
    var history: [[String: String]]

    var id: UUID { chatID }
}

struct AgenticEditContext: Identifiable {
    var chatID: UUID
    var messageID: UUID

    var id: UUID { messageID }
}

@MainActor
@Observable
final class AgenticChatStore {
    var chats: [AgenticChat] = []
    var selectedChatID: UUID?

    private var configured = false

    func configure(database _: Blackbird.Database?) async {
        guard !configured else { return }
        configured = true
        load()
        if chats.isEmpty {
            createChat()
        } else if selectedChatID == nil {
            selectedChatID = chats.first?.id
        }
    }

    func createChat() {
        let chat = AgenticChat(title: "New Chat", messages: [])
        chats.insert(chat, at: 0)
        selectedChatID = chat.id
        save()
    }

    func deleteChats(at offsets: IndexSet) {
        chats.remove(atOffsets: offsets)
        if chats.isEmpty {
            createChat()
        } else if !chats.contains(where: { $0.id == selectedChatID }) {
            selectedChatID = chats.first?.id
            save()
        } else {
            save()
        }
    }

    func appendMessage(_ message: AgenticMessage, to chatID: UUID) async {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else { return }
        var chat = chats[index]
        chat.messages.append(message)
        if chat.title == "New Chat", message.role == .user {
            chat.title = String(message.content.prefix(36))
        }
        chat.updatedAt = .now
        chats[index] = chat
        chats.sort { $0.updatedAt > $1.updatedAt }
        selectedChatID = chatID
        save()
    }

    func updateUserMessageAndTruncate(chatID: UUID, messageID: UUID, newContent: String) async {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }) else { return }
        var chat = chats[chatIndex]
        guard let messageIndex = chat.messages.firstIndex(where: { $0.id == messageID && $0.role == .user }) else { return }

        chat.messages[messageIndex].content = newContent
        if messageIndex + 1 < chat.messages.count {
            chat.messages.removeSubrange((messageIndex + 1) ..< chat.messages.count)
        }
        if let firstUser = chat.messages.first(where: { $0.role == .user }) {
            chat.title = String(firstUser.content.prefix(36))
        }
        chat.updatedAt = .now
        chats[chatIndex] = chat
        chats.sort { $0.updatedAt > $1.updatedAt }
        selectedChatID = chatID
        save()
    }

    func updateMessage(chatID: UUID, messageID: UUID, newContent: String) async {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }) else { return }
        var chat = chats[chatIndex]
        guard let messageIndex = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }

        chat.messages[messageIndex].content = newContent
        chat.updatedAt = .now
        chats[chatIndex] = chat
        chats.sort { $0.updatedAt > $1.updatedAt }
        selectedChatID = chatID
        save()
    }

    func llmHistory(for chatID: UUID) -> [[String: String]] {
        guard let chat = chats.first(where: { $0.id == chatID }) else { return [] }
        return chat.messages.compactMap { message in
            switch message.role {
            case .user:
                return ["role": "user", "content": message.content]
            case .assistant:
                if message.content.hasPrefix("Using tool:")
                    || message.content.hasPrefix("Approved. Running command")
                    || message.content.hasPrefix("Approval needed before running command")
                    || message.content == "Command cancelled." {
                    return nil
                }
                return ["role": "model", "content": message.content]
            case .tool, .system, .error:
                return ["role": "user", "content": message.content]
            }
        }
    }

    private func load() {
        guard let url = chatsFileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(AgenticChatStorePayload.self, from: data) else {
            return
        }
        chats = payload.chats.sorted(by: { $0.updatedAt > $1.updatedAt })
        selectedChatID = payload.selectedChatID ?? chats.first?.id
    }

    private func save() {
        guard let url = chatsFileURL else { return }
        let payload = AgenticChatStorePayload(chats: chats, selectedChatID: selectedChatID)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to persist agentic chats: \(error)")
        }
    }

    private var chatsFileURL: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ContainEye", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agentic_chats.json", isDirectory: false)
    }
}

struct AgenticChatStorePayload: Codable {
    var chats: [AgenticChat]
    var selectedChatID: UUID?
}

struct AgenticChat: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var messages: [AgenticMessage]
}

struct AgenticMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable {
        case user
        case assistant
        case tool
        case system
        case error
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = .now
}

enum AgenticLLMClient {
    static func systemPrompt(memory: String) -> String {
        #"""
You are ContainEye Agent, an autonomous operations assistant for server management.
You can use tools to inspect servers, inspect indexed file paths, manage test definitions, and edit memory.

Always return either:
1) A tool call JSON object:
{
  "type":"tool",
  "tool":"<tool_name>",
  "arguments": { ... }
}
2) A final response JSON object:
{
  "type":"final",
  "content":"<markdown response for the user>"
}

Allowed tools:
- list_servers {}
- run_command {"server":"<server label>", "command":"<shell command>"}
- read_file {"server":"<server label>", "path":"</path/to/file>"}
- write_file {"server":"<server label>", "path":"</path/to/file>", "content":"<full file content>"}
- list_tests {"server":"optional server label", "status":"optional failed|success|running|notRun", "query":"optional title/path filter"}
- create_test {"server":"<server label>", "title":"...", "command":"...", "expectedOutput":"...", "notes":"optional"}
- add_server {"label":"...", "host":"...", "port":22, "username":"...", "authMethod":"password|privateKey|privateKeyWithPassphrase", "password":"...", "privateKey":"...", "passphrase":"..."}
- update_server {"server":"<server label>", "label":"optional", "host":"optional", "port":22, "username":"optional", "authMethod":"optional", "password":"optional", "privateKey":"optional", "passphrase":"optional"}
- list_documents {"server":"<server label>", "path":"<directory path prefix>", "query":"optional path filter"}
- update_memory {"content":"<memory note>", "mode":"append|replace"}

Rules:
- Start each request by forming a short internal execution plan and then follow it.
- Use tools when facts are needed.
- Prefer solving autonomously with available tools before asking the user anything.
- Only ask the user a question when required information cannot be discovered via tools.
- `run_command` approvals are handled by the app; never ask the user for approval in chat text.
- `list_documents` reads the local indexed remote-path cache for the given server/path, not a live remote listing.
- For any request to modify server metadata (host/label/username/port/auth), use `update_server`.
- Prefer asking clarifying questions in a final response when information is missing.
- You do not need to suggest options unless you are asking a question.
- When you do ask a question, prefer short multiple-choice options so the user can reply with one tap/word (mobile-first UX).
- For those questions, offer 2-5 concrete options when possible, and include a recommended default option.
- Proactively call `update_memory` when you learn durable user preferences, constraints, or stable environment facts that will help future replies.
- Never fabricate command output.
- Keep final responses concise and actionable.

User memory:
\#(memory.isEmpty ? "(none)" : memory)
"""#
    }

    static func generate(systemPrompt: String, history: [[String: String]]) async throws -> AgenticLLMResponse {
        let conversation = [["role": "system", "content": systemPrompt]] + history
        var request = URLRequest(url: URL(string: "https://containeye.hannesnagel.com/text-generation")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: conversation)
        let (data, response) = try await URLSession.shared.data(for: request)
        let rawText = String(data: data, encoding: .utf8) ?? ""
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        return .init(rawText: rawText, statusCode: statusCode)
    }

    static func generateStreaming(
        systemPrompt: String,
        history: [[String: String]],
        onProgress: @escaping @Sendable (String) async -> Void
    ) async throws -> AgenticLLMResponse {
        let conversation = [["role": "system", "content": systemPrompt]] + history
        var request = URLRequest(url: URL(string: "https://containeye.hannesnagel.com/text-generation/stream")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: conversation)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        var accumulated = ""

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = (json["type"] as? String)?.lowercased() else { continue }

            switch type {
            case "delta":
                let delta = json["delta"] as? String ?? ""
                guard !delta.isEmpty else { continue }
                accumulated += delta
                await onProgress(accumulated)
            case "error":
                let reason = json["reason"] as? String ?? "Streaming request failed."
                throw NSError(domain: "AgenticLLMClient", code: statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: reason])
            case "done":
                break
            default:
                continue
            }
        }

        return .init(rawText: accumulated, statusCode: statusCode)
    }
}

struct AgenticLLMResponse {
    var rawText: String
    var statusCode: Int?
}

struct AgenticToolCall {
    var tool: String
    var arguments: [String: Any]

    static func parse(from raw: String) -> AgenticToolCall? {
        let cleaned = LLM.cleanLLMOutput(raw)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type.lowercased() == "tool",
              let tool = json["tool"] as? String else {
            if let legacy = parseLegacyExecute(from: cleaned) { return legacy }
            return nil
        }

        let arguments = (json["arguments"] as? [String: Any]) ?? [:]
        return .init(tool: tool, arguments: arguments)
    }

    private static func parseLegacyExecute(from cleaned: String) -> AgenticToolCall? {
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        if type == "execute", let command = json["content"] as? String {
            return .init(tool: "run_command", arguments: ["command": command])
        }
        return nil
    }
}

struct AgenticFinalResponse {
    var content: String

    static func parse(from raw: String) -> AgenticFinalResponse? {
        let cleaned = LLM.cleanLLMOutput(raw)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String ?? (json["error"] != nil ? "error" : nil) else {
            return nil
        }

        if type == "final" || type == "response" || type == "question" {
            if let content = json["content"] as? String {
                return .init(content: content)
            }
            if let contentObject = json["content"],
               let data = try? JSONSerialization.data(withJSONObject: contentObject, options: [.prettyPrinted]),
               let content = String(data: data, encoding: .utf8) {
                return .init(content: "```json\n\(content)\n```")
            }
        }
        if type == "error", let reason = json["reason"] as? String {
            return .init(content: reason)
        }
        return nil
    }
}

enum AgenticStreamingPreviewParser {
    static func preview(from raw: String) -> String {
        let cleaned = LLM.cleanLLMOutputPreservingMarkdown(raw)
        if let toolCall = AgenticToolCall.parse(from: cleaned) {
            return "Using tool: \(toolCall.tool)"
        }
        if let final = AgenticFinalResponse.parse(from: cleaned) {
            return final.content
        }
        if let partial = extractPartialFinalContent(from: cleaned) {
            return partial
        }
        return cleaned
    }

    private static func extractPartialFinalContent(from text: String) -> String? {
        guard text.range(of: #""type"\s*:\s*"(final|response|question)""#, options: .regularExpression) != nil else {
            return nil
        }
        guard let contentMatch = text.range(of: #""content"\s*:\s*""#, options: .regularExpression) else {
            return nil
        }

        var cursor = contentMatch.upperBound
        var output = ""
        var isEscaping = false

        while cursor < text.endIndex {
            let ch = text[cursor]
            cursor = text.index(after: cursor)

            if isEscaping {
                switch ch {
                case "n": output.append("\n")
                case "t": output.append("\t")
                case "r": output.append("\r")
                case "\"": output.append("\"")
                case "\\": output.append("\\")
                default: output.append(ch)
                }
                isEscaping = false
                continue
            }

            if ch == "\\" {
                isEscaping = true
                continue
            }
            if ch == "\"" {
                break
            }
            output.append(ch)
        }

        return output.isEmpty ? nil : output
    }
}

struct AgenticToolResult {
    var userFacingSummary: String
    var jsonPayload: String

    func toolResultEnvelope(tool: String) -> String {
        """
        {
          "type":"tool_result",
          "tool":"\(tool)",
          "payload": \(jsonPayload)
        }
        """
    }
}

enum AgenticMemoryStore {
    static func read() -> String {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ text: String) {
        guard let url = fileURL else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try? normalized.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func append(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let existing = read()
        if existing.isEmpty {
            write(text)
        } else {
            write(existing + "\n- " + text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ContainEye", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agentic_memory.md", isDirectory: false)
    }
}

enum AgenticDebugLogger {
    static func log(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(line)\n"
        print("AgenticDebug: \(line)")
        guard let url = fileURL else { return }

        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ContainEye", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agentic_debug.log", isDirectory: false)
    }

    static var filePathForDisplay: String {
        fileURL?.path ?? "(unavailable)"
    }
}

struct AgenticToolExecutor {
    let database: Blackbird.Database

    func execute(call: AgenticToolCall) async -> AgenticToolResult {
        do {
            switch call.tool {
            case "list_servers":
                return try await listServers()
            case "run_command":
                return try await runCommand(arguments: call.arguments)
            case "read_file":
                return try await readFile(arguments: call.arguments)
            case "write_file":
                return try await writeFile(arguments: call.arguments)
            case "list_tests":
                return try await listTests(arguments: call.arguments)
            case "create_test":
                return try await createTest(arguments: call.arguments)
            case "add_server":
                return try await addServer(arguments: call.arguments)
            case "update_server":
                return try await updateServer(arguments: call.arguments)
            case "list_documents":
                return try await listDocuments(arguments: call.arguments)
            case "update_memory":
                return updateMemory(arguments: call.arguments)
            default:
                return errorResult("Unknown tool '\(call.tool)'")
            }
        } catch {
            return errorResult(error.localizedDescription)
        }
    }

    private func listServers() async throws -> AgenticToolResult {
        let rows = keychain().allKeys().compactMap { key -> [String: String]? in
            guard let credential = keychain().getCredential(for: key) else { return nil }
            return [
                "label": credential.label,
                "host": credential.host,
                "username": credential.username,
                "authMethod": credential.effectiveAuthMethod.displayName,
            ]
        }
        let payload = serialize(["servers": rows])
        return .init(userFacingSummary: payload, jsonPayload: payload)
    }

    private func runCommand(arguments: [String: Any]) async throws -> AgenticToolResult {
        let command = stringArg("command", from: arguments)
        let credential = try resolveCredential(from: arguments)
        let output = try await SSHClientActor.shared.execute(command, on: credential)
        let payload = serialize([
            "server": credential.label,
            "command": command,
            "output": output,
        ])
        return .init(userFacingSummary: output, jsonPayload: payload)
    }

    private func readFile(arguments: [String: Any]) async throws -> AgenticToolResult {
        let path = stringArg("path", from: arguments)
        let credential = try resolveCredential(from: arguments)
        let command = "cat \(shellSingleQuoted(path))"
        let output = try await SSHClientActor.shared.execute(command, on: credential)
        let payload = serialize([
            "server": credential.label,
            "path": path,
            "content": output,
        ])
        return .init(userFacingSummary: output, jsonPayload: payload)
    }

    private func writeFile(arguments: [String: Any]) async throws -> AgenticToolResult {
        let path = stringArg("path", from: arguments)
        let content = stringArg("content", from: arguments)
        let credential = try resolveCredential(from: arguments)
        let base64 = Data(content.utf8).base64EncodedString()
        let command = """
        mkdir -p "$(dirname \(shellSingleQuoted(path)))"
        printf '%s' \(shellSingleQuoted(base64)) | (base64 --decode 2>/dev/null || base64 -d 2>/dev/null || base64 -D 2>/dev/null) > \(shellSingleQuoted(path))
        """
        _ = try await SSHClientActor.shared.execute(command, on: credential)
        let payload = serialize([
            "server": credential.label,
            "path": path,
            "writtenBytes": content.utf8.count,
        ])
        return .init(userFacingSummary: "Wrote \(content.utf8.count) bytes to \(path) on \(credential.label).", jsonPayload: payload)
    }

    private func listTests(arguments: [String: Any]) async throws -> AgenticToolResult {
        let query = (arguments["query"] as? String)?.lowercased()
        let requestedStatus = (arguments["status"] as? String)?.lowercased()
        let hasServerArgument = arguments["server"] != nil || arguments["credentialKey"] != nil || arguments["credential"] != nil
        let maybeCredential = hasServerArgument ? (try? resolveCredential(from: arguments, required: true)) : nil

        var tests = try await ServerTest.read(
            from: database,
            matching: .all,
            orderBy: .descending(\.$lastRun),
            limit: 300
        )

        if let credential = maybeCredential {
            tests = tests.filter { $0.credentialKey == credential.key }
        }
        if let requestedStatus, !requestedStatus.isEmpty {
            tests = tests.filter { $0.status.rawValue.lowercased() == requestedStatus }
        }
        if let query, !query.isEmpty {
            tests = tests.filter {
                $0.title.lowercased().contains(query)
                    || $0.command.lowercased().contains(query)
                    || ($0.notes?.lowercased().contains(query) ?? false)
            }
        }

        let rows = tests.prefix(150).map { test in
            [
                "id": String(test.id),
                "title": test.title,
                "server": resolveServerLabel(for: test.credentialKey),
                "status": test.status.rawValue,
                "lastRun": test.lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "never",
                "command": test.command,
            ]
        }

        let payload = serialize(["tests": rows])
        return .init(userFacingSummary: payload, jsonPayload: payload)
    }

    private func createTest(arguments: [String: Any]) async throws -> AgenticToolResult {
        let credential = try resolveCredential(from: arguments)
        let title = stringArg("title", from: arguments)
        let command = stringArg("command", from: arguments)
        let expectedOutput = stringArg("expectedOutput", from: arguments)
        let notes = (arguments["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var test = ServerTest(
            id: .random(in: .min ... .max),
            title: title,
            notes: notes?.isEmpty == true ? nil : notes,
            credentialKey: credential.key,
            command: command,
            expectedOutput: expectedOutput,
            status: .notRun
        )
        test = await test.test()
        try await test.write(to: database)

        let payload = serialize([
            "id": test.id,
            "title": test.title,
            "server": credential.label,
            "command": test.command,
            "expectedOutput": test.expectedOutput,
        ])
        return .init(userFacingSummary: "Created test '\(test.title)' for \(credential.label).", jsonPayload: payload)
    }

    private func addServer(arguments: [String: Any]) async throws -> AgenticToolResult {
        let label = stringArg("label", from: arguments)
        let host = stringArg("host", from: arguments)
        let username = stringArg("username", from: arguments)
        let portValue = arguments["port"] as? Int ?? Int(arguments["port"] as? String ?? "22") ?? 22
        let authMethodRaw = (arguments["authMethod"] as? String ?? "password").lowercased()

        let authMethod: AuthenticationMethod
        switch authMethodRaw {
        case "privatekey":
            authMethod = .privateKey
        case "privatekeywithpassphrase":
            authMethod = .privateKeyWithPassphrase
        default:
            authMethod = .password
        }

        let credential = Credential(
            key: UUID().uuidString,
            label: label,
            host: host,
            port: Int32(portValue),
            username: username,
            password: (arguments["password"] as? String) ?? "",
            authMethod: authMethod,
            privateKey: arguments["privateKey"] as? String,
            passphrase: arguments["passphrase"] as? String
        )

        let data = try JSONEncoder().encode(credential)
        try keychain().set(data, key: credential.key)
        try await Server(credentialKey: credential.key).write(to: database)

        let payload = serialize([
            "label": credential.label,
            "host": credential.host,
        ])
        return .init(userFacingSummary: "Added server '\(credential.label)' (\(credential.host)).", jsonPayload: payload)
    }

    private func updateServer(arguments: [String: Any]) async throws -> AgenticToolResult {
        var credential = try resolveCredential(from: arguments)

        if let label = arguments["label"] as? String { credential.label = label }
        if let host = arguments["host"] as? String { credential.host = host }
        if let username = arguments["username"] as? String { credential.username = username }
        if let portInt = arguments["port"] as? Int { credential.port = Int32(portInt) }
        if let portString = arguments["port"] as? String, let portInt = Int(portString) { credential.port = Int32(portInt) }
        if let password = arguments["password"] as? String { credential.password = password }
        if let privateKey = arguments["privateKey"] as? String { credential.privateKey = privateKey }
        if let passphrase = arguments["passphrase"] as? String { credential.passphrase = passphrase }
        if let authMethod = arguments["authMethod"] as? String {
            switch authMethod.lowercased() {
            case "privatekey":
                credential.authMethod = .privateKey
            case "privatekeywithpassphrase":
                credential.authMethod = .privateKeyWithPassphrase
            default:
                credential.authMethod = .password
            }
        }

        let data = try JSONEncoder().encode(credential)
        try keychain().set(data, key: credential.key)
        if let server = try? await Server.read(from: database, id: credential.key) {
            try await server.write(to: database)
        } else {
            try await Server(credentialKey: credential.key).write(to: database)
        }

        let payload = serialize([
            "label": credential.label,
            "host": credential.host,
            "username": credential.username,
            "port": Int(credential.port),
        ])
        return .init(userFacingSummary: "Updated server '\(credential.label)'.", jsonPayload: payload)
    }

    private func listDocuments(arguments: [String: Any]) async throws -> AgenticToolResult {
        let hasServerArgument = arguments["server"] != nil || arguments["credentialKey"] != nil || arguments["credential"] != nil
        guard hasServerArgument else {
            return errorResult("list_documents requires a server label")
        }
        let pathPrefixRaw = stringArg("path", from: arguments)
        guard !pathPrefixRaw.isEmpty else {
            return errorResult("list_documents requires a path")
        }
        let normalizedPathPrefix = pathPrefixRaw.hasSuffix("/") ? pathPrefixRaw : "\(pathPrefixRaw)/"
        let query = (arguments["query"] as? String)?.lowercased()
        let credential = try resolveCredential(from: arguments, required: true)
        let nodes = try await RemotePathNode.read(from: database, matching: \.$credentialKey == credential.key, orderBy: .descending(\.$lastSeen), limit: 250)

        let filtered = nodes.filter { node in
            let inPathScope = node.path == pathPrefixRaw || node.path.hasPrefix(normalizedPathPrefix)
            guard inPathScope else { return false }
            guard let query else { return true }
            return node.path.lowercased().contains(query)
        }

        let rows = filtered.prefix(120).map { node in
            [
                "server": resolveServerLabel(for: node.credentialKey),
                "path": node.path,
                "isDirectory": node.isDirectory ? "true" : "false",
                "lastSeen": node.lastSeen.formatted(date: .abbreviated, time: .shortened),
            ]
        }

        let payload = serialize([
            "server": credential.label,
            "path": pathPrefixRaw,
            "documents": rows,
        ])
        let summary: String
        if rows.isEmpty {
            summary = "No indexed documents found for \(credential.label) yet. This tool only reads ContainEye's local path index."
        } else {
            summary = payload
        }
        return .init(userFacingSummary: summary, jsonPayload: payload)
    }

    private func updateMemory(arguments: [String: Any]) -> AgenticToolResult {
        let content = stringArg("content", from: arguments)
        let mode = (arguments["mode"] as? String)?.lowercased() ?? "append"
        guard !content.isEmpty else {
            return errorResult("update_memory requires non-empty content")
        }

        if mode == "replace" {
            AgenticMemoryStore.write(content)
        } else {
            AgenticMemoryStore.append(content)
        }
        let snapshot = AgenticMemoryStore.read()
        let payload = serialize(["memory": snapshot])
        return .init(userFacingSummary: "Updated memory.", jsonPayload: payload)
    }

    private func resolveCredential(from arguments: [String: Any], required: Bool = true) throws -> Credential {
        if let raw = arguments["server"] as? String ?? arguments["credentialKey"] as? String ?? arguments["credential"] as? String {
            if let credential = keychain().getCredential(for: raw) {
                return credential
            }
            if let credential = keychain().allKeys().compactMap({ keychain().getCredential(for: $0) }).first(where: { $0.label.caseInsensitiveCompare(raw) == .orderedSame }) {
                return credential
            }
            throw NSError(domain: "Agentic", code: 404, userInfo: [NSLocalizedDescriptionKey: "Server '\(raw)' not found"])
        }

        if let first = keychain().allKeys().compactMap({ keychain().getCredential(for: $0) }).first {
            return first
        }

        if required {
            throw NSError(domain: "Agentic", code: 404, userInfo: [NSLocalizedDescriptionKey: "No servers configured"])
        }
        throw NSError(domain: "Agentic", code: 405, userInfo: [NSLocalizedDescriptionKey: "No optional server available"])
    }

    private func stringArg(_ key: String, from arguments: [String: Any]) -> String {
        (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolveServerLabel(for credentialKey: String) -> String {
        keychain().getCredential(for: credentialKey)?.label ?? credentialKey
    }

    private func shellSingleQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func serialize(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func errorResult(_ message: String) -> AgenticToolResult {
        let payload = serialize(["error": message])
        return .init(userFacingSummary: "Tool error: \(message)", jsonPayload: payload)
    }
}

#Preview {
    NavigationStack {
        AgenticView()
    }
}
