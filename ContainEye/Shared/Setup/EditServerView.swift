//
//  EditServerView.swift
//  ContainEye
//
//  Created by Claude on 6/25/25.
//

import SwiftUI
import ButtonKit
import KeychainAccess

struct EditServerView: View {
    @State var credential: Credential
    @State private var originalCredential: Credential
    @State private var currentStep = 0
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showingDeleteConfirmation = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blackbirdDatabase) var db
    
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
        case 0: return !credential.label.isEmpty
        case 1: return !credential.host.isEmpty && credential.port > 0
        case 2: return !credential.username.isEmpty
        case 3: return true // Auth method selection always allows proceeding
        case 4: return canProceedWithAuth()
        default: return false
        }
    }
    
    init(credential: Credential) {
        self._credential = State(initialValue: credential)
        self._originalCredential = State(initialValue: credential)
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
        NavigationView {
            VStack {
                editHeader
                editContent
            }
            .navigationTitle("Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
                        
                        Divider()
                        
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
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteServer()
            }
        } message: {
            Text("Are you sure you want to delete \"\(credential.label)\"? This action cannot be undone.")
        }
    }
    
    private var editHeader: some View {
        VStack {
            // Progress indicator
            HStack {
                Button {
                    if currentStep > 0 {
                        withAnimation(.spring()) {
                            currentStep -= 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(currentStep > 0 ? .blue : .gray)
                }
                .disabled(currentStep == 0)
                
                VStack {
                    HStack {
                        Text("Step \(currentStep + 1) of \(steps.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if hasChanges {
                            Text("Modified")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.blue)
                                .frame(width: geometry.size.width * progress, height: 6)
                                .animation(.spring(), value: progress)
                        }
                    }
                    .frame(height: 6)
                }
                
                Button {
                    if currentStep < steps.count - 1 {
                        nextStep()
                    } else {
                        Task {
                            await saveChanges()
                        }
                    }
                } label: {
                    Text(currentStep == steps.count - 1 ? "Save" : "Next")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(canProceed ? .blue : .gray)
                }
                .disabled(!canProceed)
            }
            .padding()
        }
    }
    
    private var editContent: some View {
        VStack {
            // Step icon and title
            VStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: currentStepData.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                .padding(.bottom, 8)
                
                Text(currentStepData.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text(currentStepData.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            
            // Input section
            VStack {
                if currentStepData.isAuthMethod {
                    authMethodSelection
                } else if currentStep == 4 {
                    authenticationInputs
                } else {
                    currentStepInput
                }
                
                errorDisplay
            }
            .padding(.horizontal, 30)
            
            Spacer()
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
    
    @ViewBuilder
    private var currentStepInput: some View {
        switch currentStep {
        case 0:
            TextField("Server name", text: $credential.label)
                .focused($isFieldFocused)
                .textFieldStyle(ModernTextFieldStyle())
                .submitLabel(.next)
        case 1:
            VStack {
                TextField("Hostname or IP", text: $credential.host)
                    .focused($isFieldFocused)
                    .keyboardType(.URL)
                    .textFieldStyle(ModernTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                
                TextField("Port", text: Binding(
                    get: { credential.port == 0 ? "" : String(credential.port) },
                    set: { credential.port = Int32(Int($0) ?? 22) }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(ModernTextFieldStyle())
                .submitLabel(.next)
            }
        case 2:
            TextField("Username", text: $credential.username)
                .focused($isFieldFocused)
                .textFieldStyle(ModernTextFieldStyle())
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
        default:
            EmptyView()
        }
    }
    
    private var authMethodSelection: some View {
        VStack {
            ForEach(AuthenticationMethod.allCases, id: \.self) { method in
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
        }
    }
    
    private var authenticationInputs: some View {
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
                }
            }
        }
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
    
    private func nextStep() {
        withAnimation(.spring()) {
            currentStep += 1
        }
    }
    
    private func testConnection() async {
        isConnecting = true
        connectionError = nil
        
        do {
            let server = Server(credentialKey: credential.key)
            try await server.connect()
            
            await MainActor.run {
                isConnecting = false
                connectionError = nil
                // Show success feedback
            }
        } catch {
            await MainActor.run {
                connectionError = "Connection test failed: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }
    
    private func saveChanges() async {
        isConnecting = true
        connectionError = nil
        
        do {
            // Update keychain
            let data = try JSONEncoder().encode(credential)
            try keychain().set(data, key: credential.key)
            
            // Update server in database if needed
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
    
    private func deleteServer() {
        Task {
            do {
                // Remove from keychain
                try keychain().remove(credential.key)
                
                // Remove from database
                if let server = try? await Server.read(from: db!, id: credential.key) {
                    try await server.delete(from: db!)
                }
                
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

struct EditStep {
    let icon: String
    let title: String
    let description: String
    let keyboardType: UIKeyboardType
    let isAuthMethod: Bool
    
    init(icon: String, title: String, description: String, keyboardType: UIKeyboardType, isAuthMethod: Bool = false) {
        self.icon = icon
        self.title = title
        self.description = description
        self.keyboardType = keyboardType
        self.isAuthMethod = isAuthMethod
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