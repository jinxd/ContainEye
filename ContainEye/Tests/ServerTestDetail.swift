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

    enum ExpandableElement {
        case expectedOutput, actualOutput
    }

    var body: some View {
        if let test {
            Form {
                if isEditing {
                    LabeledContent("Title"){
                        TextField("(e.g. website test)", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                }

                let host = keychain()
                    .getCredential(for: test.credentialKey)?.host ?? ""

                if isEditing {
                    Picker("Host", selection: $credentialKey) {
                        Text("None")
                            .tag("")
                        let allKeys = keychain().allKeys()
                        let credentials = allKeys.compactMap{keychain().getCredential(for: $0)}
                        ForEach(credentials, id: \.key) { credential in
                            Text(credential.label)
                                .tag(credential.key)
                        }
                    }
                } else {
                    LabeledContent("Host", value: host)
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
                Section {
                    AsyncButton(isEditing ? "Fetch Current Output" : "Test Now") {
                        if isEditing {

                            var test = test
                            test.credentialKey = credentialKey
                            test.command = command
                            test.expectedOutput = expectedOutput
                            test.title = title
                            try await test.write(to: db!)
                            expectedOutput = await test.fetchOutput()
                        } else {
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
                    .asyncButtonStyle(.pulse)
                    .listRowBackground(
                        RoundedProgressRectangle(cornerRadius: 10)
                            .stroke(color, lineWidth: 5)
                            .fill(color.tertiary.tertiary)
                    )
                }
                Section {
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
                }
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
            .textSelection(.enabled)
            .animation(.spring, value: expandedElement)
            .animation(.spring, value: isEditing)
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
}

#Preview {
    ServerTestDetail(test: BlackbirdLiveModel<ServerTest>(ServerTest(id: Int.random(in: (.min)...(Int.max)), title: "Title", credentialKey: UUID().uuidString, command: "curl localhost", expectedOutput: ".+", status: .notRun)))
}
