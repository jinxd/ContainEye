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

final class DocumentInteractionController: NSObject, UIDocumentInteractionControllerDelegate {
    var onDismiss: (() -> Void)?

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        onDismiss?()
    }
}

final class DocumentPickerController: NSObject, UIDocumentPickerDelegate {
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

struct SFTPActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var trailingIcon: String = "chevron.right"
    var tint: Color = .accent

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: trailingIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}
