import SwiftUI
import ButtonKit

struct AddServerView: View {
    @Environment(\.blackbirdDatabase) private var db
    @AppStorage("screen") private var appScreen = ContentView.Screen.setup

    @Binding var screen: Int

    private static let steps = [
        ServerFormStep(
            icon: "tag.fill",
            title: "Server Name",
            description: "Give your server a friendly name",
            field: .label,
            placeholder: "My Production Server"
        ),
        ServerFormStep(
            icon: "globe",
            title: "Hostname",
            description: "Enter your server's IP address or domain",
            field: .host,
            placeholder: "192.168.1.100 or server.example.com",
            keyboardType: .URL
        ),
        ServerFormStep(
            icon: "number",
            title: "SSH Port",
            description: "Usually 22 for SSH connections",
            field: .port,
            placeholder: "22",
            keyboardType: .numberPad
        ),
        ServerFormStep(
            icon: "person.fill",
            title: "Username",
            description: "Your SSH username",
            field: .username,
            placeholder: "root or ubuntu"
        ),
        ServerFormStep(
            icon: "shield.checkered",
            title: "Authentication",
            description: "Choose how to authenticate",
            field: .authenticationMethod
        ),
        ServerFormStep(
            icon: "key.fill",
            title: "Authentication Details",
            description: "Enter your authentication credentials",
            field: .authenticationDetails
        )
    ]

    @State private var credential = Credential(
        key: UUID().uuidString,
        label: "",
        host: "",
        port: 22,
        username: "",
        password: "",
        authMethod: .password
    )
    @State private var currentStep = 0
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var portText = "22"
    @FocusState private var isFieldFocused: Bool

    private var progress: Double {
        Double(currentStep + 1) / Double(Self.steps.count)
    }

    private var canProceed: Bool {
        ServerFormValidation.canProceed(credential: credential, currentStep: currentStep, steps: Self.steps)
    }

    private var currentStepData: ServerFormStep {
        Self.steps[currentStep]
    }

    private var isLastStep: Bool {
        currentStep == Self.steps.count - 1
    }

    var body: some View {
        Form {
            Section {
                ServerFormStepCardView(step: currentStepData, isPrimaryStep: currentStep == 0)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section {
                ServerFormInputsView(
                    credential: $credential,
                    steps: Self.steps,
                    currentStep: currentStep,
                    portText: $portText,
                    isFieldFocused: $isFieldFocused,
                    showsKeyTips: true
                )

                ConnectionErrorInlineView(error: connectionError)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                AsyncButton {
                    await continueOrConnect()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(isLastStep ? "Connect Server" : "Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || isConnecting)

                NavigationLink(value: URL.servers) {
                    Text("Learn about SSH servers")
                        .font(.footnote.weight(.medium))
                        .underline()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.regularMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if currentStep > 0 {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(currentStep + 1) of \(Self.steps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                            Capsule()
                                .fill(.accent)
                                .frame(width: max(18, proxy.size.width * progress))
                        }
                    }
                    .frame(height: 6)
                }
                .frame(width: 170, alignment: .leading)
            }
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
            syncPortTextFromCredential()
        }
        .onSubmit {
            guard canProceed, !isConnecting else { return }
            Task {
                await continueOrConnect()
            }
        }
    }
}

private extension AddServerView {
    func goBack() {
        guard currentStep > 0 else { return }
        withAnimation(.spring()) {
            currentStep -= 1
        }
    }

    func continueOrConnect() async {
        if isLastStep {
            await connectToServer()
            return
        }
        withAnimation(.spring()) {
            currentStep += 1
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

    func applyPortText() {
        let filtered = portText.filter(\.isNumber)
        if filtered != portText {
            portText = filtered
        }
        credential.port = Int32(Int(filtered) ?? 0)
    }

    func syncPortTextFromCredential() {
        let updated = credential.port == 0 ? "" : String(credential.port)
        if portText != updated {
            portText = updated
        }
    }
}

#Preview(traits: .sampleData) {
    AddServerView(screen: .constant(1))
}
