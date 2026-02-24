import SwiftUI

struct ServerAuthenticationInputs: View {
    @Binding var credential: Credential
    var isFieldFocused: FocusState<Bool>.Binding
    let showsKeyTips: Bool

    var body: some View {
        switch credential.effectiveAuthMethod {
        case .password:
            SecureField("Enter your password", text: $credential.password)
                .focused(isFieldFocused)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)

        case .privateKey, .privateKeyWithPassphrase:
            VStack(alignment: .leading, spacing: 12) {
                Text("SSH Private Key")
                    .font(.headline)

                TextField("Paste your SSH private key here", text: privateKeyBinding, axis: .vertical)
                    .lineLimit(6...12)
                    .focused(isFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                if credential.effectiveAuthMethod == .privateKeyWithPassphrase {
                    SecureField("Enter key passphrase", text: passphraseBinding)
                        .textFieldStyle(.roundedBorder)
                }

                if showsKeyTips {
                    keyTips
                }
            }
        }
    }

    private var privateKeyBinding: Binding<String> {
        Binding(
            get: { credential.privateKey ?? "" },
            set: { credential.privateKey = $0.isEmpty ? nil : $0 }
        )
    }

    private var passphraseBinding: Binding<String> {
        Binding(
            get: { credential.passphrase ?? "" },
            set: { credential.passphrase = $0.isEmpty ? nil : $0 }
        )
    }

    private var keyTips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SSH Key Tips")
                .font(.caption)
                .fontWeight(.semibold)

            Text("- Generate keys with: ssh-keygen -t rsa -b 4096")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("- Copy public key to server: ssh-copy-id user@server")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("- Supports RSA, Ed25519, ECDSA key formats")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @State var credential = Credential(
        key: "preview-auth",
        label: "Preview",
        host: "host",
        port: 22,
        username: "root",
        password: "",
        authMethod: .privateKeyWithPassphrase,
        privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----\npreview\n-----END OPENSSH PRIVATE KEY-----",
        passphrase: "secret"
    )
    @FocusState var focused: Bool
    return ServerAuthenticationInputs(
        credential: $credential,
        isFieldFocused: $focused,
        showsKeyTips: true
    )
    .padding()
}
