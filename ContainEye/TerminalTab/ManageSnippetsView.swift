//
//  ManageSnippetsView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/17/25.
//

import SwiftUI
import Blackbird
import ButtonKit

struct ManageSnippetsView: View {
    @BlackbirdLiveModels({try await Snippet.read(from: $0, matching: .all, orderBy: .descending(\.$lastUse))}) var snippets
    @Environment(\.blackbirdDatabase) var db
    @State private var editingSnippet: Snippet.ID?

    var body: some View {
        if snippets.didLoad {
            if snippets.results.isEmpty {
                ContentUnavailableView("No snippets found", systemImage: "ellipsis.curlybraces", description: Text("Add some snippets by clicking the plus button in the top right corner."))
            } else {
                List{
                    ForEach(snippets.results){snippet in
                        SnippetSummaryView(snippet: snippet.liveModel, editingSnippet: $editingSnippet)
                            .onTapGesture {
                                editingSnippet = snippet.id
                            }
                    }
                    .onDelete { idx in
                        let snippets = snippets.results
                        Task{
                            for id in idx{
                                try await snippets[id].delete(from: db!)
                            }
                        }
                    }
                }
                .navigationTitle("Snippets")
                .toolbar {
                    AsyncButton {
                        let snippet = Snippet(command: "", comment: "", lastUse: .now)
                        try? await snippet.write(to: db!)
                        editingSnippet = snippet.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                }
            }
        }
    }
}

#Preview(traits: .sampleData) {
    ManageSnippetsView()
}

struct SnippetSummaryView: View {
    @BlackbirdLiveModel var snippet: Snippet?
    @Binding var editingSnippet: Snippet.ID?
    @Environment(\.blackbirdDatabase) var db

    var body: some View {
        if let snippet {
            HStack {
                VStack(alignment: .leading){
                    textField(snippet.command, save: { text in
                        var snippet = snippet
                        snippet.command = text
                        Task{try? await snippet.write(to: db!)}
                    })
                    .font(.headline)
                    textField(snippet.comment, save: { text in
                        var snippet = snippet
                        snippet.comment = text
                        Task{try? await snippet.write(to: db!)}
                    })
                    .font(.caption)
                }
                Spacer()
                Text("\(snippet.lastUse, style: .relative) ago")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    func textField(_ text: String, save: @escaping (String) -> Void) -> some View {
        if editingSnippet == snippet?.id {
            InlineTextField(text: text) {text in
                save(text)
            }
        } else {
            Text(text)
        }
    }
}

struct InlineTextField: View {
    @State var text: String
    let onSave: (String) -> Void
    @FocusState private var focused : Bool

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .onChange(of: focused) {
                if !focused {
                    onSave(text)
                }
            }
    }
}
