//
//  ServerDetailView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//

import SwiftUI

struct ServerDetailView: View {
    let server: Server
    @Environment(\.namespace) var namespace

    var body: some View {
        ScrollView{
            VStack {
                ServerSummaryView(server: server, hostInsteadOfLabel: true)
                    .padding(.horizontal)
                    .onAppear{
                        Task{
                            await server.fetchDockerStats()
                            try? await Task.sleep(for: .seconds(1))
                            server.dockerUpdatesPaused = true
                        }
                    }
                    .onDisappear{
                        guard !server.containers.contains(where: {$0.fetchDetailedUpdates}) else { return }
                        print("on disappear", "pausing docker updates")
                        server.dockerUpdatesPaused = true
                    }
                    .animation(.spring, value: server.cpuUsage)
                    .animation(.spring, value: server.memoryUsage)
                    .animation(.spring, value: server.ioWait)
                    .animation(.spring, value: server.diskUsage)
                    .navigationTitle(server.credential.label)
                #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif

                if server.containers.isEmpty {
                    ContentUnavailableView(server.containersLoaded ? "You don't have any containers" :"Loading your containers...", systemImage: "shippingbox")
                } else {
                    Text("Container")
                    ForEach(server.containers) { container in
                        NavigationLink(value: container){
                            VStack{
                                Text(container.name)
                                HStack {
                                    GridRow {
                                        GridItemView.Percentage(title: "CPU Usage", percentage: container.cpuUsage)
                                        GridItemView.Percentage(title: "Memory Usage", percentage: container.memoryUsage)
                                    }
                                    .tint(
                                        container.status.localizedCaseInsensitiveContains("up") ? Color.accentColor.secondary : Color.primary.secondary
                                    )
                                }
                            }
                            .padding()
                            .background(Color.accentColor.quaternary.quaternary, in: RoundedProgressRectangle(cornerRadius: 15))
                            .padding(.horizontal)
                            #if !os(macOS)
                            .navigationTransition(.zoom(sourceID: container.id, in: namespace!))
                            #endif
                        }
                        .matchedTransitionSource(id: container.id, in: namespace!)
                        .buttonStyle(.plain)
                    }
                }
            }
            .animation(.spring, value: server.containers)
            .zIndex(-1)
        }
    }
}

#Preview {
    ServerDetailView(server: Server(credential: Credential(key: UUID().uuidString, label: "My fancy new server", host: "", port: 0, username: "", password: "")))
}
