import Foundation
import SwiftUI

extension Notification.Name {
    static let terminalOpenRequestsDidChange = Notification.Name("terminal.openRequestsDidChange")
    static let terminalSFTPEditorRequestsDidChange = Notification.Name("terminal.sftpEditorRequestsDidChange")
}

struct TerminalOpenRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let credentialKey: String
    let label: String
    let createdAt: Date

    init(credentialKey: String, label: String) {
        self.id = UUID()
        self.credentialKey = credentialKey
        self.label = label
        self.createdAt = .now
    }
}

struct SFTPEditorOpenRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let credentialKey: String
    let path: String
    let cwd: String?
    let createdAt: Date

    init(credentialKey: String, path: String, cwd: String?) {
        self.id = UUID()
        self.credentialKey = credentialKey
        self.path = path
        self.cwd = cwd
        self.createdAt = .now
    }
}

@MainActor
@Observable
class TerminalNavigationManager {
    static let shared = TerminalNavigationManager()

    var openRequests: [TerminalOpenRequest] = []
    var sftpEditorOpenRequests: [SFTPEditorOpenRequest] = []
    var showingDeeplinkConfirmation = false

    private init() {}

    func navigateToTerminal(with credential: Credential) {
        openRequests.append(TerminalOpenRequest(credentialKey: credential.key, label: credential.label))
        showingDeeplinkConfirmation = true
        NotificationCenter.default.post(name: .terminalOpenRequestsDidChange, object: nil)
        UserDefaults.standard.set(ContentView.Screen.terminal.rawValue, forKey: "screen")
    }

    func dequeueAllRequests() -> [TerminalOpenRequest] {
        let requests = openRequests
        openRequests.removeAll(keepingCapacity: false)
        return requests
    }

    func navigateToSFTPEditor(credentialKey: String, path: String, cwd: String?) {
        sftpEditorOpenRequests.append(
            SFTPEditorOpenRequest(
                credentialKey: credentialKey,
                path: path,
                cwd: cwd
            )
        )
        NotificationCenter.default.post(name: .terminalSFTPEditorRequestsDidChange, object: nil)
        UserDefaults.standard.set(ContentView.Screen.sftp.rawValue, forKey: "screen")
    }

    func dequeueAllSFTPEditorRequests() -> [SFTPEditorOpenRequest] {
        let requests = sftpEditorOpenRequests
        sftpEditorOpenRequests.removeAll(keepingCapacity: false)
        return requests
    }
}
