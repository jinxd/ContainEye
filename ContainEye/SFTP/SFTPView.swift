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
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
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
                    
                    // Current path display and input
                    HStack {
                        Text("Path:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            pathInput = currentDirectory
                            showingPathInput = true
                        }) {
                            Text(currentDirectory.isEmpty ? "/" : currentDirectory)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        Button("Go") {
                            pathInput = currentDirectory
                            showingPathInput = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
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
                        VStack {
                            if isUploading {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("Uploading...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(uploadProgress * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: uploadProgress)
                                        .progressViewStyle(.linear)
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                            
                            HStack {
                                Button {
                                    presentFilePicker()
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.up.doc")
                                        Text("Upload Files")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isUploading)
                                
                                Menu {
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
                                    HStack {
                                        Image(systemName: "plus")
                                        Text("Create")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isUploading)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
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
            .alert("Navigate to Path", isPresented: $showingPathInput) {
                TextField("Enter path", text: $pathInput)
                Button("Cancel", role: .cancel) { }
                Button("Go") {
                    Task {
                        await navigateToPath(pathInput)
                    }
                }
            } message: {
                Text("Enter the full path you want to navigate to")
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
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
            Task { @MainActor in
                showError("Failed to navigate to path '\(path)': \(error.localizedDescription)")
            }
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
                                Task { @MainActor in
                                    showError("Failed to save file: \(error.localizedDescription)")
                                }
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
                                    Task { @MainActor in
                                        showError("Failed to save file: \(error.localizedDescription)")
                                    }
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
            Task { @MainActor in
                showError("Failed to open file: \(error.localizedDescription)")
            }
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
            Task { @MainActor in
                showError("SFTP connection not available")
            }
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
                Task { @MainActor in
                    showError("Upload completed with errors:\n\n" + failedFiles.joined(separator: "\n"))
                }
            }
        }
    }
    
    @MainActor
    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
    }
}


