//
//  ServerTestDetail.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/23/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import KeychainAccess

struct ServerTestDetail: View {
    @BlackbirdLiveModel var test: ServerTest?
    @Environment(\.blackbirdDatabase) private var db
    @State private var expandedElement = ExpandableElement?.none
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var credentialKey = ""
    @State private var command = ""
    @State private var expectedOutput = ""
    @State private var title = ""
    @State private var notes = ""

    enum ExpandableElement {
        case expectedOutput, actualOutput, notes
    }

    var prompt: String {
        if let test {
            "\(test.title)\n\(test.notes?.appending("\n") ?? "")The current command is: \(command)\n Current regex that should validate the output is: \(expectedOutput)\n\n"
        } else {""}
    }

    @State private var changeDescription = ""

    var body: some View {
        if let test {
            Form {
                if isEditing {
                    LabeledContent("Title"){
                        TextField("(e.g. website test)", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if isEditing {
                    Picker("Host", selection: $credentialKey) {
                        Text("Do not execute")
                            .tag("-")
                        Text("Local (only urls)")
                            .tag("")
                        let allKeys = keychain().allKeys()
                        let credentials = allKeys.compactMap{keychain().getCredential(for: $0)}
                        ForEach(credentials, id: \.key) { credential in
                            Text(credential.label)
                                .tag(credential.key)
                        }
                    }
                } else {
                    let host = keychain()
                        .getCredential(for: test.credentialKey)?.label
                    let hostText = host ?? (test.credentialKey.isEmpty ? "Local (urls only)" : "Do not run")

                    LabeledContent("Host", value: hostText)
                }

                Section("Notes") {
                    if isEditing {
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                    } else {
                        Text((test.notes?.isEmpty ?? true) ? "No notes" : test.notes ?? "No notes")
                            .italic(test.notes?.isEmpty ?? true)
                            .lineLimit(expandedElement == .notes ? nil : 2)
                            .onTapGesture {
                                expandedElement = expandedElement == .notes ? .none : .notes
                            }
                    }
                }

                if isEditing {
                    Section("Adapt this test"){
                        TextField("Describe the changes", text: $changeDescription)
                        AsyncButton("Adapt") {
                            try await adapt(changeDescription)
                        }
                    }
                }

                if isEditing {
                    Section("Command") {
                        TextEditor(text: $command)
#if !os(macOS)
                            .keyboardType(.asciiCapable)
#endif
                            .frame(minHeight: 100)

                    }
                } else {
                    LabeledContent("Command", value: test.command)
                }

                LabeledContent("Last run", value: test.lastRun?.formatted(.dateTime) ?? "Never")


                Section {
                    if isEditing {
                        TextEditor(text: $expectedOutput)
                            .frame(minHeight: 100)
                    } else {
                        Text(test.expectedOutput)
                            .lineLimit(expandedElement == .expectedOutput ? nil : 2)
                            .onTapGesture {
                                expandedElement = expandedElement == .expectedOutput ? .none : .expectedOutput
                            }
                    }
                } header: {
                    Text("Expected output")
                } footer: {
                    if isEditing {
                        Text("You can use a regular expression to match the output. Both will be tried. This is \((try? Regex(expectedOutput)) == nil ? "an invalid regex" : "a valid regex")")
                    }
                }

                Section(isEditing ? "Last output before editing" : "Actual output") {
                    Text(test.output ?? "No output")
                        .italic(test.output == nil)
                        .lineLimit(expandedElement == .actualOutput ? nil : 2)
                        .onTapGesture {
                            expandedElement = expandedElement == .actualOutput ? .none : .actualOutput
                        }
                }


                let color = switch test.status {
                case .failed:
                    Color.red
                case .success:
                    Color.green
                default:
                    Color.gray
                }

                if test.status == .failed {
                    Section{
                        AsyncButton("Fix command") {
                            if isEditing {
                                try await setTestProperties()
                            }
                            let output = await test.fetchOutput()
                            try await adapt("Fix the command to work properly. The current output is \(output)")
                        }
                        AsyncButton("Fix expected output") {
                            if isEditing {
                                try await setTestProperties()
                            }
                            let output = await test.fetchOutput()
                            try await adapt("Fix the regex to match a succeeding output properly, but still doesn't match failing tests. The current output is \(output).")
                        }
                    } header: {
                        Text("Fix the test")
                    } footer: {
                    }
                }
                Section {
                    AsyncButton(isEditing ? "Fetch Current Output" : "Test Now") {
                        if isEditing {

                            var test = test
                            test.credentialKey = credentialKey
                            test.command = command
                            test.expectedOutput = expectedOutput
                            test.title = title
                            test.notes = notes
                            expectedOutput = await test.fetchOutput()
                        } else {
                            guard test.credentialKey != "-" else {return}
                            self.test?.status = .running
                            let test = await test.test()
#if !os(macOS)
                            if test.status == .failed {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
#endif
                            try await test.write(to: db!)
                        }
                    }
                    .listRowBackground(
                        RoundedProgressRectangle(cornerRadius: 10)
                            .stroke(color, lineWidth: 5)
                            .fill(color.tertiary.tertiary)
                    )
                }
                Section {
                    AsyncButton(isEditing ? "Done" : "Edit", systemImage: "pencil") {
                        if isEditing {
                            try await setTestProperties()
                            isEditing = false
                        } else {
                            try await setLocalProperties()
                            isEditing = true
                        }
                    }
                }
                if test.credentialKey != "-" {
                    Section{
                        AsyncButton(role: .destructive) {
                            try await test.delete(from: db!)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .animation(.spring, value: expandedElement)
            .animation(.spring, value: isEditing)
            .animation(.spring, value: test.status)
            .navigationTitle(test.title)
            .toolbarTitleMenu {
                AsyncButton(isEditing ? "Done" : "Edit", systemImage: "pencil") {
                    if isEditing {
                        var test = test
                        test.credentialKey = credentialKey
                        test.command = command
                        test.expectedOutput = expectedOutput
                        test.title = title
                        try await test.write(to: db!)
                        isEditing = false
                    } else {
                        credentialKey = test.credentialKey
                        command = test.command
                        expectedOutput = test.expectedOutput
                        title = test.title
                        isEditing = true
                    }
                }
                Menu{
                    AsyncButton(role: .destructive) {
                        try await test.delete(from: db!)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } label : {
                    Label("Delete", systemImage: "trash")
                }
            }
            .userActivity("test.selected", element: test) { test, userActivity in
                if #available(iOS 18.2, macOS 15.2, *){
                    userActivity.appEntityIdentifier = .init(for: test.entity)
                }
                userActivity.userInfo?["id"] = test.id
                userActivity.isEligibleForHandoff = true
                userActivity.isEligibleForSearch = true
#if !os(macOS)
                userActivity.isEligibleForPrediction = true
#endif
                userActivity.targetContentIdentifier = "\(test.id)"
                userActivity.title = test.title
                userActivity.becomeCurrent()
            }
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "questionmark.circle")
        }
    }
    func setTestProperties() async throws {
        guard var test else {return}
        test.credentialKey = credentialKey
        test.command = command
        test.expectedOutput = expectedOutput
        test.title = title
        test.notes = notes
        try await test.write(to: db!)
        isEditing = false
    }
    func setLocalProperties() async throws {
        guard let test else {return}
        credentialKey = test.credentialKey
        command = test.command
        expectedOutput = test.expectedOutput
        title = test.title
        notes = test.notes ?? ""
        isEditing = true
    }

    func adapt(_ changeDescription: String) async throws {
        if !isEditing { try await setLocalProperties() }
        isEditing = true

        let dirtyOutput = await LLM.generate(
            prompt: "\(prompt)Do the following:\n\(changeDescription)",
            systemPrompt: LLM.addTestSystemPrompt
        )
        let llmOutput = LLM.cleanLLMOutput(dirtyOutput)

        struct LLMOutput: Decodable {
            let title: String
            let command: String
            let expectedOutput: String
        }

        let output = try JSONDecoder().decode(
            LLMOutput.self,
            from: Data(
                llmOutput.utf8
            )
        )
        title = output.title
        command = output.command
        expectedOutput = output.expectedOutput
    }
}

#Preview {
    ServerTestDetail(test: BlackbirdLiveModel<ServerTest>(ServerTest(id: Int.random(in: (.min)...(Int.max)), title: "Title", credentialKey: UUID().uuidString, command: "curl localhost", expectedOutput: ".+", status: .notRun)))
}
