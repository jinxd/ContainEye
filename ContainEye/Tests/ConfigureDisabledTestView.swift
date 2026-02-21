//
//  ConfigureDisabledTestView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/8/25.
//


import SwiftUI
import Blackbird
import ButtonKit

struct ConfigureDisabledTestView: View {
    @BlackbirdLiveModel var test: ServerTest?
    @Environment(\.blackbirdDatabase) var db
    @Environment(\.agenticBridge) private var bridge
    @State private var aiPrompt = ""
    @State private var isShowingServerPicker = false
    @State private var credentialKey = "-"

    var body: some View {
        if let test {
            VStack {
                ContentUnavailableView("This test is currently disabled", systemImage: "testtube.2", description: Text("Let's configure it for you needs."))

                Group {
                    Text(test.command).monospaced()
                    Text(test.expectedOutput).monospaced()
                    if let notes = test.notes {
                        Text(notes)
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(.accent.quinary, in: .rect(cornerRadius: 25, style: .continuous))
                .clipShape(.rect(cornerRadius: 25, style: .continuous))
                .padding(.horizontal, 30)

                Spacer(minLength: 100)

                HStack {
                    TextField("Describe how to change the test...", text: $aiPrompt, axis: .vertical)
                    AsyncButton {
                        let requestedChanges = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !requestedChanges.isEmpty else { return }
                        let serverLabel = keychain().getCredential(for: test.credentialKey)?.label ?? test.credentialKey
                        let draft = """
                        Edit this existing test using tool calls.

                        Use `update_test` for this record:
                        - id: \(test.id)
                        - server: \(serverLabel)
                        - title: \(test.title)
                        - command: \(test.command)
                        - expectedOutput: \(test.expectedOutput)
                        - notes: \(test.notes ?? "(none)")

                        Requested changes:
                        \(requestedChanges)
                        """
                        bridge.openAgentic(
                            chatTitle: "Edit Test #\(test.id)",
                            draftMessage: draft
                        )
                        aiPrompt.removeAll()
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

                Button("Save") {isShowingServerPicker = true}
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.top)
            }
            .overlay {
                if isShowingServerPicker {
                    VStack {
                        Spacer()
                        Text("Choose where to execute the test").monospaced()

                        Picker("Select Server", selection: $credentialKey) {
                            Text("Select a server")
                                .tag("-")
                            let keychain = keychain()
                            let allCredentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
                            ForEach(allCredentials, id: \.key) {credential in
                                Text(credential.label)
                                    .tag(credential.key)
                            }
                        }
                        .pickerStyle(.inline)
                        Spacer()
                        AsyncButton("Save") {
                            var test = test
                            test.credentialKey = credentialKey
                            try await test.write(to: db!)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(credentialKey == "-")
                        Button(role: .cancel) {
                            isShowingServerPicker = false
                        }
                        .buttonStyle(.bordered)
                    }
                        .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(test.title)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }
}

#Preview {
    NavigationStack {
        ConfigureDisabledTestView(test: ServerTest(id: 12638712454, title: "Check docker containers", notes: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.", credentialKey: "-", command: "docker ps | wsl -i", expectedOutput: "8", status: .notRun).liveModel)
    }
}
