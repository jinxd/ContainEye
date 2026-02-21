//
//  EditServerView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI
import KeychainAccess

struct EditServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blackbirdDatabase) private var db

    let steps = [
        EditStep(
            icon: "tag.fill",
            title: "Server Name",
            description: "Update your server's display name",
            keyboardType: .default
        ),
        EditStep(
            icon: "globe",
            title: "Connection",
            description: "Modify hostname and port settings",
            keyboardType: .URL
        ),
        EditStep(
            icon: "person.fill",
            title: "Username",
            description: "Change the SSH username",
            keyboardType: .default
        ),
        EditStep(
            icon: "shield.checkered",
            title: "Authentication",
            description: "Update authentication method",
            keyboardType: .default,
            isAuthMethod: true
        ),
        EditStep(
            icon: "key.fill",
            title: "Credentials",
            description: "Update your authentication credentials",
            keyboardType: .default
        )
    ]

    @State private var credential: Credential
    @State private var originalCredential: Credential
    @State private var currentStep = 0
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showingDeleteConfirmation = false
    @FocusState private var isFieldFocused: Bool

    var currentStepData: EditStep {
        steps[currentStep]
    }

    var progress: Double {
        Double(currentStep + 1) / Double(steps.count)
    }

    var hasChanges: Bool {
        credential != originalCredential
    }

    var canProceed: Bool {
        switch currentStep {
        case 0:
            return !credential.label.isEmpty
        case 1:
            return !credential.host.isEmpty && credential.port > 0
        case 2:
            return !credential.username.isEmpty
        case 3:
            return true
        case 4:
            return canProceedWithAuth()
        default:
            return false
        }
    }

    init(credential: Credential) {
        _credential = State(initialValue: credential)
        _originalCredential = State(initialValue: credential)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                editHeader
                editContent
            }
            .padding()
            .navigationTitle("Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Test Connection") {
                            Task {
                                await testConnection()
                            }
                        }
                        Button("Delete Server", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button(role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteServer()
            }
        } message: {
            Text("Are you sure you want to delete \"\(credential.label)\"? This action cannot be undone.")
        }
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: currentStep) {
            connectionError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }
}

// MARK: - Subviews
private extension EditServerView {
    var editHeader: some View {
        HStack {
            Button {
                if currentStep > 0 {
                    withAnimation(.spring()) {
                        currentStep -= 1
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .opacity(currentStep > 0 ? 1 : 0)
            .disabled(currentStep == 0)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Step \(currentStep + 1) of \(steps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if hasChanges {
                        Text("Modified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: progress)
                    .tint(.blue)
            }

            Button(currentStep == steps.count - 1 ? "Save" : "Next") {
                if currentStep < steps.count - 1 {
                    nextStep()
                } else {
                    Task {
                        await saveChanges()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed || isConnecting)
        }
    }

    var editContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: currentStepData.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text(currentStepData.title)
                    .font(.headline)

                Text(currentStepData.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                if currentStepData.isAuthMethod {
                    ServerAuthMethodPicker(selectedMethod: $credential.authMethod)
                } else if currentStep == 4 {
                    ServerAuthenticationInputs(
                        credential: $credential,
                        isFieldFocused: $isFieldFocused,
                        showsKeyTips: false
                    )
                } else {
                    currentStepInput
                }

                ConnectionErrorInlineView(error: connectionError)
            }

            Spacer()
        }
    }

    @ViewBuilder
    var currentStepInput: some View {
        switch currentStep {
        case 0:
            TextField("Server name", text: $credential.label)
                .focused($isFieldFocused)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)
        case 1:
            TextField("Hostname or IP", text: $credential.host)
                .focused($isFieldFocused)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .submitLabel(.next)

            TextField("Port", text: portBinding)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)
        case 2:
            TextField("Username", text: $credential.username)
                .focused($isFieldFocused)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
        default:
            EmptyView()
        }
    }
}

// MARK: - Actions
private extension EditServerView {
    func nextStep() {
        withAnimation(.spring()) {
            currentStep += 1
        }
    }

    func testConnection() async {
        isConnecting = true
        connectionError = nil

        do {
            let server = Server(credentialKey: credential.key)
            try await server.connect()

            await MainActor.run {
                isConnecting = false
                connectionError = nil
            }
        } catch {
            await MainActor.run {
                connectionError = "Connection test failed: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }

    func saveChanges() async {
        isConnecting = true
        connectionError = nil

        do {
            let data = try JSONEncoder().encode(credential)
            try keychain().set(data, key: credential.key)

            if let server = try? await Server.read(from: db!, id: credential.key) {
                try await server.write(to: db!)
            }

            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                connectionError = "Failed to save changes: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }

    func deleteServer() {
        Task {
            do {
                try keychain().remove(credential.key)

                if let server = try? await Server.read(from: db!, id: credential.key) {
                    try await server.delete(from: db!)
                }
                await Snippet.deleteForServer(credentialKey: credential.key, in: db!)

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    connectionError = "Failed to delete server: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Helpers
private extension EditServerView {
    var portBinding: Binding<String> {
        Binding(
            get: { credential.port == 0 ? "" : String(credential.port) },
            set: { credential.port = Int32(Int($0) ?? 22) }
        )
    }

    func canProceedWithAuth() -> Bool {
        switch credential.effectiveAuthMethod {
        case .password:
            return !credential.password.isEmpty
        case .privateKey:
            return credential.hasPrivateKey
        case .privateKeyWithPassphrase:
            return credential.hasPrivateKey && !(credential.passphrase?.isEmpty ?? true)
        }
    }
}

#Preview {
    EditServerView(credential: Credential(
        key: "test",
        label: "Test Server",
        host: "192.168.1.100",
        port: 22,
        username: "admin",
        password: "password"
    ))
}
