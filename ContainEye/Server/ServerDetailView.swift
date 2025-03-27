//
//  ServerDetailView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//

import SwiftUI
import ButtonKit
import Blackbird


struct ServerDetailView: View {
    @BlackbirdLiveModels({try await Container.read(from: $0, matching: .all)}) var containers
    @BlackbirdLiveModels({try await Process.read(from: $0, matching: .all)}) var processes
    @BlackbirdLiveModel var server: Server?
    @Environment(\.namespace) var namespace
    @Environment(\.blackbirdDatabase) var db

    init(server: BlackbirdLiveModel<Server>, id serverId: String) {
        self._server = server
        self._containers = .init({try await Container.read(from: $0, matching: \.$serverId == serverId)})
        self._processes = .init({try await Process.read(from: $0, matching: \.$serverId == serverId)})
    }



    var body: some View {
        if let server {
            ScrollView{
                VStack {
                    ServerSummaryView(server: server.liveModel, hostInsteadOfLabel: true)
                        .padding(.horizontal)
                        .animation(.spring, value: server.cpuUsage)
                        .animation(.spring, value: server.memoryUsage)
                        .animation(.spring, value: server.ioWait)
                        .animation(.spring, value: server.diskUsage)
                        .navigationTitle(server.credential?.label ?? "")
#if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif
                    VStack{
                        if processes.results.isEmpty{
                            ContentUnavailableView("Processes not yet loaded", systemImage: "rectangle.stack.badge.person.crop", description: Text("Wait a second..."))
                        } else {
                            VStack {
                                Text("Processes")
                                ScrollView{
                                    Grid{
                                        GridRow{
                                            AsyncButton("Pid") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .pid ? .pidReversed : .pid
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            AsyncButton("Command") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .command ? .commandReversed : .command
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            AsyncButton("User") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .user ? .userReversed : .user
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            AsyncButton("CPU") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .cpu ? .cpuReversed : .cpu
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            AsyncButton("Memory") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .memory ? .memoryReversed : .memory
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                        }
                                        ForEach(processes.results) { process in
                                            GridRow{
                                                Text(process.pid, format: .number)
                                                Text(process.command)
                                                Text(process.user)
                                                Text(process.cpuUsage, format: .number)
                                                Text(process.memoryUsage, format: .number)
                                            }
                                            .lineLimit(2)
                                            .overlay{
                                                Rectangle()
                                                    .fill(.gray.opacity(0.01))
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                    .contentShape(.rect)
                                                    .contextMenu{
                                                        Text(process.pid, format: .number)
                                                        Text(process.command)
                                                        Text(process.user)
                                                        Text(process.cpuUsage, format: .number)
                                                        Text(process.memoryUsage, format: .number)
                                                        AsyncButton("Kill Process", role: .destructive) {
                                                            let _ = try await server.execute("kill \(process.pid)")
                                                            await server.fetchProcesses()
                                                        }
                                                    }
                                            }
                                            Divider()
                                        }
                                    }
                                    .gridCellAnchor(.topLeading)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.accent.opacity(0.1), in: RoundedProgressRectangle(cornerRadius: 15))
                    .padding()
                    .containerRelativeFrame(.vertical, count: 2, spacing: 10)
                    if containers.results.isEmpty {
                        ContentUnavailableView((containers.didLoad) ? "No cached containers" :"Fetching servers from cache...", systemImage: "shippingbox", description: Text("ContainEye is loading them for you."))
                    } else {
                        Text("Container")
                        ForEach(containers.results) { container in
                            NavigationLink(value: container){
                                ContainerSummaryView(container: container.liveModel)
                            }
                            .matchedTransitionSource(id: container.id, in: namespace!)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .zIndex(-1)
            }
            .task{
                while !Task.isCancelled {
                    if !server.isConnected {try? await server.connect()}
                    await server.fetchServerStats()
                    await server.fetchDockerStats()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
}

#Preview {
    ServerDetailView(server: Server(credentialKey: UUID().uuidString).liveModel, id: UUID().uuidString)
}
