//
//  AddServerView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI

struct AddServerView: View {
    @Environment(\.blackbirdDatabase) private var db
    @AppStorage("screen") private var appScreen = ContentView.Screen.setup

    @Binding var screen: Int

    let steps = [
        SetupStep(
            icon: "tag.fill",
            title: "Server Name",
            description: "Give your server a friendly name",
            placeholder: "My Production Server",
            keyboardType: .default
        ),
        SetupStep(
            icon: "globe",
            title: "Hostname",
            description: "Enter your server's IP address or domain",
            placeholder: "192.168.1.100 or server.example.com",
            keyboardType: .URL
        ),
        SetupStep(
            icon: "number",
            title: "SSH Port",
            description: "Usually 22 for SSH connections",
            placeholder: "22",
            keyboardType: .numberPad
        ),
        SetupStep(
            icon: "person.fill",
            title: "Username",
            description: "Your SSH username",
            placeholder: "root or ubuntu",
            keyboardType: .default
        ),
        SetupStep(
            icon: "shield.checkered",
            title: "Authentication",
            description: "Choose how to authenticate",
            placeholder: "",
            keyboardType: .default,
            isAuthMethod: true
        ),
        SetupStep(
            icon: "key.fill",
            title: "Authentication Details",
            description: "Enter your authentication credentials",
            placeholder: "Enter your password",
            keyboardType: .default,
            isSecure: true
        )
    ]

    @State private var credential = Credential(key: UUID().uuidString, label: "", host: "", port: 22, username: "", password: "", authMethod: .password)
    @State private var currentStep = 0
    @State private var isConnecting = false
    @State private var connectionError: String?
    @FocusState private var isFieldFocused: Bool

    var currentStepData: SetupStep {
        steps[currentStep]
    }

    var progress: Double {
        Double(currentStep + 1) / Double(steps.count)
    }

    var canProceed: Bool {
        switch currentStep {
        case 0:
            return !credential.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return !credential.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2:
            return credential.port > 0
        case 3:
            return !credential.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 4:
            return true
        case 5:
            return canProceedWithAuth()
        default:
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                setupHeader
                stepContent
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
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
private extension AddServerView {
    var setupHeader: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    withAnimation(.spring()) {
                        currentStep -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .tint(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var stepContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepIconAndTitle
            inputSection
            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var stepIconAndTitle: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: currentStepData.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.blue)
                .frame(width: 56, height: 56)
                .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(currentStepData.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(currentStepData.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if currentStepData.isAuthMethod {
                ServerAuthMethodPicker(selectedMethod: $credential.authMethod)
            } else if currentStep == 5 {
                ServerAuthenticationInputs(
                    credential: $credential,
                    isFieldFocused: $isFieldFocused,
                    showsKeyTips: true
                )
            } else if currentStepData.isSecure {
                SecureField(currentStepData.placeholder, text: $credential.password)
                    .focused($isFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            } else {
                TextField(currentStepData.placeholder, text: currentStepBinding, axis: .horizontal)
                    .id(currentStep)
                    .focused($isFieldFocused)
                    .keyboardType(currentStepData.keyboardType)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(currentStep <= 1 ? .never : .words)
                    .submitLabel(currentStep == steps.count - 1 ? .done : .next)
                    .onSubmit {
                        advanceFromKeyboard()
                    }
            }

            ConnectionErrorInlineView(error: connectionError)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if #available(iOS 26.0, *) {
                Button {
                    if currentStep == steps.count - 1 {
                        Task { await connectToServer() }
                    } else {
                        nextStep()
                    }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text(currentStep == steps.count - 1 ? "Connect Server" : "Continue")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canProceed || isConnecting)
                .frame(maxWidth: .infinity)

                NavigationLink(value: URL.servers) {
                    Text("Learn about SSH servers")
                        .font(.footnote)
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Button {
                    if currentStep == steps.count - 1 {
                        Task { await connectToServer() }
                    } else {
                        nextStep()
                    }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text(currentStep == steps.count - 1 ? "Connect Server" : "Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || isConnecting)
                .frame(maxWidth: .infinity)

                NavigationLink(value: URL.servers) {
                    Text("Learn about SSH servers")
                        .font(.footnote)
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Actions
private extension AddServerView {
    func nextStep() {
        withAnimation(.spring()) {
            currentStep += 1
        }
    }

    func advanceFromKeyboard() {
        guard canProceed else { return }
        if currentStep == steps.count - 1 {
            Task { await connectToServer() }
        } else if !currentStepData.isAuthMethod {
            nextStep()
        }
    }

    func connectToServer() async {
        isConnecting = true
        connectionError = nil

        do {
            let data = try JSONEncoder().encode(credential)
            let server = Server(credentialKey: credential.key)

            try await server.connect()
            try await server.write(to: db!)
            try keychain().set(data, key: credential.key)

            await MainActor.run {
                withAnimation(.spring()) {
                    appScreen = .serverList
                }
            }
        } catch {
            await MainActor.run {
                connectionError = "Connection failed: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }
}

// MARK: - Helpers
private extension AddServerView {
    var currentStepBinding: Binding<String> {
        switch currentStep {
        case 0:
            return $credential.label
        case 1:
            return $credential.host
        case 2:
            return Binding(
                get: { credential.port == 0 ? "" : String(credential.port) },
                set: { credential.port = Int32(Int($0) ?? 0) }
            )
        case 3:
            return $credential.username
        default:
            return $credential.password
        }
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
    AddServerView(screen: .constant(1))
}
