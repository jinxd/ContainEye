import SwiftUI

struct ServerFormInputsView: View {
    @Binding var credential: Credential
    let steps: [ServerFormStep]
    let currentStep: Int
    @Binding var portText: String
    var isFieldFocused: FocusState<Bool>.Binding
    let showsKeyTips: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if currentStepField == .authenticationMethod {
                ServerAuthMethodPicker(selectedMethod: $credential.authMethod)
            } else if currentStepField == .authenticationDetails {
                ServerAuthenticationInputs(
                    credential: $credential,
                    isFieldFocused: isFieldFocused,
                    showsKeyTips: showsKeyTips
                )
            } else {
                primaryInputField

                if currentStepField == .hostAndPort {
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.next)
                }
            }
        }
    }

    private var currentStepField: ServerFormField {
        steps[currentStep].field
    }

    @ViewBuilder
    private var primaryInputField: some View {
        switch currentStepField {
        case .label:
            TextField(currentStepPlaceholder("Server name"), text: $credential.label)
                .focused(isFieldFocused)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)
                .textInputAutocapitalization(.words)
        case .host, .hostAndPort:
            TextField(currentStepPlaceholder("Hostname or IP"), text: $credential.host)
                .focused(isFieldFocused)
                .keyboardType(currentStepKeyboardType(.URL))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
        case .port:
            TextField(currentStepPlaceholder("22"), text: $portText)
                .focused(isFieldFocused)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.next)
        case .username:
            TextField(currentStepPlaceholder("Username"), text: $credential.username)
                .focused(isFieldFocused)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .submitLabel(.next)
        case .authenticationMethod, .authenticationDetails:
            EmptyView()
        }
    }

    private func currentStepPlaceholder(_ fallback: String) -> String {
        let placeholder = steps[currentStep].placeholder
        return placeholder.isEmpty ? fallback : placeholder
    }

    private func currentStepKeyboardType(_ fallback: UIKeyboardType) -> UIKeyboardType {
        steps[currentStep].keyboardType == .default ? fallback : steps[currentStep].keyboardType
    }
}

#Preview(traits: .sampleData) {
    @Previewable @State var credential = Credential(
        key: "preview-edit-input",
        label: "Preview Server",
        host: "192.168.0.10",
        port: 22,
        username: "root",
        password: "secret"
    )
    @Previewable @State var portText = "22"
    @FocusState var focused: Bool
    let steps = [
        ServerFormStep(
            icon: "globe",
            title: "Connection",
            description: "Modify hostname and port settings",
            field: .hostAndPort,
            placeholder: "Hostname or IP",
            keyboardType: .URL
        )
    ]
    return ServerFormInputsView(
        credential: $credential,
        steps: steps,
        currentStep: 0,
        portText: $portText,
        isFieldFocused: $focused,
        showsKeyTips: false
    )
    .padding()
}
