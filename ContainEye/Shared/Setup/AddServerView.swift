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
        ScrollView {
            VStack(alignment: .leading) {
                ServerFormStepHeaderView(
                    currentStep: currentStep,
                    stepCount: Self.steps.count,
                    progress: progress,
                    statusText: nil,
                    canProceed: canProceed,
                    isConnecting: isConnecting,
                    onBack: goBack,
                    onForward: advanceOrConnect,
                    forwardTitle: isLastStep ? "Connect" : "Next"
                )

                ServerFormStepCardView(step: currentStepData)

                VStack(alignment: .leading) {
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
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                AsyncButton {
                    await continueOrConnect()
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text(isLastStep ? "Connect Server" : "Continue")
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canProceed || isConnecting)
                .frame(maxWidth: .infinity)

                NavigationLink(value: URL.servers) {
                    Text("Learn about SSH servers")
                        .font(.footnote)
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.accent)
                .frame(maxWidth: .infinity)
            }
            .padding()
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
    }
}

private extension AddServerView {
    func goBack() {
        guard currentStep > 0 else { return }
        withAnimation(.spring()) {
            currentStep -= 1
        }
    }

    func advanceOrConnect() {
        Task {
            await continueOrConnect()
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
