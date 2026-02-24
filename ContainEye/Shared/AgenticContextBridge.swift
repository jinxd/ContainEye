//
//  AgenticContextBridge.swift
//  ContainEye
//

import Foundation
import Observation

enum AgenticContextDeliveryMode: String, Codable, Hashable {
    case composerDraft
    case userMessage
}

struct AgenticDraftContext: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var chatTitle: String
    var draftMessage: String
    var deliveryMode: AgenticContextDeliveryMode = .composerDraft
    var autoRunAgent: Bool = false
}

@MainActor
@Observable
final class AgenticContextBridge {
    static let shared = AgenticContextBridge()

    var pendingContext: AgenticDraftContext?

    private init() {}

    func openAgentic(chatTitle: String, draftMessage: String) {
        let trimmedDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        pendingContext = AgenticDraftContext(
            chatTitle: chatTitle,
            draftMessage: trimmedDraft,
            deliveryMode: .composerDraft,
            autoRunAgent: false
        )
        UserDefaults.standard.set(ContentView.Screen.agentic.rawValue, forKey: "screen")
    }

    func openAgenticAsUserMessage(chatTitle: String, message: String, autoRunAgent: Bool = true) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        pendingContext = AgenticDraftContext(
            chatTitle: chatTitle,
            draftMessage: trimmedMessage,
            deliveryMode: .userMessage,
            autoRunAgent: autoRunAgent
        )
        UserDefaults.standard.set(ContentView.Screen.agentic.rawValue, forKey: "screen")
    }

    func queueContext(chatTitle: String, draftMessage: String) {
        let trimmedDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        pendingContext = AgenticDraftContext(
            chatTitle: chatTitle,
            draftMessage: trimmedDraft,
            deliveryMode: .composerDraft,
            autoRunAgent: false
        )
    }

    func consumePendingContext() -> AgenticDraftContext? {
        defer { pendingContext = nil }
        return pendingContext
    }
}
