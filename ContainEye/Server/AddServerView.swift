//
//  AddServerView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/15/25.
//

import SwiftUI
import ButtonKit
import KeychainAccess


struct AddServerView: View {
    @State private var dataStreamer = DataStreamer.shared
    @State private var credential = Credential(key: UUID().uuidString, label: "", host: "", port: 22, username: "", password: "")
    @Environment(\.dismiss) var dismiss

    @State private var disabled = false

    @FocusState private var focus : Focus?

    enum Focus {
        case label, host, port, username, password
    }

    @Namespace var namespace

    var body: some View {
        VStack{
            if focus == nil {
                Image(systemName: "server.rack")
                    .resizable()
                    .scaledToFit()
                    .padding(100)
                    .matchedGeometryEffect(id: "server.rack", in: namespace)
            }
            Form {
                Section {
                    TextField("Label", text: $credential.label)
#if !os(macOS)
                        .keyboardType(.asciiCapable)
#endif
                        .focused($focus, equals: .label)
                        .onSubmit {
                            focus = .host
                        }
                        .submitLabel(.next)
                }
                .padding()
                Section {
                    TextField("Host (example.com)", text: $credential.host)
#if !os(macOS)
                        .keyboardType(.URL)
#endif
                        .focused($focus, equals: .host)
                        .onSubmit {
                            focus = .username
                        }
                        .submitLabel(.next)

                    TextField("Port (e.g. 22)", value: $credential.port, format: .number.precision(.fractionLength(0)))
#if !os(macOS)
                        .keyboardType(.numberPad)
#endif
                        .focused($focus, equals: .port)
                        .onSubmit {
                            focus = .username
                        }
                        .submitLabel(.next)
                }
                .padding()

                Section {
                    TextField("User (e.g. root)", text: $credential.username)
#if !os(macOS)
                        .keyboardType(.asciiCapable)
#endif
                        .focused($focus, equals: .username)
                        .onSubmit {
                            focus = .password
                        }
                        .submitLabel(.next)

                    SecureField("Password", text: $credential.password)
                        .focused($focus, equals: .password)
                        .onSubmit {
                            Task{try await addServer()}
                        }
                        .submitLabel(.done)
                }
                .padding()
            }
            .formStyle(.columns)
            .safeAreaInset(edge: .bottom) {
                AsyncButton {
                    do {
#if !os(macOS)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
                        try await addServer()
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
                .disabled(disabled)
                .padding(.bottom)
            }
            .onAppear{
                focus = .label
            }
        }
        .navigationTitle("Add a Server")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if focus != nil {
                Image(systemName: "server.rack")
                    .matchedGeometryEffect(id: "server.rack", in: namespace)
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

    func addServer() async throws {
        let data = try JSONEncoder().encode(credential)

        guard try !keychain().contains(credential.key) else {
            throw AddServerError.existsAlready
        }

        try await dataStreamer.addServer(with: credential)


        try keychain()
            .set(data, key: credential.key)

        dismiss()
        Logger.telemetry("Added server", with: ["total":keychain().allKeys().count])
    }
}

#Preview {
    VStack{}
        .sheet(isPresented: .constant(true)) {
            SheetView(sheet: .addServer)
        }
}
