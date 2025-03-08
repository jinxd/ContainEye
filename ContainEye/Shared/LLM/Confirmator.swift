//
//  Confirmator.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/6/25.
//

import SwiftUI
import ButtonKit

extension View {
    public func confirmator() -> some View {
        overlay(Confirmator())
    }
}

@MainActor @Observable
final class ConfirmatorManager {
    static let shared = ConfirmatorManager()

    var continuation: CheckedContinuation<String, any Error>?
    var question: String?
    var command: String?

    func ask(_ question: String) async throws -> String {
        self.question = question
        return try await withCheckedThrowingContinuation { con in
            self.continuation = con
        }
    }
    func execute(_ command: String) async throws -> String {
        self.command = command
        return try await withCheckedThrowingContinuation { con in
            self.continuation = con
        }
    }
}
enum ConfirmatorError: Error {
    case cancelled
}

import Blackbird

private struct Confirmator: View {
    @State private var confirmator = ConfirmatorManager.shared
    @State private var answer = ""
    @State private var server: Server?
    @BlackbirdLiveModels({
        try await Server.read(
            from: $0,
            matching: .all
        )
    }) var servers
    @Environment(\.blackbirdDatabase) var db
    @FocusState private var focused: Bool

    var body: some View {
        if confirmator.question != nil || confirmator.command != nil {
            VStack {
                if let question = confirmator.question {
                    Text("I have a question for you")
                        .font(.headline)
                    Spacer()
                    Text(.init(question))
                        .padding()
                        .background(.accent.opacity(0.1), in: .rect(cornerRadius: 15))
                    Spacer()
                    HStack {
                        TextField("Tell me please...", text: $answer, axis: .vertical)
                            .focused($focused)
                        Button {
                            confirmator.continuation?.resume(returning: answer)
                            confirmator.question = nil
                            answer.removeAll()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Submit")

                    }
                    .padding(10)
                    .background(.accent.quinary, in: .capsule)
                    .padding(.horizontal, 30)

                    Button("Cancel") {
                        confirmator.continuation?.resume(throwing: ConfirmatorError.cancelled)
                        confirmator.question = nil
                        answer.removeAll()
                    }
                    .buttonStyle(.bordered)
                } else if let command = confirmator.command {
                    Text("I would like to execute the following command:")
                        .font(.headline)
                    Spacer()

                    Text(.init("```\(command)```"))
                        .padding()
                        .background(.accent.opacity(0.1), in: .rect(cornerRadius: 15))

                    Spacer()

                    Text("Choose where to execute the command:").monospaced()
                    Picker("Host", selection: $server) {
                        Text("Choose a server")
                            .tag(Server?.none)
                        ForEach(servers.results) { server in
                            Text(server.credential?.label ?? "Unknown")
                                .tag(server)
                        }
                    }
                    .pickerStyle(.inline)
                    .task{
                        while server == nil,
                              !Task.isCancelled{
                            server = servers.results.first
                            try? await Task.sleep(for: .seconds(1))
                        }
                    }

                    AsyncButton("Tap to Execute") {
                        guard let server = server else {return}
                        let output = (try? await server.execute(command)) ?? "sth went wrong"
                        confirmator.continuation?.resume(returning: output)
                        confirmator.command = nil
                        answer.removeAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(server == nil)
                    Button("Cancel") {
                        confirmator.continuation?.resume(throwing: ConfirmatorError.cancelled)
                        confirmator.command = nil
                        answer.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .buttonBorderShape(.roundedRectangle(radius: 15))
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .onAppear{
                focused = false
                focused = true
            }
        }
    }
}

#Preview {
    let _ = ConfirmatorManager.shared.command = "print(\"Hello, World!\")"
    Confirmator()
}
#Preview {
    let _ = ConfirmatorManager.shared.question = "Do you want help with your docker containers?"
    Confirmator()
}
