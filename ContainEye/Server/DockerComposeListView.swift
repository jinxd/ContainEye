//
//  DockerComposeListView.swift
//  ContainEye
//
//  Created by Claude on 6/22/25.
//

import SwiftUI
import Blackbird

struct DockerComposeListView: View {
    @BlackbirdLiveModels({try await DockerCompose.read(from: $0, matching: .all)}) var dockerComposeFiles
    let server: Server
    
    init(server: Server, id serverId: String) {
        self.server = server
        self._dockerComposeFiles = .init({
            try await DockerCompose.read(from: $0, matching: \.$serverId == serverId)
        })
    }
    
    var body: some View {
        Group {
            if dockerComposeFiles.results.isEmpty {
                ContentUnavailableView(
                    "No Docker Compose Files",
                    systemImage: "doc.text",
                    description: Text("No compose files detected on this server")
                )
            } else {
                List {
                    ForEach(dockerComposeFiles.results) { composeFile in
                        NavigationLink {
                            DockerComposeDetailView(composeFile: composeFile, server: server)
                        } label: {
                            DockerComposeRowView(composeFile: composeFile, server: server)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Docker Compose")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await server.fetchDockerComposeFiles()
        }
        .task {
            // Poll for updates while view is active
            while !Task.isCancelled {
                if !server.isConnected {
                    try? await server.connect()
                }
                await server.fetchDockerComposeFiles()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

#Preview {
    NavigationStack {
        DockerComposeListView(
            server: Server(credentialKey: "test"),
            id: "test"
        )
    }
}