//
//  SecondSetupView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/28/25.
//

import SwiftUI
import ButtonKit

struct SecondSetupView: View {
    @Binding var screen: Int?
    @State private var credential = Credential(key: UUID().uuidString, label: "", host: "", port: 22, username: "", password: "")
    @State private var showing = Field.label
    @FocusState private var field : Field?
    @Environment(\.triggerButton) private var triggerButton

    enum Field: CaseIterable {
        case label, host, port, username, password
    }

    var body: some View {
        VStack {
            Spacer()
            Text("Alright, let's add a Server")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            questionText
                .padding(.horizontal)

            Spacer()
            TextField("Enter a label", text: $credential.label)
                .focused($field, equals: .label)
                .padding(10)
                .background(.accent.quinary, in: .capsule)
                .padding(.horizontal, 30)

            if showing != .label {
                TextField("Host", text: $credential.host)
                    .focused($field, equals: .host)
                    .padding(10)
                    .background(.accent.quinary, in: .capsule)
                    .padding(.horizontal, 30)
                    .textInputAutocapitalization(.never)
                if [Field.port, .username, .password].contains(showing) {
                    TextField("Port (default: 22)", value: $credential.port, format: .number)
                        .keyboardType(.numberPad)
                        .focused($field, equals: .port)
                        .padding(10)
                        .background(.accent.quinary, in: .capsule)
                        .padding(.horizontal, 30)
                    if [Field.username, .password].contains(showing) {
                        TextField("Username", text: $credential.username)
                            .focused($field, equals: .username)
                            .padding(10)
                            .background(.accent.quinary, in: .capsule)
                            .padding(.horizontal, 30)
                            .textInputAutocapitalization(.never)

                        if showing == .password {
                            SecureField("Password", text: $credential.password)
                                .focused($field, equals: .password)
                                .padding(10)
                                .background(.accent.quinary, in: .capsule)
                                .padding(.horizontal, 30)
                        }
                    }
                }
            }
            Spacer()

            AsyncButton(showing == .password ? "Add" : "Next") {
                try await showNextField()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(nextButtonDisabled)

            NavigationLink("Learn about Servers", value: Help.servers)
        }
        .onSubmit(of: .text) {
            guard showing != .password else { return }
            showing = Field.allCases[Field.allCases.index(
                after: Field.allCases
                    .firstIndex(of: showing)!
            )]
            field = showing
        }
    }

    func showNextField() async throws {
        if showing == .password {
            try await addServer()
            screen = 3
        } else {
            showing = Field.allCases[Field.allCases.index(
                after: Field.allCases
                    .firstIndex(of: showing)!
            )]
            field = showing
        }
    }


    func addServer() async throws {
        let data = try JSONEncoder().encode(credential)

        try await DataStreamer.shared.addServer(with: credential)


        try keychain()
            .set(data, key: credential.key)


        Logger.telemetry("Added server", with: ["total":keychain().allKeys().count])
    }
    var questionText: Text {
        switch showing {
        case .label:
            Text("How would you like to identify it?")
        case .host:
            Text("What is the hostname or IP-Address to connect to the server?")
        case .port:
            Text("On what port should ContainEye connect? (Usually that's 22)")
        case .username:
            Text("Which user should be used to connect?")
        case .password:
            Text("What's the password for that user?")
        }
    }
    var nextButtonDisabled : Bool {
        switch showing {
        case .label:
            credential.label.isEmpty
        case .host:
            credential.host.isEmpty || credential.label.isEmpty
        case .port:
            credential.label.isEmpty || credential.host.isEmpty || credential.port == 0
        case .username:
            credential.label.isEmpty || credential.host.isEmpty || credential.port == 0 || credential.username.isEmpty
        case .password:
            credential.label.isEmpty || credential.host.isEmpty || credential.port == 0 || credential.username.isEmpty || credential.password.isEmpty
        }
    }
}
