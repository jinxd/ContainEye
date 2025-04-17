//
//  FileSummaryView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/27/25.
//


import ButtonKit
import SwiftUI
@preconcurrency import Citadel

struct FileSummaryView: View {
    @Environment(\.editMode) var editMode
    let sftp: SFTPClient
    let credential: Credential
    let file: SFTPItem
    let updateDirectory: (String) async throws -> Void
    let openFile: (String,_ mode: OpenDocumentMode) async throws -> Void

    @State private var filename = ""

    var body: some View {
        AsyncButton{
            if file.isDirectory {
                try await updateDirectory(file.file.filename)
            } else {
                try await openFile(file.path, .ask)
            }
        } label: {
            HStack {
                Text(file.file.filename)
                Spacer()
                if !file.isDirectory {
                    VStack(alignment: .trailing){
                        Text((file.file.attributes.size ?? 0)/1024, format: .number) + Text("KB")
                        Text(file.file.attributes.accessModificationTime?.modificationTime ?? .now, format: .dateTime)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .swipeActions {
            AsyncButton("Rename", systemImage: "pencil.line") {
                try await file.rename(to: ConfirmatorManager.shared.ask("What do you want to rename this \(file.isDirectory ? "directory" : "file") (\(file.file.filename)) to?"), using: sftp)
                try await updateDirectory("")
            }
            AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                try await file.delete(using: sftp, credential: credential)
                try await updateDirectory("")
            }
        }
        .contextMenu {
            AsyncButton {
                if file.isDirectory {
                    try await updateDirectory(file.file.filename)
                } else {
                    try await openFile(file.path, .asText)
                }
            } label: {
                Label("Open", systemImage: "folder")
            }
            
            if !file.isDirectory {
                AsyncButton {
                    try await openFile(file.path, .asText)
                } label: {
                    Label("Open as Text", systemImage: "text.alignleft")
                }
                
                AsyncButton {
                    try await openFile(file.path, .export)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            
            AsyncButton {
                try await file.rename(to: ConfirmatorManager.shared.ask("What do you want to rename this \(file.isDirectory ? "directory" : "file") (\(file.file.filename)) to?"), using: sftp)
                try await updateDirectory("")
            } label: {
                Label("Rename", systemImage: "pencil.line")
            }
            
            AsyncButton(role: .destructive) {
                try await file.delete(using: sftp, credential: credential)
                try await updateDirectory("")
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
