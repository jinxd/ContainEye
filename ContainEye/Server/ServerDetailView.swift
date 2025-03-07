//
//  ServerDetailView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//

import SwiftUI
import Blackbird

@MainActor
class CurrentServerId{
    static let shared = CurrentServerId()
    var currentServerId: String?

    func setCurrentServerId(_ id: String?){
        self.currentServerId = id
    }
}

struct ServerDetailView: View {
    @BlackbirdLiveModels({try await Container.read(from: $0, matching: .all)}) var containers
    @BlackbirdLiveModel var server: Server?
    @Environment(\.namespace) var namespace

    init(server: BlackbirdLiveModel<Server>, id serverId: String) {
        self._server = server
        self._containers = .init({try await Container.read(from: $0, matching: \.$serverId == serverId)})
    }



    var body: some View {
        if let server {
            ScrollView{
                VStack {
                    ServerSummaryView(server: server, hostInsteadOfLabel: true)
                        .padding(.horizontal)
                        .animation(.spring, value: server.cpuUsage)
                        .animation(.spring, value: server.memoryUsage)
                        .animation(.spring, value: server.ioWait)
                        .animation(.spring, value: server.diskUsage)
                        .navigationTitle(server.credential?.label ?? "")
#if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif

                    if containers.results.isEmpty {
                        ContentUnavailableView((containers.didLoad) ? "You don't have any containers" :"Loading your containers...", systemImage: "shippingbox")
                    } else {
                        Text("Container")
                        ForEach(containers.results) { container in
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
                .zIndex(-1)
            }
            .onAppear{
                CurrentServerId.shared.setCurrentServerId(server.id)
            }
            .task{
                while !Task.isCancelled {
                    if !server.isConnected {try? await server.connect()}
                    await server.fetchServerStats()
                    await server.fetchDockerStats()
                }
            }
        }
    }
}

#Preview {
    ServerDetailView(server: Server(credentialKey: UUID().uuidString).liveModel, id: UUID().uuidString)
}
