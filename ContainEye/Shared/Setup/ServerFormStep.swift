import SwiftUI

enum ServerFormField {
    case label
    case host
    case hostAndPort
    case port
    case username
    case authenticationMethod
    case authenticationDetails
}

struct ServerFormStep {
    let icon: String
    let title: String
    let description: String
    let field: ServerFormField
    let placeholder: String
    let keyboardType: UIKeyboardType

    init(
        icon: String,
        title: String,
        description: String,
        field: ServerFormField,
        placeholder: String = "",
        keyboardType: UIKeyboardType = .default
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.field = field
        self.placeholder = placeholder
        self.keyboardType = keyboardType
    }
}

extension Credential {
    var hasValidAuthenticationInput: Bool {
        switch effectiveAuthMethod {
        case .password:
            return !password.isEmpty
        case .privateKey:
            return hasPrivateKey
        case .privateKeyWithPassphrase:
            return hasPrivateKey && !(passphrase?.isEmpty ?? true)
        }
    }
}

enum ServerFormValidation {
    static func canProceed(credential: Credential, currentStep: Int, steps: [ServerFormStep]) -> Bool {
        guard steps.indices.contains(currentStep) else { return false }

        switch steps[currentStep].field {
        case .label:
            return !credential.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .host:
            return !credential.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .hostAndPort:
            return !credential.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && credential.port > 0
        case .port:
            return credential.port > 0
        case .username:
            return !credential.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .authenticationMethod:
            return true
        case .authenticationDetails:
            return credential.hasValidAuthenticationInput
        }
    }
}
