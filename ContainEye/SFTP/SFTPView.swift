//
//  SFTPView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/26/25.
//

import ButtonKit
import SwiftUI
@preconcurrency import Citadel

struct SFTPView: View {
    @State private var credential = {
        let keychain = keychain()
        if let key = keychain.allKeys().first {
            return keychain.getCredential(for: key)
        }
        return nil
    }()
    @State private var sftp: SFTPClient?
    @State private var openedFile: String?
    @State private var files: [SFTPPathComponent]?
    @State private var showHiddenFiles = false
    @State private var currentDirectory = ""
    @State private var fileContent = ""

    var body: some View {
        if let credential {
            VStack{
                if let openedFile {
                    TextEditor(text: $fileContent)
                        .safeAreaInset(edge: .top) {
                            HStack{
                                Spacer()
                                AsyncButton("Save") {
                                    let openedFile = try await sftp?.openFile(filePath: openedFile, flags: [.create, .truncate, .write])
                                    try await openedFile?.write(.init(string: fileContent))
                                    try await openedFile?.close()
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                                .buttonStyle(.bordered)

                                AsyncButton {
                                    self.openedFile = nil
                                    fileContent.removeAll()
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.circle)
                                .controlSize(.large)
                            }
                        }
                } else {
                    HStack {
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
                    }
                    Form{
                        let ffiles = (files ?? []).filter({showHiddenFiles || !$0.filename.hasPrefix(".")})
                        ForEach(ffiles, id: \.longname) { file in
                            AsyncButton{
                                do {
                                    try await updateDirectories(appending: file.filename)
                                } catch {
                                    if let openedFile = try await sftp?.openFile(filePath: "\(currentDirectory)/\(file.filename)", flags: [.read]) {
                                        fileContent = try await String(buffer: openedFile.readAll())
                                        self.openedFile = try await String(buffer: openedFile.readAll())
                                        try await openedFile.close()
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(file.filename)
                                    Spacer()
                                    VStack(alignment: .trailing){
                                        Text((file.attributes.size ?? 0)/1024, format: .number) + Text("KB")
                                        Text(file.attributes.accessModificationTime?.modificationTime ?? .now, format: .dateTime)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                                    do {
                                        try await sftp?.remove(at: "\(currentDirectory)/\(file.filename)")
                                    } catch {
                                        try await sftp?.rmdir(at: "\(currentDirectory)/\(file.filename)")
                                    }
                                }
                            }
                            .contextMenu{
                                AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                                    do {
                                        try await sftp?.remove(at: "\(currentDirectory)/\(file.filename)")
                                    } catch {
                                        try await sftp?.rmdir(at: "\(currentDirectory)/\(file.filename)")
                                    }
                                }
                            }

                        }
                    }
                    .refreshable {
                        try? await updateDirectories(appending: "")
                    }
                }
            }
            .task(id: credential) {
                do {
                    try? await sftp?.close()
                    sftp = try await SSHClient.connect(host: credential.host, authenticationMethod: .passwordBased(username: credential.username, password: credential.password), hostKeyValidator: .acceptAnything(), reconnect: .always).openSFTP()
                    do {
                        currentDirectory = "/\(credential.username)"
                        try await updateDirectories(appending: "")
                    } catch {
                        currentDirectory = "/"
                        try await updateDirectories(appending: "")
                    }
                } catch {
                    print(error)
                }
            }
        } else {
            ContentUnavailableView("You don't have any servers yet.", systemImage: "server.rack")
        }
    }
    func updateDirectories(appending: String) async throws {
        let newDir = currentDirectory.appending(appending.isEmpty ? "" : "/").appending(appending)
        files = try await sftp?.listDirectory(atPath: newDir).flatMap({$0.components}).sorted(by: {$0.filename < $1.filename})
        currentDirectory = newDir
    }
}

#Preview {
    SFTPView()
}
