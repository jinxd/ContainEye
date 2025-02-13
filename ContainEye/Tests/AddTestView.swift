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
        case title, notes, command, expectedOutput
    }

    @State private var serverTest = ServerTest(id: .random(in: Int.min...Int.max), title: "", credentialKey: "-", command: "", expectedOutput: "", status: .notRun)

    @Environment(\.blackbirdDatabase) var db

    @Namespace private var namespace

    @Environment(LLMEvaluator.self) var llm

    private let systemPrompt = #"""
You are an expert system administrator and shell scripting specialist. Your task is to generate a single shell command that tests a system, service, or resource, and a corresponding regular expression that validates the command's output.

Follow these instructions exactly:
1. Read the provided test case description.
2. Write exactly one executable shell command that performs the test.
3. Write exactly one regular expression that matches exactly the output produced by the command.
4. Output a valid JSON object with exactly two keys: "command" and "expectedOutput". Do not include any extra text, commentary, or explanation.

**Output Format:**
Your output must strictly follow this JSON structure:

```json
{
    "command": "Your shell command here",
    "expectedOutput": "Your regular expression here"
}
```

**Example:**
If the test case is “Check available disk space”, your output must be:

```json
{
    "command": "df -h / | awk 'NR==2 {print $4}'",
    "expectedOutput": "^[0-9]+[A-Za-z]$"
}
```

**Additional Requirements:**
- Do not use aliases, variables, or unnecessary options.
- Do not include any additional flags or parameters unless necessary.
- The shell command must be executable exactly as provided.
- The regular expression must match exactly the output of the shell command.
"""#


    var body: some View {
        VStack{
            Form {
                if focus == nil {
                    Image(systemName: "testtube.2")
                        .resizable()
                        .scaledToFit()
                        .padding(100)
                        .matchedGeometryEffect(id: "testtube.2", in: namespace)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Title (example.com)", text: $serverTest.title)
#if !os(macOS)
                        .keyboardType(.asciiCapable)
#endif
                        .focused($focus, equals: .title)
                        .onSubmit {
                            focus = .notes
                        }
                        .submitLabel(.next)
                }
                Section("Describe your test") {
                    TextEditor(text: $serverTest.notes.nonOptional)
#if !os(macOS)
                        .keyboardType(.asciiCapable)
#endif
                        .focused($focus, equals: .notes)
                        .onSubmit {
                            focus = nil
                        }
                        .submitLabel(.next)
                }
                Section {
                    AsyncButton("Generate test from description") {
                        let dirtyLlmOutput = await llm.generate(
                            prompt: "\(serverTest.title)\n\(serverTest.notes ?? "")",
                            systemPrompt: systemPrompt
                        )
                        let llmOutput = cleanLLMOutput(dirtyLlmOutput)

                        struct LLMOutput: Decodable {
                            let command: String
                            let expectedOutput: String
                        }
                        
                        let output = try JSONDecoder().decode(
                            LLMOutput.self,
                            from: Data(
                                llmOutput.utf8
                            )
                        )
                        serverTest.command = output.command
                        serverTest.expectedOutput = output.expectedOutput
                    }
                } footer: {
                    if llm.isThinking && llm.running {
                        Text(llm.elapsedTime ?? 0, format: .number.precision(.fractionLength(1))).monospacedDigit() + Text(" seconds elapsed") + Text(
                            llm.output
                                .replacingOccurrences(of: "<think>", with: "")
                        )
                    } else {
                        Text(llm.modelInfo.replacingOccurrences(of: "mlx-community/", with: ""))
                    }
                }


                Section{
                    Picker("Host", selection: $serverTest.credentialKey) {
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
            .scrollContentBackground(.hidden)
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
//                focus = .title
            }
        }
        .navigationTitle("Test a server")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if focus != nil {
                Image(systemName: "testtube.2")
                    .matchedGeometryEffect(id: "testtube.2", in: namespace)
                    .onTapGesture {
                        focus = nil
                    }
            }
        }
        .animation(.smooth, value: focus)
    }
    enum AddServerError: Error {
        case existsAlready
    }

    func addTest() async throws {
        try await serverTest.write(to: db!)
        dismiss()
        let _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        Logger.telemetry("added server test")
    }
}

#Preview {
    AddServerView()
}


func cleanLLMOutput(_ input: String) -> String {
    // Remove <think>...</think>
    let thinkPattern = #"<think>.*?</think>"#
    let cleanedThinkOutput = (try? NSRegularExpression(pattern: thinkPattern, options: .dotMatchesLineSeparators))?
        .stringByReplacingMatches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count), withTemplate: "")
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? input

    return cleanedThinkOutput
        .replacingOccurrences(of: "```json", with: "")
        .replacingOccurrences(of: "``` json", with: "")
        .replacingOccurrences(of: "```", with: "")
}

