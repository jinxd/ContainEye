import SwiftUI
import Observation

struct AgenticScreenContext: Hashable {
    var chatTitle: String
    var draftMessage: String
}

@MainActor
@Observable
final class AgenticScreenContextStore {
    static let shared = AgenticScreenContextStore()

    var currentContext: AgenticScreenContext?

    private init() {}

    func set(chatTitle: String, draftMessage: String) {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentContext = nil
            return
        }
        currentContext = AgenticScreenContext(chatTitle: chatTitle, draftMessage: trimmed)
    }

    func clear() {
        currentContext = nil
    }
}

struct AgenticFloatingActionButton: View {
    let action: () -> Void

    var body: some View {
        Button("Agentic", systemImage: "lasso.badge.sparkles", action: action)
            .font(.title2)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .labelStyle(.iconOnly)
            .controlSize(.extraLarge)
            .padding(.trailing, 15)
            .padding(.bottom, -15)
    }
}

struct AgenticDetailFABInset: View {
    @Environment(\.agenticBridge) private var bridge
    @Environment(\.agenticContextStore) private var contextStore

    var body: some View {
        if let context = contextStore.currentContext {
            HStack {
                Spacer()
                AgenticFloatingActionButton {
                    bridge.openAgentic(
                        chatTitle: context.chatTitle,
                        draftMessage: context.draftMessage
                    )
                }
            }
        }
    }
}

#Preview("Floating Button", traits: .sampleData) {
    AgenticFloatingActionButton(action: {})
}

#Preview("Detail Inset", traits: .sampleData) {
    AgenticDetailFABInset()
}
