//
//  PowerfulTextEditorView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 6/28/25.
//


import ButtonKit
import SwiftUI

struct PowerfulTextEditorView: View {
    @Binding var text: String
    let filePath: String
    let onSave: () async throws -> Void
    let onClose: () async throws -> Void

    var body: some View {
        TextEditor(text: $text)
            .monospaced()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                HStack {
                    AsyncButton {
                        try await onClose()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.red)
                    Spacer()

                    AsyncButton {
                        try await onSave()
                    } label: {
                        Label("Save", systemImage: "opticaldiscdrive")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                }
            }
    }
}

#Preview(traits: .sampleData) {
    @Previewable @State var text = """
    version: \"3\"
    services:
      web:
        image: nginx:latest
    """
    return PowerfulTextEditorView(
        text: $text,
        filePath: "/srv/app/docker-compose.yml",
        onSave: {},
        onClose: {}
    )
}
