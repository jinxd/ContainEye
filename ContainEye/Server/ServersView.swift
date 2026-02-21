//
//  ServersView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/26/25.
//


import SwiftUI
import KeychainAccess
import ButtonKit
import Blackbird

struct ServersView: View {
    @BlackbirdLiveModels({try await Server.read(from: $0, matching: .all, orderBy: .descending(\.$id))}) var servers
    @Environment(\.namespace) var namespace
    @Environment(\.blackbirdDatabase) private var db
    @State private var editingServer: Server?


    var body: some View {
        ScrollView{
            VStack{
                // Supporter banner
                SupporterBanner()

                if servers.results.isEmpty {
                    if servers.didLoad {
                        ContentUnavailableView("You don't have any servers yet.", systemImage: "server.rack")
                            .trackView("servers/no-servers")
                    } else {
                        ProgressView()
                            .controlSize(.extraLarge)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 500, maximum: 800))]) {
                        ForEach(servers.results) {server in
                            NavigationLink(value: server) {
                                ServerSummaryView(server: server.liveModel, hostInsteadOfLabel: false)
                                    .contextMenu{
                                        Button("Edit Server", systemImage: "pencil") {
                                            editingServer = server
                                        }

                                        Divider()
                                        Menu {
                                            
                                            AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                                                try keychain().remove(server.credentialKey)
                                                for container in try await server.containers {
                                                    try await container.delete(from: db!)
                                                }
                                                await Snippet.deleteForServer(credentialKey: server.credentialKey, in: db!)
                                                try await server.delete(from: db!)
                                                try keychain().remove(server.credentialKey)
                                            }

                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            .matchedTransitionSource(id: server.id, in: namespace!)
                            .buttonStyle(.plain)
                        }
                    }
                    .trackView("servers")
                }

                Spacer()
#if !os(macOS)
                .drawingGroup()
#endif
                NavigationLink("Learn more", value: URL.servers)
                    .matchedTransitionSource(id: URL.servers, in: namespace!)
                
            }
            .padding()
        }
        .defaultScrollAnchor((servers.didLoad && servers.results.isEmpty) ? .center : .top)
        .animation(.smooth, value: servers.results)
        .sheet(item: $editingServer) { server in
            if let credential = loadCredential(for: server.credentialKey) {
                EditServerView(credential: credential)
                    .confirmator()
            } else {
                Text("Failed to load server credentials")
                    .padding()
            }
        }
        .task{
            while !Task.isCancelled {
                for server in servers.results {
                    if !server.isConnected {try? await server.connect()}
                    await server.fetchServerStats()
                }
                if servers.results.isEmpty {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
    
    private func loadCredential(for key: String) -> Credential? {
        do {
            guard let data = try keychain().getData(key) else {
                print("No data found for credential key \(key)")
                return nil
            }
            return try JSONDecoder().decode(Credential.self, from: data)
        } catch {
            print("Failed to load credential for key \(key): \(error)")
            return nil
        }
    }
}


#Preview {
    ServersView()
}
