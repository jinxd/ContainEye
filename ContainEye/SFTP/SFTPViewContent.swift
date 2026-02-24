import ButtonKit
import SwiftUI
@preconcurrency import Citadel

struct SFTPConnectedContentView: View {
    @Binding var selectedCredential: Credential?
    let credential: Credential
    let sftp: SFTPClient?
    @Binding var openedFile: String?
    @Binding var fileContent: String
    let files: [SFTPItem]?
    let showHiddenFiles: Bool
    let currentDirectory: String
    let isLoading: Bool
    let isUploading: Bool
    let uploadProgress: Double
    let onGoHome: () async throws -> Void
    let onToggleHiddenFiles: () -> Void
    let onStartPathEditing: () -> Void
    let onUpdateDirectories: (String) async throws -> Void
    let onPresentFilePicker: () -> Void
    let onCreateDirectory: () async -> Void
    let onCreateFile: () async -> Void
    let onOpenFile: (String, OpenDocumentMode) async throws -> Void
    let onEditorSave: () async throws -> Void
    let onEditorClose: () async throws -> Void

    var body: some View {
        VStack {
            if let openedFile {
                PowerfulTextEditorView(
                    text: $fileContent,
                    filePath: openedFile,
                    onSave: onEditorSave,
                    onClose: onEditorClose
                )
            } else if let sftp {
                SFTPBrowserHeaderView(
                    selectedCredential: $selectedCredential,
                    credential: credential,
                    showHiddenFiles: showHiddenFiles,
                    currentDirectory: currentDirectory,
                    onGoHome: onGoHome,
                    onToggleHiddenFiles: onToggleHiddenFiles,
                    onStartPathEditing: onStartPathEditing
                )

                Form {
                    let visibleFiles = (files ?? []).filter { showHiddenFiles || !$0.file.filename.hasPrefix(".") }

                    Section {
                        if currentDirectory != "/" {
                            AsyncButton {
                                try await onUpdateDirectories("..")
                            } label: {
                                SFTPActionRow(
                                    icon: "arrow.up",
                                    title: "Go Up",
                                    subtitle: "Navigate to parent directory",
                                    trailingIcon: "chevron.up",
                                    tint: .accent
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            onPresentFilePicker()
                        } label: {
                            SFTPActionRow(
                                icon: "icloud.and.arrow.up",
                                title: "Upload Files",
                                subtitle: "Select files from your device",
                                tint: .accent
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isUploading)
                        .opacity(isUploading ? 0.6 : 1.0)

                        AsyncButton {
                            await onCreateDirectory()
                        } label: {
                            SFTPActionRow(
                                icon: "folder.badge.plus",
                                title: "New Folder",
                                subtitle: "Create a new directory",
                                tint: .orange
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isUploading)
                        .opacity(isUploading ? 0.6 : 1.0)

                        AsyncButton {
                            await onCreateFile()
                        } label: {
                            SFTPActionRow(
                                icon: "doc.badge.plus",
                                title: "New File",
                                subtitle: "Create a new file",
                                tint: .green
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isUploading)
                        .opacity(isUploading ? 0.6 : 1.0)
                    }

                    if !visibleFiles.isEmpty {
                        Section("Files & Folders") {
                            ForEach(visibleFiles, id: \.id) { file in
                                FileSummaryView(sftp: sftp, credential: credential, file: file) { append in
                                    try await onUpdateDirectories(append)
                                } openFile: { path, mode in
                                    try await onOpenFile(path, mode)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    try? await onUpdateDirectories("")
                }
                .safeAreaInset(edge: .bottom) {
                    if isUploading {
                        SFTPUploadProgressView(uploadProgress: uploadProgress)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .redacted(reason: isLoading ? .invalidated : [])
    }
}

private struct SFTPBrowserHeaderView: View {
    @Binding var selectedCredential: Credential?
    let credential: Credential
    let showHiddenFiles: Bool
    let currentDirectory: String
    let onGoHome: () async throws -> Void
    let onToggleHiddenFiles: () -> Void
    let onStartPathEditing: () -> Void

    var body: some View {
        VStack {
            HStack {
                AsyncButton {
                    try await onGoHome()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(
                                colors: [.accent, .accent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(.circle)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                }

                Picker("Server", selection: $selectedCredential) {
                    let allCredentials = keychain().allKeys().compactMap { keychain().getCredential(for: $0) }
                    ForEach(allCredentials, id: \.key) { serverCredential in
                        Text(serverCredential.label)
                            .tag(Optional(serverCredential))
                    }
                }
                .pickerStyle(.segmented)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )

                Button {
                    onToggleHiddenFiles()
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

                Button {
                    onStartPathEditing()
                } label: {
                    HStack {
                        Text(currentDirectory.isEmpty ? "/" : currentDirectory)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.accent)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .stroke(.accent.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
}

private struct SFTPUploadProgressView: View {
    let uploadProgress: Double

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(.accent)
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
                    .foregroundStyle(.accent)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.accent.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.accent, .accent.opacity(0.7)],
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
                .fill(.accent.opacity(0.05))
                .stroke(.accent.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

struct SFTPServerSelectionContentView: View {
    let credentials: [Credential]
    let servers: [Server]
    let onSelectCredential: (Credential) -> Void

    var body: some View {
        if credentials.isEmpty {
            ContentUnavailableView("You don't have any servers yet.", systemImage: "server.rack")
                .trackView("sftp/no-servers")
        } else {
            VStack {
                VStack {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 60))
                        .foregroundStyle(.accent)
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

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(credentials, id: \.key) { credential in
                        Button {
                            onSelectCredential(credential)
                        } label: {
                            VStack {
                                if let server = servers.first(where: { $0.credentialKey == credential.key }) {
                                    OSIconView(server: server, size: 32)
                                } else {
                                    Image(systemName: "server.rack")
                                        .font(.title)
                                        .foregroundStyle(.accent)
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
                                    .fill(.accent.opacity(0.05))
                                    .stroke(.accent.opacity(0.2), lineWidth: 1)
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
