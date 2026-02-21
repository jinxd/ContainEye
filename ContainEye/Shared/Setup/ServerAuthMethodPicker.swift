import SwiftUI

struct ServerAuthMethodPicker: View {
    @Binding var selectedMethod: AuthenticationMethod?

    private var effectiveMethod: AuthenticationMethod {
        selectedMethod ?? .password
    }

    var body: some View {
        Picker("Authentication", selection: $selectedMethod) {
            ForEach(AuthenticationMethod.allCases, id: \.self) { method in
                Text(method.displayName)
                    .tag(Optional(method))
            }
        }
        .pickerStyle(.menu)

        Text(effectiveMethod.setupDescription)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private extension AuthenticationMethod {
    var setupDescription: String {
        switch self {
        case .password:
            return "Use your account password"
        case .privateKey:
            return "Use SSH key for secure authentication"
        case .privateKeyWithPassphrase:
            return "SSH key protected with passphrase"
        }
    }
}
