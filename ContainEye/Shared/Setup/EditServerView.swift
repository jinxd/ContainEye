//
//  EditServerView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI
import KeychainAccess
import ButtonKit
@preconcurrency import Citadel

struct EditServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blackbirdDatabase) private var db

    @State private var credential: Credential
    @State private var originalCredential: Credential
    @State private var currentStep = 0
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showingDeleteConfirmation = false
    @State private var portText: String
    @FocusState private var isFieldFocused: Bool

    private static let steps = [
        ServerFormStep(icon: "tag.fill", title: "Server Name", description: "Update your server's display name", field: .label, placeholder: "Server name"),
        ServerFormStep(icon: "globe", title: "Connection", description: "Modify hostname and port settings", field: .hostAndPort, placeholder: "Hostname or IP", keyboardType: .URL),
        ServerFormStep(icon: "person.fill", title: "Username", description: "Change the SSH username", field: .username, placeholder: "Username"),
        ServerFormStep(icon: "shield.checkered", title: "Authentication", description: "Update authentication method", field: .authenticationMethod),
        ServerFormStep(icon: "key.fill", title: "Credentials", description: "Update your authentication credentials", field: .authenticationDetails)
    ]

    private var currentStepData: ServerFormStep { Self.steps[currentStep] }
    private var progress: Double { Double(currentStep + 1) / Double(Self.steps.count) }
    private var hasChanges: Bool { credential != originalCredential }
    private var isLastStep: Bool { currentStep == Self.steps.count - 1 }

    private var canProceed: Bool {
        ServerFormValidation.canProceed(credential: credential, currentStep: currentStep, steps: Self.steps)
    }

    init(credential: Credential) {
        _credential = State(initialValue: credential)
        _originalCredential = State(initialValue: credential)
        _portText = State(initialValue: credential.port == 0 ? "" : String(credential.port))
    }

    var body: some View {
        VStack {
            ServerFormStepHeaderView(
                currentStep: currentStep,
                stepCount: Self.steps.count,
                progress: progress,
                statusText: hasChanges ? "Modified" : nil,
                canProceed: canProceed,
                isConnecting: isConnecting,
                onBack: goBack,
                onForward: advanceOrSave,
                forwardTitle: isLastStep ? "Save" : "Next"
            )

            ServerFormStepCardView(step: currentStepData)

            ServerFormInputsView(
                credential: $credential,
                steps: Self.steps,
                currentStep: currentStep,
                portText: $portText,
                isFieldFocused: $isFieldFocused,
                showsKeyTips: false
            )

            ConnectionErrorInlineView(error: connectionError)
            Spacer()
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
                    AsyncButton("Test Connection") {
                        await testConnection()
                    }
                    Button("Delete Server", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
            Button(role: .cancel) {}
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
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                isFieldFocused = true
            }
        }
        .onChange(of: portText) {
            applyPortText()
        }
        .onChange(of: credential.port) {
            let updated = credential.port == 0 ? "" : String(credential.port)
            if portText != updated {
                portText = updated
            }
        }
    }
}

private extension EditServerView {
    func goBack() {
        guard currentStep > 0 else { return }
        withAnimation(.spring()) {
            currentStep -= 1
        }
    }

    func advanceOrSave() {
        if currentStep < Self.steps.count - 1 {
            withAnimation(.spring()) {
                currentStep += 1
            }
            return
        }
        Task { await saveChanges() }
    }

    func applyPortText() {
        let filtered = portText.filter(\.isNumber)
        if filtered != portText {
            portText = filtered
        }
        credential.port = Int32(Int(filtered) ?? 0)
    }

    func testConnection() async {
        isConnecting = true
        connectionError = nil

        do {
            let client = try await SSHClient.connect(using: credential)
            try await client.close()
            isConnecting = false
        } catch {
            connectionError = "Connection test failed: \(error.localizedDescription)"
            isConnecting = false
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
            dismiss()
        } catch {
            connectionError = "Failed to save changes: \(error.localizedDescription)"
            isConnecting = false
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
                dismiss()
            } catch {
                connectionError = "Failed to delete server: \(error.localizedDescription)"
            }
        }
    }

}

#Preview(traits: .sampleData) {
    EditServerView(credential: Credential(
        key: "test",
        label: "Test Server",
        host: "192.168.1.100",
        port: 22,
        username: "admin",
        password: "password"
    ))
}
