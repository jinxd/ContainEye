//
//  AddServerView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI
import ButtonKit

struct AddServerView: View {
    @Binding var screen: Int
    @State private var credential = Credential(key: UUID().uuidString, label: "", host: "", port: 22, username: "", password: "", authMethod: .password)
    @State private var currentStep = 0
    @State private var isConnecting = false
    @State private var connectionError: String?
    @FocusState private var isFieldFocused: Bool
    @Environment(\.blackbirdDatabase) var db
    
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
    
    var currentStepData: SetupStep {
        steps[currentStep]
    }
    
    var progress: Double {
        Double(currentStep + 1) / Double(steps.count)
    }
    
    var canProceed: Bool {
        switch currentStep {
        case 0: return !credential.label.isEmpty
        case 1: return !credential.host.isEmpty
        case 2: return credential.port > 0
        case 3: return !credential.username.isEmpty
        case 4: return true // Auth method selection always allows proceeding
        case 5: return canProceedWithAuth()
        default: return false
        }
    }
    
    private func canProceedWithAuth() -> Bool {
        switch credential.effectiveAuthMethod {
        case .password:
            return !credential.password.isEmpty
        case .privateKey:
            return credential.hasPrivateKey
        case .privateKeyWithPassphrase:
            return credential.hasPrivateKey && !(credential.passphrase?.isEmpty ?? true)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack {
                setupHeader
                stepContent
            }
        }
        .defaultScrollAnchor(.center)
    }
    
    private var setupHeader: some View {
        VStack {
            setupProgressBar
            Spacer()
        }
    }
    
    private var setupProgressBar: some View {
        HStack {
            backButton
            progressSection
            skipButton
        }
        .padding()
    }
    
    private var backButton: some View {
        Button {
            if currentStep > 0 {
                withAnimation(.spring()) {
                    currentStep -= 1
                }
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3)
                .foregroundStyle(currentStep > 0 ? .blue : .clear)
        }
        .disabled(currentStep == 0)
    }
    
    private var progressSection: some View {
        VStack {
            HStack {
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.blue)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.spring(), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
    
    private var skipButton: some View {
        Button {
            screen = 3 // Skip to test setup
        } label: {
            Text("Skip")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }
    
    private var stepContent: some View {
        VStack {
            stepIconAndTitle
            inputSection
            Spacer()
            actionButtons
        }
    }
    
    private var stepIconAndTitle: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: currentStepData.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }
            .padding(.bottom)
            
            Text(currentStepData.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            Text(currentStepData.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
    
    private var inputSection: some View {
        VStack {
            if currentStepData.isAuthMethod {
                authMethodSelection
            } else if currentStep == 5 {
                authenticationInputs()
            } else if currentStepData.isSecure {
                passwordInput
            } else {
                standardInput
            }
            
            errorDisplay
        }
        .padding(.horizontal, 30)
    }
    
    private var authMethodSelection: some View {
        VStack {
            ForEach(AuthenticationMethod.allCases, id: \.self) { method in
                authMethodButton(method)
            }
        }
    }
    
    private func authMethodButton(_ method: AuthenticationMethod) -> some View {
        Button {
            credential.authMethod = method
        } label: {
            HStack {
                Image(systemName: method.icon)
                    .font(.title3)
                    .foregroundStyle(credential.effectiveAuthMethod == method ? .blue : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading) {
                    Text(method.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(authMethodDescription(method))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                if credential.effectiveAuthMethod == method {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(credential.effectiveAuthMethod == method ? .blue.opacity(0.1) : Color(.systemGray6))
                    .stroke(credential.effectiveAuthMethod == method ? .blue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var passwordInput: some View {
        SecureField(currentStepData.placeholder, text: $credential.password)
            .focused($isFieldFocused)
            .textFieldStyle(ModernTextFieldStyle())
            .submitLabel(.done)
    }
    
    private var standardInput: some View {
        TextField(currentStepData.placeholder, text: currentStepBinding, axis: .horizontal)
            .focused($isFieldFocused)
            .keyboardType(currentStepData.keyboardType)
            .textFieldStyle(ModernTextFieldStyle())
            .textInputAutocapitalization(currentStep == 1 ? .never : .words)
            .submitLabel(currentStep == steps.count - 1 ? .done : .next)
    }
    
    private var errorDisplay: some View {
        Group {
            if let error = connectionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }
    
    private var actionButtons: some View {
        VStack {
            if currentStep == steps.count - 1 {
                connectButton
            } else {
                continueButton
            }
            
            helpLink
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 40)
    }
    
    private var connectButton: some View {
        AsyncButton {
            await connectToServer()
        } label: {
            HStack {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isConnecting ? "Connecting..." : "Connect Server")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .disabled(!canProceed || isConnecting)
    }
    
    private var continueButton: some View {
        Button {
            nextStep()
        } label: {
            HStack {
                Text("Continue")
                    .fontWeight(.semibold)
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canProceed ? .blue : .gray.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .disabled(!canProceed)
    }
    
    private var helpLink: some View {
        NavigationLink(value: URL.servers) {
            HStack {
                Image(systemName: "questionmark.circle")
                Text("Learn about SSH servers")
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(.top, 8)
        .onSubmit {
            if currentStep < steps.count - 1 && canProceed {
                nextStep()
            } else if currentStep == steps.count - 1 && canProceed {
                Task {
                    await connectToServer()
                }
            }
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
    
    private var currentStepBinding: Binding<String> {
        switch currentStep {
        case 0: return $credential.label
        case 1: return $credential.host
        case 2: return Binding(
            get: { credential.port == 0 ? "" : String(credential.port) },
            set: { credential.port = Int32(Int($0) ?? 22) }
        )
        case 3: return $credential.username
        default: return $credential.password
        }
    }
    
    private func authMethodDescription(_ method: AuthenticationMethod) -> String {
        switch method {
        case .password:
            return "Use your account password"
        case .privateKey:
            return "Use SSH key for secure authentication"
        case .privateKeyWithPassphrase:
            return "SSH key protected with passphrase"
        }
    }
    
    @ViewBuilder
    private func authenticationInputs() -> some View {
        VStack {
            switch credential.effectiveAuthMethod {
            case .password:
                SecureField("Enter your password", text: $credential.password)
                    .focused($isFieldFocused)
                    .textFieldStyle(ModernTextFieldStyle())
                    .submitLabel(.done)
                
            case .privateKey, .privateKeyWithPassphrase:
                VStack {
                    // SSH Key input
                    VStack(alignment: .leading) {
                        Text("SSH Private Key")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("Paste your SSH private key here", text: Binding(
                            get: { credential.privateKey ?? "" },
                            set: { credential.privateKey = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .lineLimit(6...12)
                        .focused($isFieldFocused)
                        .textFieldStyle(ModernTextFieldStyle())
                        .font(.system(.caption, design: .monospaced))
                    }
                    
                    if credential.effectiveAuthMethod == .privateKeyWithPassphrase {
                        VStack(alignment: .leading) {
                            Text("Passphrase")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            SecureField("Enter key passphrase", text: Binding(
                                get: { credential.passphrase ?? "" },
                                set: { credential.passphrase = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(ModernTextFieldStyle())
                        }
                        .padding(.top)
                    }
                    
                    // Helper text
                    VStack(alignment: .leading) {
                        Text("💡 SSH Key Tips:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("• Generate keys with: ssh-keygen -t rsa -b 4096")
                            Text("• Copy public key to server: ssh-copy-id user@server")
                            Text("• Supports RSA, Ed25519, ECDSA key formats")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    private func nextStep() {
        withAnimation(.spring()) {
            currentStep += 1
        }
    }
    
    private func connectToServer() async {
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
                    screen = 3 // Move to test setup
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

struct SetupStep {
    let icon: String
    let title: String
    let description: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let isSecure: Bool
    let isAuthMethod: Bool
    
    init(icon: String, title: String, description: String, placeholder: String, keyboardType: UIKeyboardType, isSecure: Bool = false, isAuthMethod: Bool = false) {
        self.icon = icon
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.keyboardType = keyboardType
        self.isSecure = isSecure
        self.isAuthMethod = isAuthMethod
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.blue.opacity(0.3), lineWidth: 1)
            )
    }
}

#Preview {
    AddServerView(screen: .constant(1))
}
