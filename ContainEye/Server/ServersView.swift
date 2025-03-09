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
    @Binding var sheet : ContentView.Sheet?
    @Environment(\.namespace) var namespace
    @Environment(\.blackbirdDatabase) private var db


    var body: some View {
        ScrollView{
            VStack{
                if servers.results.isEmpty {
                    if servers.didLoad {
                        ContentUnavailableView("You don't have any servers yet.", systemImage: "server.rack")
                    } else {
                        ProgressView()
                            .controlSize(.extraLarge)
                    }
                }


                LazyVGrid(columns: [GridItem(.adaptive(minimum: 500, maximum: 800))]) {
                    ForEach(servers.results) {server in
                        NavigationLink(value: server) {
                            ServerSummaryView(server: server, hostInsteadOfLabel: false)
                                .contextMenu{
                                    Menu {
                                        AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                                            try keychain().remove(server.credentialKey)
                                            for container in try await server.containers {
                                                try await container.delete(from: db!)
                                            }
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
                        .onTapGesture {
                            CurrentServerId.shared.setCurrentServerId(server.id)
                        }
                    }
                }

                Spacer()
#if !os(macOS)
                .drawingGroup()
#endif
                NavigationLink("Learn more", value: Help.servers)
                    .matchedTransitionSource(id: Help.servers, in: namespace!)
                
            }
            .padding()
            .padding(.top, 50)
        }
        .animation(.smooth, value: servers.results)
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
        .refreshable {
            for server in servers.results {
                await server.fetchServerStats()
            }
        }
    }
}


#Preview {
    ServersView(sheet: .constant(nil))
}
