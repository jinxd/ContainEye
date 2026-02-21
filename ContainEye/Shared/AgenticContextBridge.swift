//
//  AgenticContextBridge.swift
//  ContainEye
//

import Foundation
import Observation

struct AgenticDraftContext: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var chatTitle: String
    var draftMessage: String
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
        pendingContext = AgenticDraftContext(chatTitle: chatTitle, draftMessage: trimmedDraft)
        UserDefaults.standard.set(ContentView.Screen.agentic.rawValue, forKey: "screen")
    }

    func queueContext(chatTitle: String, draftMessage: String) {
        let trimmedDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        pendingContext = AgenticDraftContext(chatTitle: chatTitle, draftMessage: trimmedDraft)
    }

    func consumePendingContext() -> AgenticDraftContext? {
        defer { pendingContext = nil }
        return pendingContext
    }
}
