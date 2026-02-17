import Foundation
import CoreGraphics

enum XTermBridgeEventType: String {
    case terminalReady = "terminal_ready"
    case terminalData = "terminal_data"
    case terminalResized = "terminal_resized"
    case cwdChanged = "cwd_changed"
    case promptBegins = "prompt_begins"
    case promptEnds = "prompt_ends"
    case commandStarted = "command_started"
    case commandExited = "command_exited"
    case shellIntegrationError = "shell_integration_error"
    case selectionChanged = "selection_changed"
    case selectionHint = "selection_hint"
    case openExternalLink = "open_external_link"
    case editorCommandEntered = "editor_command_entered"
}

struct XTermBridgeEvent {
    let type: XTermBridgeEventType
    let payload: [String: Any]

    init?(body: Any) {
        guard
            let dict = body as? [String: Any],
            let rawType = dict["type"] as? String,
            let type = XTermBridgeEventType(rawValue: rawType)
        else {
            return nil
        }

        self.type = type
        self.payload = dict["payload"] as? [String: Any] ?? [:]
    }

    var data: String? {
        payload["data"] as? String
    }

    var cols: Int? {
        payload["cols"] as? Int
    }

    var rows: Int? {
        payload["rows"] as? Int
    }

    var cwd: String? {
        payload["cwd"] as? String
    }

    var command: String? {
        payload["cmd"] as? String
    }

    var exitCode: String? {
        payload["exitCode"] as? String
    }

    var selectionText: String? {
        payload["selection"] as? String
    }

    var selectionHintMessage: String? {
        payload["message"] as? String
    }

    var editorCommandLine: String? {
        payload["line"] as? String
    }

    var hasSelection: Bool? {
        payload["hasSelection"] as? Bool
    }

    var menuX: CGFloat? {
        numberPayload("menuX")
    }

    var menuY: CGFloat? {
        numberPayload("menuY")
    }

    private func numberPayload(_ key: String) -> CGFloat? {
        if let value = payload[key] as? Double {
            return CGFloat(value)
        }
        if let value = payload[key] as? Int {
            return CGFloat(value)
        }
        return nil
    }
}

enum TerminalConnectionStatus: String, Codable {
    case idle
    case connecting
    case connected
    case disconnected
    case failed
}

enum ShellIntegrationStatus: String, Codable {
    case unknown
    case active
    case warning
}

struct PromptPosition: Codable, Hashable {
    let row: Int
    let col: Int
}

struct ActiveCommandLifecycle: Codable, Hashable {
    var command: String
    var startedAtMs: Double
    var exitCode: String?
    var endedAtMs: Double?
}
