//
//  SSHTerminalView.swift
//  SwiftTerm
//
//  Created by Hannes Nagel on 3/13/25.
//

import SwiftUI
import SwiftSH


public enum AuthenticationMethod: Codable, Equatable, Hashable, CaseIterable {
    case password
    case privateKey
    case privateKeyWithPassphrase

    var displayName: String {
        switch self {
        case .password:
            return "Password"
        case .privateKey:
            return "SSH Key"
        case .privateKeyWithPassphrase:
            return "SSH Key + Passphrase"
        }
    }

    var icon: String {
        switch self {
        case .password:
            return "key.fill"
        case .privateKey:
            return "key.horizontal.fill"
        case .privateKeyWithPassphrase:
            return "key.horizontal.fill"
        }
    }
}

public struct Credential: Codable, Equatable, Hashable {
    var key: String
    var label: String
    var host: String
    var port: Int32
    var username: String
    var password: String
    var authMethod: AuthenticationMethod?
    var privateKey: String?
    var passphrase: String?

    public init(key: String, label: String, host: String, port: Int32, username: String, password: String, authMethod: AuthenticationMethod = .password, privateKey: String? = nil, passphrase: String? = nil) {
        self.key = key
        self.label = label
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKey = privateKey
        self.passphrase = passphrase
    }

    // Custom decoding to handle legacy credentials
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int32.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)

        // Handle optional new fields for backward compatibility
        authMethod = try container.decodeIfPresent(AuthenticationMethod.self, forKey: .authMethod)
        privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey)
        passphrase = try container.decodeIfPresent(String.self, forKey: .passphrase)
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, host, port, username, password, authMethod, privateKey, passphrase
    }

    // Legacy support for password-only credentials
    var isPasswordAuth: Bool {
        (authMethod ?? .password) == .password
    }

    var requiresPassphrase: Bool {
        (authMethod ?? .password) == .privateKeyWithPassphrase
    }

    var hasPrivateKey: Bool {
        let method = authMethod ?? .password
        return method != .password && privateKey != nil && !privateKey!.isEmpty
    }

    // Get the effective auth method (defaults to password for legacy credentials)
    var effectiveAuthMethod: AuthenticationMethod {
        authMethod ?? .password
    }
}


import MediaPlayer
import AVFoundation

class SSHTerminalModel: NSObject {
    var credential: Credential
    var shell: SSHShell?
    var terminalView: TerminalView?
    var authenticationChallenge: AuthenticationChallenge?
    var sshQueue: DispatchQueue
    var useVolumeButtons: Bool
    var volumeView: MPVolumeView?
    var slider: UISlider?
    var setBackToVolume: Float = 0.5
    private var isObservingVolume = false

    var lines: [String] {
        terminalView?.attrStrBuffer!.array.compactMap({$0?.attrStr.string}) ?? []
    }
    public var currentInputLine: String {
        // Get the current cursor position from terminal
        guard let terminal = terminalView?.getTerminal() else { return "" }
        
        let currentRow = terminal.buffer.y
        let totalRows = terminal.rows
        
        // Look for the prompt line (contains $ or # at the end typically)
        var promptLineIndex = -1
        for i in stride(from: currentRow, through: max(0, currentRow - 20), by: -1) {
            if i < lines.count {
                let line = lines[i]
                // Look for common shell prompts
                if line.contains("$") || line.contains("#") || line.contains("%") {
                    promptLineIndex = i
                    break
                }
            }
        }
        
        if promptLineIndex == -1 {
            // Fallback to old method if no prompt found
            return lines.last { string in
                !string.trimmingCharacters(in: .whitespaces).isEmpty
            }?.split(separator: "#").dropFirst().joined(separator: "#") ?? ""
        }
        
        // Extract command from prompt line to current line
        var commandParts: [String] = []
        
        for i in promptLineIndex...min(currentRow, lines.count - 1) {
            let line = lines[i]
            if i == promptLineIndex {
                // Extract everything after the last prompt symbol
                let promptSymbols = ["$ ", "# ", "% ", "> "]
                var commandPart = line
                for symbol in promptSymbols {
                    if let range = line.range(of: symbol, options: .backwards) {
                        commandPart = String(line[range.upperBound...])
                        break
                    }
                }
                commandParts.append(commandPart)
            } else {
                // Add continuation lines
                commandParts.append(line)
            }
        }
        
        return commandParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    init(credential: Credential, useVolumeButtons: Bool) {
        self.credential = credential
        self.sshQueue = DispatchQueue(label: "SSH Queue")
        self.useVolumeButtons = useVolumeButtons
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            if let volume = change?[.newKey] as? Float {
                guard volume != setBackToVolume, useVolumeButtons else { return }
                if volume < setBackToVolume {
                    terminalView?.sendKeyDown()
                } else {
                    terminalView?.sendKeyUp()
                }
                slider?.value = setBackToVolume
            }
        }
    }
    func connect(terminalView: TerminalView) {
        self.terminalView = terminalView

        let volumeView = MPVolumeView(frame: .init(origin: .init(x: -1000, y: -1000), size: .zero))
        volumeView.isOpaque = false
        volumeView
        slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        if let slider, useVolumeButtons {
            slider.value = min(0.1, max(0.9, slider.value))
            setBackToVolume = slider.value
        }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        if !isObservingVolume {
            AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [.new], context: nil)
            isObservingVolume = true
        }
        self.terminalView!.addSubview(volumeView)
        switch credential.effectiveAuthMethod {
        case .password:
            authenticationChallenge = .byPassword(username: credential.username, password: credential.password)
        case .privateKey:
            authenticationChallenge = .byPublicKeyFromMemory(username: credential.username, password: "", publicKey: nil, privateKey: credential.privateKey!.data(using: .utf8)!)
        case .privateKeyWithPassphrase:
            authenticationChallenge = .byPublicKeyFromMemory(username: credential.username, password: credential.passphrase!, publicKey: nil, privateKey: credential.privateKey!.data(using: .utf8)!)
        }

        shell = try? SSHShell(sshLibrary: Libssh2.self,
                              host: credential.host,
                              port: UInt16(credential.port),
                              environment: [Environment(name: "LANG", variable: "en_US.UTF-8")],
                              terminal: "xterm-256color")
        shell?.log.enabled = false
        shell?.setCallbackQueue(queue: sshQueue)

        sshQueue.async {
            self.connectSSH()
        }
    }

    private func connectSSH() {
        guard let shell = shell else { return }

        shell.withCallback { [weak self] (data: Data?, error: Data?) in
            guard let self = self else { return }
            if let d = data {
                let sliced = Array(d)[0...]
                let blocksize = 1024
                var next = 0
                let last = sliced.endIndex

                while next < last {
                    let end = min(next + blocksize, last)
                    let chunk = sliced[next..<end]
                    DispatchQueue.main.sync {
                        self.terminalView?.feed(byteArray: chunk)
                    }
                    next = end
                }
            }
        }
        .connect()
        .authenticate(authenticationChallenge)
        .open { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.terminalView?.feed(text: "[ERROR] \(error)\n")
            } else {
                if let terminal = self.terminalView?.getTerminal() {
                    shell.setTerminalSize(width: UInt(terminal.cols), height: UInt(terminal.rows))
                }
            }
        }
    }

    func send(data: ArraySlice<UInt8>) {
        shell?.write(Data(data)) { err in
            if let e = err {
                print("Error sending \(e)")
            }
        }
    }
    
    func cleanup() {
        // Disconnect SSH
        shell?.close {
            print("SSH connection closed")
        }
        shell = nil
        
        // Remove volume observer
        if isObservingVolume {
            AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
            isObservingVolume = false
        }
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: [])
        
        // Clean up views
        volumeView?.removeFromSuperview()
        volumeView = nil
        slider = nil
        terminalView = nil
        
        print("SSHTerminalModel cleaned up")
    }
    
    deinit {
        cleanup()
        print("SSHTerminalModel deinit")
    }
}

class AppTerminalView: TerminalView, TerminalViewDelegate {
    let model: SSHTerminalModel

    init(model: SSHTerminalModel) {
        self.model = model
        super.init(frame: .init(x: 0, y: 0, width: 400, height: 400), font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        terminalDelegate = self
        
        // Enable smart tab completion
        enableSmartTabCompletion = true
        onTabCompletion = { [weak self] input in
            self?.handleTabCompletion(input: input)
        }
    }
    
    private func handleTabCompletion(input: String) {
        // This can be used to trigger completion in the parent view
        // For now, we'll just print the input for debugging
        print("Tab completion requested for: \(input)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }

    func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        model.shell?.setTerminalSize(width: UInt(newCols), height: UInt(newRows))
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        model.send(data: data)
    }

    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) {
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
    }

    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}

public struct SSHTerminalView: UIViewRepresentable {
    let terminalView : AppTerminalView
    let model: SSHTerminalModel
    public var currentInputLine: String {
        model.currentInputLine
    }
    public func setCurrentInputLine(_ newValue: String) {
        if currentInputLine.trimmingCharacters(in: .whitespaces) == newValue.trimmingCharacters(in: .whitespaces) {
            terminalView.send(txt: "\n")
            return
        }
        
        let currentCommand = model.currentInputLine
        // Clear current input by sending Ctrl+C then clearing line
        model.terminalView?.send(txt: "\u{03}") // Ctrl+C to cancel current command
        // Small delay to ensure the command is cancelled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.model.terminalView?.insertText(newValue)
        }
    }
    public var useVolumeButtons: Bool {
        get {model.useVolumeButtons}
        set {model.useVolumeButtons = newValue}
    }

    public init(credential: Credential, useVolumeButtons: Bool) {
        self.model = .init(credential: credential, useVolumeButtons: useVolumeButtons)
        terminalView = AppTerminalView(model: model)
        model.connect(terminalView: terminalView)
    }

    public func makeUIView(context: Context) -> TerminalView {
        return terminalView
    }

    public func updateUIView(_ uiView: TerminalView, context: Context) {}
    
    public func cleanup() {
        model.cleanup()
    }
    
    public static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        // Additional cleanup if needed
        print("SSHTerminalView dismantled")
    }
}

