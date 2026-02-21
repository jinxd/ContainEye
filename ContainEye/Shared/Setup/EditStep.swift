import SwiftUI

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
