import SwiftUI

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
