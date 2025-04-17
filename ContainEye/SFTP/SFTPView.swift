//
//  SFTPView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/26/25.
//

import ButtonKit
import SwiftUI
import UIKit
@preconcurrency import Citadel

struct SFTPItem: Identifiable, Hashable, Equatable {
    static func == (lhs: SFTPItem, rhs: SFTPItem) -> Bool {
        lhs.id == rhs.id && lhs.path == rhs.path
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(path)
    }

    var id = UUID().uuidString
    var isDirectory: Bool
    var file: SFTPPathComponent
    var path: String

    func delete(using sftp: SFTPClient, credential: Credential) async throws {
        if isDirectory {
            do {
                try await sftp.rmdir(at: path)
            } catch {
                 let _ = try await SSHClientActor.shared.execute("rm -r \(path)", on: credential)
            }
        } else {
            try await sftp.remove(at: path)
        }
    }
    func rename(to newName: String, using sftp: SFTPClient) async throws {
        let newPath = "/\(path.split(separator: "/").dropLast().joined(separator: "/"))/\(newName)"
        try await sftp.rename(at: path, to: newPath)
    }
    func move(to newPath: String, using sftp: SFTPClient) async throws {
        try await sftp.rename(at: path, to: newPath)
    }
}

class DocumentInteractionController: NSObject, UIDocumentInteractionControllerDelegate {
    var onDismiss: (() -> Void)?
    
    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        onDismiss?()
    }
}

enum OpenDocumentMode {
    case ask
    case asText
    case export
}

struct SFTPView: View {
    @State private var credential : Credential? = {
        let keychain = keychain()
        if let key = keychain.allKeys().first {
            return keychain.getCredential(for: key)
        }
        return nil
    }()
    @State private var sftp: SFTPClient?
    @State private var openedFile: String?
    @State private var files: [SFTPItem]?
    @State private var showHiddenFiles = false
    @State private var currentDirectory = ""
    @State private var fileContent = ""
    @Environment(\.editMode) var editMode: Binding<EditMode>?
    @State private var isloading = false
    @State private var documentController: UIDocumentInteractionController?
    @State private var documentDelegate = DocumentInteractionController()
    @State private var tempFileURL: URL?
    
    private let tempDirectory: URL = {
        FileManager.default.temporaryDirectory.appendingPathComponent("ContainEye")
    }()
    
    init() {
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    init(credential: Credential) {
        self._credential = .init(initialValue: credential)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    var body: some View {
        if let credential {
            VStack{
                if let openedFile {
                    TextEditor(text: $fileContent)
                        .safeAreaInset(edge: .top) {
                            HStack{
                                Spacer()
                                AsyncButton("Save") {
                                    try await sftp?.withFile(filePath: openedFile, flags: [.create, .read, .write], { file in
                                        try await file.write(.init(string: fileContent))
                                    })
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                                .buttonStyle(.bordered)

                                AsyncButton {
                                    self.openedFile = nil
                                    fileContent.removeAll()
                                    try await updateDirectories(appending: "")
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.circle)
                                .controlSize(.large)
                            }
                        }
                } else if let sftp {
                    HStack {
                        AsyncButton{
                            try await goHome()
                        } label: {
                            Image(systemName: "house")
                        }
                        Picker("Server", selection: $credential) {
                            let keychain = keychain()
                            let credentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
                            ForEach(credentials, id: \.key){ credential in
                                Text(credential.label)
                                    .tag(credential)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle(isOn: $showHiddenFiles) {
                            Image(systemName: "list.bullet")
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                    }
                    .padding(.horizontal)
                    Form{
                        let ffiles : [SFTPItem] = (files ?? []).filter({showHiddenFiles || !$0.file.filename.hasPrefix(".")})
                        if currentDirectory != "/" {
                            AsyncButton("go up") {
                                try await updateDirectories(appending: "..")
                            }
                            .foregroundStyle(.primary)
                        }
                        ForEach(ffiles, id: \.id) { file in
                            FileSummaryView(sftp: sftp, credential: credential, file: file) { append in
                                try await updateDirectories(appending: append)
                            } openFile: { path, mode in
                                try await openFile(path: path, mode: mode)
                            }
                        }
                    }
                    .refreshable {
                        try? await updateDirectories(appending: "")
                    }
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Spacer()
                            Menu{
                                AsyncButton("New Directory") {
                                    try await sftp.createDirectory(atPath: "\(currentDirectory)/\(ConfirmatorManager.shared.ask("What do you want to call the new directory?"))")
                                    try await updateDirectories(appending: "")
                                }
                                .foregroundStyle(.primary)
                                AsyncButton("New File") {
                                    try await openFile(path: "\(currentDirectory)/\(ConfirmatorManager.shared.ask("What do you want to call the new file?"))")
                                }
                                .foregroundStyle(.primary)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                            .padding(.bottom)
                            .padding(.trailing)
                        }
                    }
                }
            }
            .redacted(reason: isloading ? .invalidated : [])
            .task(id: credential) {
                do {
                    try await goHome()
                } catch {
                    print(error)
                }
            }
            .trackView("sftp/connected")
        } else {
            let keychain = keychain()
            let credentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
            if credentials.isEmpty {
                ContentUnavailableView("You don't have any servers yet.", systemImage: "server.rack")
                    .trackView("sftp/no-servers")
            } else {
                VStack {
                    Text("Select a server to connect to.")
                        .font(.headline)
                    List {
                        ForEach(credentials, id: \.key) { credential in
                            Button("Credential"){
                                self.credential = credential
                            }
                        }
                    }
                }
                .trackView("sftp/select-server")
            }
        }
    }
    func goHome() async throws {
        guard let credential else { return }
        try? await sftp?.close()
        sftp = try await SSHClient.connect(host: credential.host, authenticationMethod: .passwordBased(username: credential.username, password: credential.password), hostKeyValidator: .acceptAnything(), reconnect: .always).openSFTP()
        do {
            currentDirectory = "/\(credential.username)"
            try await updateDirectories(appending: "")
        } catch {
            currentDirectory = "/"
            try await updateDirectories(appending: "")
        }
    }
    func updateDirectories(appending: String) async throws {
        isloading = true
        defer { isloading = false}
        if !(sftp?.isActive ?? false) {
            try? await sftp?.close()
            guard let credential else {return}
            sftp = try await SSHClient.connect(host: credential.host, authenticationMethod: .passwordBased(username: credential.username, password: credential.password), hostKeyValidator: .acceptAnything(), reconnect: .always).openSFTP()
        }
        let newDir = currentDirectory.appending(appending.isEmpty ? "" : "/").appending(appending)
        print(newDir)
        if let newFiles = try await sftp?.listDirectory(atPath: newDir).flatMap({$0.components}).sorted(by: {$0.filename < $1.filename}){
            files = []
            let filenames: [String] = newFiles.map({$0.filename})
            let dirs = await withTaskGroup(of: (key: String, value: Bool).self) { group in
                for file in filenames {
                    group.addTask{
                        let filepath = "\(newDir)/\(file)"
                        do {
                            let _ = try await sftp?.listDirectory(atPath: filepath)
                            return (filepath, true)
                        } catch {
                            return (filepath, false)
                        }
                    }
                }
                var returns = [String : Bool]()
                for await result in group {
                    returns[result.key] = result.value
                }
                return returns
            }
            currentDirectory = newDir
            for file in newFiles {
                let filepath = "\(newDir)/\(file.filename)"
                files?.append(.init(isDirectory: dirs[filepath] ?? false, file: file, path: filepath))
            }
        }
        print("end")
    }
    func openFile(path: String, mode: OpenDocumentMode = .ask) async throws {
        guard let sftp else { return }
        isloading = true
        defer { isloading = false }
        
        // Create a temporary file URL
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let tempFileURL = tempDirectory.appendingPathComponent(fileName)
        self.tempFileURL = tempFileURL
        
        do {
            // Read file from SFTP
            let openedFile = try await sftp.openFile(filePath: path, flags: [.create, .read])
            let buffer = try await openedFile.readAll()
            try await openedFile.close()
            let data = Data(buffer: buffer)
            
            try data.write(to: tempFileURL)
            
            // Handle different modes
            switch mode {
            case .asText:
                if let content = String(data: data, encoding: .utf8) {
                    await MainActor.run {
                        self.fileContent = content
                        self.openedFile = path
                    }
                }
                
            case .export:
                await MainActor.run {
                    let controller = UIDocumentInteractionController(url: tempFileURL)
                    controller.delegate = self.documentDelegate
                    self.documentController = controller
                    
                    // Set up the dismiss handler
                    self.documentDelegate.onDismiss = {
                        Task {
                            do {
                                // Read the modified file
                                let modifiedData = try Data(contentsOf: tempFileURL)
                                
                                // Convert Data to ByteBuffer and write back to SFTP
                                try await sftp.withFile(filePath: path, flags: [.create, .write]) { file in
                                    try await file.write(.init(data: modifiedData))
                                }
                                
                                // Clean up
                                try? FileManager.default.removeItem(at: tempFileURL)
                                self.tempFileURL = nil
                                self.documentController = nil
                                
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } catch {
                                print("Error saving file back to SFTP: \(error)")
                            }
                        }
                    }
                    
                    // Present the document interaction controller
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        controller.presentOpenInMenu(from: CGRect.zero, in: rootViewController.view, animated: true)
                    }
                }
                
            case .ask:
                // Present action sheet
                await MainActor.run {
                    let alert = UIAlertController(title: "Open File", message: "How would you like to open this file?", preferredStyle: .actionSheet)
                    
                    // Add "Edit as Text" action
                    alert.addAction(UIAlertAction(title: "Edit as Text", style: .default) { _ in
                        let content = String(data: data, encoding: .utf8) ?? ""
                        DispatchQueue.main.async {
                            self.fileContent = content
                            self.openedFile = path
                        }
                    })
                    
                    // Add "Export" action
                    alert.addAction(UIAlertAction(title: "Export/Download", style: .default) { _ in
                        let controller = UIDocumentInteractionController(url: tempFileURL)
                        controller.delegate = self.documentDelegate
                        self.documentController = controller
                        
                        // Set up the dismiss handler
                        self.documentDelegate.onDismiss = {
                            Task {
                                do {
                                    // Read the modified file
                                    let modifiedData = try Data(contentsOf: tempFileURL)
                                    
                                    // Convert Data to ByteBuffer and write back to SFTP
                                    try await sftp.withFile(filePath: path, flags: [.create, .write]) { file in
                                        try await file.write(.init(data: modifiedData))
                                    }
                                    
                                    // Clean up
                                    try? FileManager.default.removeItem(at: tempFileURL)
                                    self.tempFileURL = nil
                                    self.documentController = nil
                                    
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } catch {
                                    print("Error saving file back to SFTP: \(error)")
                                }
                            }
                        }
                        
                        // Present the document interaction controller
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootViewController = window.rootViewController {
                            controller.presentOpenInMenu(from: CGRect.zero, in: rootViewController.view, animated: true)
                        }
                    })
                    
                    // Add cancel action
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                        try? FileManager.default.removeItem(at: tempFileURL)
                        self.tempFileURL = nil
                    })
                    
                    // Present the alert
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        } catch {
            print("Error opening file: \(error)")
        }
    }
}


