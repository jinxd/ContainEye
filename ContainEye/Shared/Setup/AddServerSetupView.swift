//
//  AddServerSetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//


import SwiftUI
import ButtonKit
import Blackbird
import UserNotifications

struct AddServerSetupView: View {
    @Binding var screen: Int?
    @State private var test = ServerTest(id: .random(in: (.min)...(.max)), title: "", credentialKey: "", command: "", expectedOutput: "", status: .notRun)
    @FocusState private var field : Field?
    @Environment(\.blackbirdDatabase) private var db

    @State private var testDescription = ""

    enum Field: CaseIterable {
        case askAI
    }

    var body: some View {
        VStack {
            Spacer()
            Text("Alright, let's add a Test")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Spacer()

            let allKeys = keychain().allKeys()
            let credentials = allKeys.compactMap{keychain().getCredential(for: $0)}
            Picker("Host", selection: $test.credentialKey) {
                ForEach(credentials, id: \.key) { credential in
                    Text(credential.label)
                        .tag(credential.key)
                }
            }
            .pickerStyle(.inline)
            .task{
                while test.credentialKey.isEmpty || test.credentialKey == "-",
                      !Task.isCancelled{
                    test.credentialKey = credentials.first?.key ?? "-"
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            Spacer()
            if !test.command.isEmpty {
                VStack {
                    Text(test.command)
                    Divider()
                    Text(test.expectedOutput)
                }
                .padding(10)
                .background(.accent.quinary, in: .capsule)
                .padding(.horizontal, 30)

                if test.status == .failed {
                    VStack{
                        HStack {
                            AsyncButton{
                                test = try await generateTest(from: test, description: testDescription.appending("\n\nYou need to fix this test. It previously failed, because the command: \n\(test.command) \n produced the output: \n\(test.output ?? "no output")\ninstead of:\n\(test.expectedOutput)\nIf it just fails, because the conditions weren't met please explain that it the expectedOutput field using regex comments.\n\n\(test.notes ?? "")"))
                            } label: {
                                VStack {
                                    Image(systemName: "wand.and.sparkles")
                                    Text("Fix").font(.caption)
                                }
                            }
                            .accessibilityLabel("Fix the test")
                            Text("This test failed!")
                                .padding(10)
                                .background(.red.opacity(0.2))
                            AsyncButton{
                                test = await test.test()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Retry")
                        }
                        Divider()
                        ScrollView(.horizontal){
                            Text(test.output ?? "No output")
                                .font(.caption)
                                .lineLimit(2...3)
                                .padding(2)
                        }
                    }
                    .padding(10)
                    .background(.accent.quinary, in: .capsule)
                    .clipShape(.capsule)
                    .padding(.horizontal, 30)
                } else {

                    AsyncButton("Add the test") {
                        try? await Logger.telemetry(
                            "added test",
                            with: [
                                "servers":keychain().allKeys().count,
                                "tests":ServerTest.count(in: db!, matching: \.$credentialKey != "-")
                            ]
                        )
                        try await test.write(to: db!)
                        test = ServerTest(id: .random(in: (.min)...(.max)), title: "", credentialKey: "", command: "", expectedOutput: "", status: .notRun)
                        screen = 3
                        let _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    }
                    .buttonStyle(.bordered)

                }
            }
            Spacer()
            HStack {
                TextField("Describe what to test", text: $testDescription, axis: .vertical)
                    .focused($field, equals: .askAI)
                AsyncButton {
                    test = try await generateTest(from: test, description: testDescription)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .accessibilityLabel("Generate test from description")

            }
            .padding(10)
            .background(.accent.quinary, in: .capsule)
            .padding(.horizontal, 30)
            Spacer()

            NavigationLink("Learn about testing", value: Help.tests)
        }
    }
    func generateTest(from test: ServerTest, description: String) async throws -> ServerTest {
        var test = test
        let dirtyLlmOutput = await LLM.generate(
            prompt: description,
            systemPrompt: LLM.addTestSystemPrompt
        )
        let llmOutput = LLM.cleanLLMOutput(dirtyLlmOutput)

        let output = try JSONDecoder().decode(
            LLM.Output.self,
            from: Data(
                llmOutput.utf8
            )
        )
        test.title = output.content.title
        test.command = output.content.command
        test.expectedOutput = output.content.expectedOutput
        test.notes = testDescription
        testDescription.removeAll()
        field = nil
        return await test.test()
    }

}
