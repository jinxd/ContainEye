//
//  SFTPView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/26/25.
//

import ButtonKit
import SwiftUI
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

    func delete(using sftp: SFTPClient) async throws {
        if isDirectory {
            try await sftp.rmdir(at: path)
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

    init() {}

    init(credential: Credential) {
        self._credential = .init(initialValue: credential)
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
                            FileSummaryView(sftp: sftp, file: file) { append in
                                try await updateDirectories(appending: append)
                            } openFile: { path in
                                try await openFile(path: path)
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
    func openFile(path: String) async throws {
        guard let sftp else { return }
        do {
            let openedFile = try await sftp.openFile(filePath: path, flags: [.create, .read])
            fileContent = (try? await String(buffer: openedFile.readAll())) ?? ""
            self.openedFile = path
            try await openedFile.close()
        } catch {
            fileContent = ""
            self.openedFile = path
        }
    }
}


