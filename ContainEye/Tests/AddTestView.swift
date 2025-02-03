//
//  AddTestView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/25/25.
//

import SwiftUI
import ButtonKit
import KeychainAccess
import Citadel
import UserNotifications

struct AddTestView: View {
    @Environment(\.dismiss) var dismiss

    @FocusState private var focus : Focus?

    enum Focus {
        case title, command, expectedOutput
    }

    @State private var serverTest = ServerTest(id: .random(in: Int.min...Int.max), title: "", credentialKey: UUID().uuidString, command: "", expectedOutput: "", status: .notRun)

    @Environment(\.blackbirdDatabase) var db

    var body: some View {
        VStack{
            Form {
                Section {
                    TextField("Title (example.com)", text: $serverTest.title)
#if !os(macOS)
                        .keyboardType(.asciiCapable)
#endif
                        .focused($focus, equals: .title)
                        .onSubmit {
                            focus = nil
                        }
                        .submitLabel(.next)
                }
                Section{
                    Picker("Host", selection: $serverTest.credentialKey) {
                        Text("None")
                            .tag("")
                        let allKeys = keychain().allKeys()
                        let credentials = allKeys.compactMap{keychain().getCredential(for: $0)}
                        ForEach(credentials, id: \.key) { credential in
                            Text(credential.label)
                                .tag(credential.key)
                        }
                    }
                }
                Section {
                    TextField("Command (e.g. curl localhost)", text: $serverTest.command)
#if !os(macOS)
                        .keyboardType(.asciiCapable)
#endif
                        .focused($focus, equals: .command)
                        .onSubmit {
                            focus = .expectedOutput
                        }
                        .submitLabel(.next)
                }

                Section {
                    TextEditor(text: $serverTest.expectedOutput)
                        .focused($focus, equals: .expectedOutput)
                        .onSubmit {
                            Task{try await addTest()}
                        }
                        .submitLabel(.done)

                    AsyncButton("Fetch current output") {
                        serverTest.expectedOutput = await serverTest.fetchOutput()
                    }
                } header: {
                    Text("Expected output")
                } footer: {
                    Text("You can use a regular expression to match the output. Both will be tried. This is \((try? Regex(serverTest.expectedOutput)) == nil ? "an invalid regex" : "a valid regex")")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                AsyncButton {
                    do {
#if !os(macOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                        try await addTest()
                    } catch {
#if !os(macOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
                        throw error
                    }
                } label: {
                    Text("Add")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .asyncButtonStyle(.overlay(style: .bar))
                .padding(.horizontal)
                .padding(.bottom)
            }
            .onAppear{
                focus = .title
            }
        }
        .navigationTitle("Test a server")
    }
    enum AddServerError: Error {
        case existsAlready
    }

    func addTest() async throws {
        try await serverTest.write(to: db!)
        dismiss()
        let _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
}

#Preview {
    AddServerView()
}
