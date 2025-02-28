//
//  AddServerSetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//


import SwiftUI
import ButtonKit
import Blackbird

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

            Picker("Host", selection: $test.credentialKey) {
                Text("Local (only urls)")
                    .tag("")
                let allKeys = keychain().allKeys()
                let credentials = allKeys.compactMap{keychain().getCredential(for: $0)}
                ForEach(credentials, id: \.key) { credential in
                    Text(credential.label)
                        .tag(credential.key)
                }
            }
            .pickerStyle(.inline)
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
                    Menu("Add this test"){
                        AsyncButton("and add another test") {
                            try? await Logger.telemetry(
                                "added test",
                                with: [
                                    "servers":keychain().allKeys().count,
                                    "tests":ServerTest.count(in: db!, matching: \.$credentialKey != "-")
                                ]
                            )
                            try await test.write(to: db!)
                            test = ServerTest(id: .random(in: (.min)...(.max)), title: "", credentialKey: "", command: "", expectedOutput: "", status: .notRun)
                        }
                        .buttonStyle(.bordered)
                        AsyncButton("but do not add another test") {
                            try? await Logger.telemetry(
                                "added test",
                                with: [
                                    "servers":keychain().allKeys().count,
                                    "tests":ServerTest.count(in: db!, matching: \.$credentialKey != "-")
                                ]
                            )
                            try await test.write(to: db!)
                            UserDefaults.standard.set(ContentView.Screen.testList.rawValue, forKey: "screen")
                        }
                    }
                }
            }
            Spacer()
            HStack {
                TextField("Describe what to test", text: $testDescription, axis: .vertical)
                    .focused($field, equals: .askAI)
                AsyncButton {

                    let dirtyLlmOutput = await LLM.generate(
                        prompt: testDescription,
                        systemPrompt: LLM.addTestSystemPrompt
                    )
                    let llmOutput = LLM.cleanLLMOutput(dirtyLlmOutput)

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
                    test.title = output.title
                    test.command = output.command
                    test.expectedOutput = output.expectedOutput
                    test.notes = testDescription
                    testDescription.removeAll()
                    field = nil
                    test = await test.test()
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
}
