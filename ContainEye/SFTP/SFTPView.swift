//
//  SFTPView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/26/25.
//

import ButtonKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Blackbird
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

class DocumentPickerController: NSObject, UIDocumentPickerDelegate {
    var onPick: (([URL]) -> Void)?
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick?(urls)
    }
}

enum OpenDocumentMode {
    case ask
    case asText
    case export
}

struct SFTPView: View {
    @BlackbirdLiveModels({try await Server.read(from: $0, matching: .all)}) var servers
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
    @State private var documentPickerDelegate = DocumentPickerController()
    @State private var tempFileURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var showingPathInput = false
    @State private var pathInput = ""
    @State private var terminalManager = TerminalNavigationManager.shared
    
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
        Group {
            if let credential {
                VStack{
                if let openedFile {
                    PowerfulTextEditorView(
                        text: $fileContent,
                        filePath: openedFile,
                        onSave: {
                            try await sftp?.withFile(filePath: openedFile, flags: [.create, .read, .write], { file in
                                try await file.write(.init(string: fileContent))
                            })
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        },
                        onClose: {
                            self.openedFile = nil
                            fileContent.removeAll()
                            try await updateDirectories(appending: "")
                        }
                    )
                } else if let sftp {
                    // Enhanced Navigation Header
                    VStack {
                        HStack {
                            // Home Button
                            AsyncButton{
                                try await goHome()
                            } label: {
                                Image(systemName: "house.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        LinearGradient(
                                            colors: [.blue, .blue.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(Circle())
                                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            
                            // Server Picker
                            Picker("Server", selection: $credential) {
                                let keychain = keychain()
                                let credentials = keychain.allKeys().compactMap({keychain.getCredential(for: $0)})
                                ForEach(credentials, id: \.key){ credential in
                                    Text(credential.label)
                                        .tag(credential)
                                }
                            }
                            .pickerStyle(.segmented)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                            
                            // Hidden Files Toggle
                            Button {
                                showHiddenFiles.toggle()
                            } label: {
                                Image(systemName: showHiddenFiles ? "eye.fill" : "eye.slash.fill")
                                    .font(.title3)
                                    .foregroundStyle(showHiddenFiles ? .orange : .secondary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(showHiddenFiles ? .orange.opacity(0.1) : .secondary.opacity(0.1))
                                            .stroke(showHiddenFiles ? .orange.opacity(0.3) : .secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Enhanced Path Display
                        VStack {
                            HStack {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("Current Path")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                            }
                            
                            Button(action: {
                                pathInput = currentDirectory
                                showingPathInput = true
                            }) {
                                HStack {
                                    Text(currentDirectory.isEmpty ? "/" : currentDirectory)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.regularMaterial)
                                        .stroke(.blue.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                    
                    Form{
                        let ffiles : [SFTPItem] = (files ?? []).filter({showHiddenFiles || !$0.file.filename.hasPrefix(".")})
                        
                        // Action buttons section
                        Section {
                            if currentDirectory != "/" {
                                // Go Up Button
                                AsyncButton {
                                    try await updateDirectories(appending: "..")
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.up")
                                            .font(.title3)
                                            .foregroundStyle(.blue)
                                        
                                        VStack(alignment: .leading) {
                                            Text("Go Up")
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text("Navigate to parent directory")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.up")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Upload Files
                            Button {
                                presentFilePicker()
                            } label: {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Upload Files")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("Select files from your device")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUploading)
                            .opacity(isUploading ? 0.6 : 1.0)
                            
                            // New Folder
                            Button {
                                Task {
                                    do {
                                        let dirName = try await ConfirmatorManager.shared.ask("What do you want to call the new directory?")
                                        try await sftp.createDirectory(atPath: "\(currentDirectory)/\(dirName)")
                                        try await updateDirectories(appending: "")
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    } catch {
                                        ConfirmatorManager.shared.showError(error, title: "Failed to Create Directory")
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.title3)
                                        .foregroundStyle(.orange)
                                    
                                    VStack(alignment: .leading) {
                                        Text("New Folder")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("Create a new directory")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUploading)
                            .opacity(isUploading ? 0.6 : 1.0)
                            
                            // New File
                            Button {
                                Task {
                                    do {
                                        let fileName = try await ConfirmatorManager.shared.ask("What do you want to call the new file?")
                                        try await openFile(path: "\(currentDirectory)/\(fileName)")
                                    } catch {
                                        ConfirmatorManager.shared.showError(error, title: "Failed to Create File")
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.title3)
                                        .foregroundStyle(.green)
                                    
                                    VStack(alignment: .leading) {
                                        Text("New File")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("Create a new file")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUploading)
                            .opacity(isUploading ? 0.6 : 1.0)
                        }
                        
                        // Files and folders section
                        if !ffiles.isEmpty {
                            Section("Files & Folders") {
                                ForEach(ffiles, id: \.id) { file in
                                    FileSummaryView(sftp: sftp, credential: credential, file: file) { append in
                                        try await updateDirectories(appending: append)
                                    } openFile: { path, mode in
                                        try await openFile(path: path, mode: mode)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        try? await updateDirectories(appending: "")
                    }
                    .safeAreaInset(edge: .bottom) {
                        if isUploading {
                            VStack {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                        .symbolEffect(.pulse)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Uploading Files...")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        Text("\(Int(uploadProgress * 100))% complete")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(Int(uploadProgress * 100))%")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                        .monospacedDigit()
                                }
                                
                                // Custom Progress Bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // Background
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.blue.opacity(0.1))
                                            .frame(height: 8)
                                        
                                        // Progress
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.blue, .blue.opacity(0.7)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geometry.size.width * uploadProgress, height: 8)
                                            .animation(.easeInOut(duration: 0.3), value: uploadProgress)
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.blue.opacity(0.05))
                                    .stroke(.blue.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal)
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
                        VStack {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .font(.system(size: 60))
                                .foregroundStyle(.blue)
                                .symbolEffect(.pulse)
                            
                            Text("Connect to Server")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Text("Select a server to browse files and manage content")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ]) {
                            ForEach(credentials, id: \.key) { credential in
                                Button {
                                    self.credential = credential
                                } label: {
                                    VStack {
                                        if let server = servers.results.first(where: { $0.credentialKey == credential.key }) {
                                            OSIconView(server: server, size: 32)
                                        } else {
                                            Image(systemName: "server.rack")
                                                .font(.title)
                                                .foregroundStyle(.blue)
                                        }
                                        
                                        Text(credential.label)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                        
                                        Text(credential.host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.blue.opacity(0.05))
                                            .stroke(.blue.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .trackView("sftp/select-server")
                }
            }
        }
        .alert("Navigate to Path", isPresented: $showingPathInput) {
            TextField("Enter path", text: $pathInput)
            Button(role: .cancel) { }
            Button("Go") {
                Task {
                    await navigateToPath(pathInput)
                }
            }
        } message: {
            Text("Enter the full path you want to navigate to")
        }
        .onAppear {
            processPendingSFTPEditorRequests()
        }
        .onChange(of: terminalManager.sftpEditorOpenRequests.count) { _, _ in
            processPendingSFTPEditorRequests()
        }
    }

    private func processPendingSFTPEditorRequests() {
        let requests = terminalManager.dequeueAllSFTPEditorRequests()
        guard !requests.isEmpty else {
            return
        }

        Task {
            for request in requests {
                await openSFTPEditorRequest(request)
            }
        }
    }

    private func openSFTPEditorRequest(_ request: SFTPEditorOpenRequest) async {
        guard let targetCredential = keychain().getCredential(for: request.credentialKey) else {
            return
        }

        do {
            credential = targetCredential
            try await goHome()

            let resolvedPath = try await resolvePathForEditorRequest(request, credential: targetCredential)
            let directory = (resolvedPath as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                currentDirectory = directory
                try await updateDirectories(appending: "")
            }
            try await openFile(path: resolvedPath, mode: .asText)
        } catch {
            ConfirmatorManager.shared.showError(error, title: "Failed to Open File")
        }
    }

    private func resolvePathForEditorRequest(_ request: SFTPEditorOpenRequest, credential: Credential) async throws -> String {
        let rawPath = request.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else {
            return request.path
        }

        let candidatePath: String
        if rawPath.hasPrefix("/") {
            candidatePath = rawPath
        } else if rawPath == "~" {
            candidatePath = "/\(credential.username)"
        } else if rawPath.hasPrefix("~/") {
            candidatePath = "/\(credential.username)/\(rawPath.dropFirst(2))"
        } else if let cwd = request.cwd, cwd.hasPrefix("/") {
            candidatePath = joinPath(cwd, rawPath)
        } else {
            candidatePath = rawPath
        }

        if let sftp, let resolved = try? await sftp.getRealPath(atPath: candidatePath) {
            return resolved
        }

        return candidatePath
    }

    private func joinPath(_ base: String, _ part: String) -> String {
        if base.hasSuffix("/") {
            return base + part
        }
        return base + "/" + part
    }

    func goHome() async throws {
        guard let credential else { return }
        try? await sftp?.close()
        sftp = try await SSHClient.connect(using: credential).openSFTP()
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
            sftp = try await SSHClient.connect(using: credential).openSFTP()
        }
        let newDirFull = currentDirectory.appending(appending.isEmpty ? "" : "/").appending(appending)
        let newDir = try await sftp?.getRealPath(atPath: newDirFull) ?? newDirFull
        
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
    
    func navigateToPath(_ path: String) async {
        guard !path.isEmpty else { return }
        
        do {
            // Validate the path by trying to list it
            if let sftp = sftp {
                let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
                let _ = try await sftp.listDirectory(atPath: normalizedPath)
                
                // If successful, update the current directory
                await MainActor.run {
                    currentDirectory = normalizedPath
                }
                
                // Refresh the file list
                try await updateDirectories(appending: "")
            }
        } catch {
            // Show error feedback
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            ConfirmatorManager.shared.showError(error, title: "Navigation Failed")
            print("Failed to navigate to path: \(path), error: \(error)")
        }
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
                                ConfirmatorManager.shared.showError(error, title: "Failed to Save File")
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
                                    ConfirmatorManager.shared.showError(error, title: "Failed to Save File")
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
            ConfirmatorManager.shared.showError(error, title: "Failed to Open File")
        }
    }
    
    func presentFilePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = documentPickerDelegate
        picker.allowsMultipleSelection = true
        
        // Enable access to more file types and locations
        picker.shouldShowFileExtensions = true
        
        documentPickerDelegate.onPick = { urls in
            Task {
                await uploadFiles(urls: urls)
            }
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(picker, animated: true)
        }
    }
    
    func uploadFiles(urls: [URL]) async {
        guard let sftp = sftp else { 
            ConfirmatorManager.shared.showError("SFTP connection not available", title: "Upload Failed")
            return 
        }
        
        await MainActor.run {
            isUploading = true
            uploadProgress = 0
        }
        
        let totalFiles = urls.count
        var completedFiles = 0
        var failedFiles: [String] = []
        
        for url in urls {
            let fileName = url.lastPathComponent
            let destinationPath = "\(currentDirectory)/\(fileName)"
            var accessGranted = false
            
            do {
                // Debug: Check if file is accessible
                print("Attempting to upload: \(url.path)")
                print("File exists: \(FileManager.default.fileExists(atPath: url.path))")
                print("Is security scoped: \(url.hasDirectoryPath)")
                
                // Always try to start accessing security scoped resource for document picker URLs
                accessGranted = url.startAccessingSecurityScopedResource()
                print("Security scoped access granted: \(accessGranted)")
                
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // Read the file data
                let fileData = try Data(contentsOf: url)
                print("Successfully read \(fileData.count) bytes from \(fileName)")
                
                // Upload to SFTP
                try await sftp.withFile(filePath: destinationPath, flags: [.create, .write]) { file in
                    try await file.write(.init(data: fileData))
                }
                
                completedFiles += 1
                let progress = Double(completedFiles) / Double(totalFiles)
                
                await MainActor.run {
                    uploadProgress = progress
                }
                
            } catch {
                print("Error uploading file \(fileName): \(error)")
                
                // Provide more specific error messages
                let errorMessage: String
                if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == 257 {
                    errorMessage = "Permission denied - try selecting files from Files app instead of Photos or other restricted apps"
                } else if (error as NSError).code == 260 {
                    errorMessage = "File not found or moved during upload"
                } else if !accessGranted {
                    errorMessage = "Could not access file - try copying to Files app first, then upload"
                } else {
                    errorMessage = error.localizedDescription
                }
                
                failedFiles.append("\(fileName): \(errorMessage)")
            }
        }
        
        await MainActor.run {
            isUploading = false
            uploadProgress = 0
        }
        
        // Refresh the directory to show uploaded files
        try? await updateDirectories(appending: "")
        
        // Show feedback
        await MainActor.run {
            if failedFiles.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ConfirmatorManager.shared.showError("Upload completed with errors:\n\n" + failedFiles.joined(separator: "\n"), title: "Upload Errors")
            }
        }
    }
}



struct FileInfoSheet: View {
    let filePath: String
    let fileType: String
    let lineCount: Int
    let characterCount: Int
    @Environment(\.dismiss) private var dismiss
    
    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    private var fileSize: String {
        let bytes = characterCount
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section("File Information") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(fileName)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Path")
                        Spacer()
                        Text(filePath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(fileType)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Statistics") {
                    HStack {
                        Text("Lines")
                        Spacer()
                        Text("\(lineCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Characters")
                        Spacer()
                        Text("\(characterCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Size")
                        Spacer()
                        Text(fileSize)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Editor Features") {
                    Label("Syntax highlighting", systemImage: "paintbrush")
                    Label("Line numbers", systemImage: "list.number")
                    Label("Word wrapping", systemImage: "arrow.turn.down.right")
                    Label("Search & replace", systemImage: "magnifyingglass")
                    Label("Adjustable font size", systemImage: "textformat.size")
                }
            }
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
