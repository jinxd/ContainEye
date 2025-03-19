//
//  SSHTerminalView.swift
//  SwiftTerm
//
//  Created by Hannes Nagel on 3/13/25.
//

import SwiftUI
import SwiftSH


public struct Credential: Codable, Equatable, Hashable {
    var key: String
    var label: String
    var host: String
    var port: Int32
    var username: String
    var password: String

    public init(key: String, label: String, host: String, port: Int32, username: String, password: String) {
        self.key = key
        self.label = label
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }
}
import MediaPlayer

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

    var lines: [String] {
        terminalView?.attrStrBuffer!.array.compactMap({$0?.attrStr.string}) ?? []
    }
    public var currentInputLine: String {
        lines.last { string in
            !string.trimmingCharacters(in: .whitespaces).isEmpty
        }?.split(separator: "#").dropFirst().joined(separator: "#") ?? ""
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
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [.new], context: nil)
        self.terminalView!.addSubview(volumeView)
        authenticationChallenge = .byPassword(username: credential.username, password: credential.password)

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

        shell.withCallback { [unowned self] (data: Data?, error: Data?) in
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
        .open { [unowned self] error in
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
}

class AppTerminalView: TerminalView, TerminalViewDelegate {
    let model: SSHTerminalModel

    init(model: SSHTerminalModel) {
        self.model = model
        super.init(frame: .init(x: 0, y: 0, width: 400, height: 400), font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        terminalDelegate = self
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
        for i in 0..<model.currentInputLine.count {
            model.terminalView?.deleteBackward()
        }
        model.terminalView?.insertText(newValue)
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
}

