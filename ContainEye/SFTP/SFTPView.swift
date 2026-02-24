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
    @State private var isLoading = false
    @State private var documentController: UIDocumentInteractionController?
    private let documentDelegate = DocumentInteractionController()
    private let documentPickerDelegate = DocumentPickerController()
    @State private var tempFileURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var showingPathInput = false
    @State private var pathInput = ""
    @Environment(\.terminalNavigationManager) private var terminalManager
    @Environment(\.agenticContextStore) private var contextStore
    
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
                SFTPConnectedContentView(
                    selectedCredential: $credential,
                    credential: credential,
                    sftp: sftp,
                    openedFile: $openedFile,
                    fileContent: $fileContent,
                    files: files,
                    showHiddenFiles: showHiddenFiles,
                    currentDirectory: currentDirectory,
                    isLoading: isLoading,
                    isUploading: isUploading,
                    uploadProgress: uploadProgress,
                    onGoHome: goHome,
                    onToggleHiddenFiles: { showHiddenFiles.toggle() },
                    onStartPathEditing: {
                        pathInput = currentDirectory
                        showingPathInput = true
                    },
                    onUpdateDirectories: updateDirectories,
                    onPresentFilePicker: presentFilePicker,
                    onCreateDirectory: createDirectory,
                    onCreateFile: createFile,
                    onOpenFile: openFile,
                    onEditorSave: saveOpenedFile,
                    onEditorClose: closeOpenedFileEditor
                )
                .task(id: credential) {
                    do {
                        try await goHome()
                    } catch {
                        print(error)
                    }
                }
                .trackView("sftp/connected")
            } else {
                SFTPServerSelectionContentView(
                    credentials: keychain().allKeys().compactMap { keychain().getCredential(for: $0) },
                    servers: servers.results,
                    onSelectCredential: { credential = $0 }
                )
            }
        }
        .alert("Navigate to Path", isPresented: $showingPathInput) {
            TextField("Enter path", text: $pathInput)
            Button(role: .cancel) { }
            Button("Go") {
                navigateToEnteredPath()
            }
        } message: {
            Text("Enter the full path you want to navigate to")
        }
        .onAppear {
            processPendingSFTPEditorRequests()
            updateAgenticContext()
        }
        .onChange(of: terminalManager.sftpEditorOpenRequests.count) { _, _ in
            processPendingSFTPEditorRequests()
        }
        .onChange(of: credential) {
            updateAgenticContext()
        }
        .onChange(of: currentDirectory) {
            updateAgenticContext()
        }
        .onChange(of: openedFile) {
            updateAgenticContext()
        }
    }

    private func updateAgenticContext() {
        if let credential {
            let file = openedFile ?? "(none)"
            let cwd = currentDirectory.isEmpty ? "/" : currentDirectory
            contextStore.set(
                chatTitle: "SFTP \(credential.label)",
                draftMessage: """
                Use this SFTP context:
                - server: \(credential.label)
                - host: \(credential.host)
                - cwd: \(cwd)
                - openedFile: \(file)

                Help me with:
                """
            )
        } else {
            contextStore.set(
                chatTitle: "SFTP",
                draftMessage: "I am in SFTP server selection. Help me with:"
            )
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
        isLoading = true
        defer { isLoading = false}
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

    private func navigateToEnteredPath() {
        Task {
            await navigateToPath(pathInput)
        }
    }

    func saveOpenedFile() async throws {
        guard let openedFile else { return }
        try await sftp?.withFile(filePath: openedFile, flags: [.create, .read, .write]) { file in
            try await file.write(.init(string: fileContent))
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func closeOpenedFileEditor() async throws {
        openedFile = nil
        fileContent.removeAll()
        try await updateDirectories(appending: "")
    }

    func createDirectory() async {
        guard let sftp else { return }
        do {
            let dirName = try await ConfirmatorManager.shared.ask("What do you want to call the new directory?")
            try await sftp.createDirectory(atPath: "\(currentDirectory)/\(dirName)")
            try await updateDirectories(appending: "")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            ConfirmatorManager.shared.showError(error, title: "Failed to Create Directory")
        }
    }

    func createFile() async {
        do {
            let fileName = try await ConfirmatorManager.shared.ask("What do you want to call the new file?")
            try await openFile(path: "\(currentDirectory)/\(fileName)")
        } catch {
            ConfirmatorManager.shared.showError(error, title: "Failed to Create File")
        }
    }

    func openFile(path: String, mode: OpenDocumentMode = .ask) async throws {
        guard let sftp else { return }
        isLoading = true
        defer { isLoading = false }
        
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

#Preview("Server Picker", traits: .sampleData) {
    SFTPView()
}
