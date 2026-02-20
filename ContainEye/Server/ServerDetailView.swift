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
    @BlackbirdLiveModels({try await DockerCompose.read(from: $0, matching: .all)}) var dockerComposeFiles
    @BlackbirdLiveModel var server: Server?
    @Environment(\.namespace) var namespace
    @Environment(\.blackbirdDatabase) var db
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearContainersAlert = false

    init(server: BlackbirdLiveModel<Server>, id serverId: String) {
        self._server = server
        self._containers = .init({try await Container.read(from: $0, matching: \.$serverId == serverId)})
        self._processes = .init({try await Process.read(from: $0, matching: \.$serverId == serverId)})
        self._dockerComposeFiles = .init({try await DockerCompose.read(from: $0, matching: \.$serverId == serverId)})
    }



    var body: some View {
        if let server {
            ScrollView{
                VStack {
                    serverSummarySection(server: server)
                    processesSection(server: server)
                    containersSection
                    dockerComposeSection(server: server)
                }
                .zIndex(-1)
            }
            .task{
                while !Task.isCancelled {
                    if !server.isConnected {try? await server.connect()}
                    await server.fetchServerStats()
                    await server.fetchDockerStats()
                    await server.fetchDockerComposeFiles()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .alert("Clear Cached Containers", isPresented: $showingClearContainersAlert) {
                Button(role: .cancel) { }
                Button("Clear", role: .destructive) {
                    Task {
                        try? await server.clearCachedContainers()
                    }
                }
            } message: {
                Text("This will remove all cached container data for this server. The data will be refreshed from the server.")
            }
            .trackView("servers/detail")
        }
    }
    
    @ViewBuilder
    private func serverSummarySection(server: Server) -> some View {
        VStack(spacing: 12) {
            ServerSummaryView(server: server.liveModel, hostInsteadOfLabel: true)
            
            // Quick actions
            HStack(spacing: 16) {
                Button(action: {
                    if let credential = server.credential {
                        TerminalNavigationManager.shared.navigateToTerminal(with: credential)
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "terminal")
                        Text("Open Terminal")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.horizontal)
        .animation(.spring, value: server.cpuUsage)
        .animation(.spring, value: server.memoryUsage)
        .animation(.spring, value: server.ioWait)
        .animation(.spring, value: server.diskUsage)
        .navigationTitle(server.credential?.label ?? "")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
    
    @ViewBuilder
    private func processesSection(server: Server) -> some View {
        VStack{
            if processes.results.isEmpty{
                ContentUnavailableView("Processes not yet loaded", systemImage: "rectangle.stack.badge.person.crop", description: Text("Wait a second..."))
            } else {
                VStack {
                    HStack {
                        Text("Processes")
                        Spacer()
                        NavigationLink("View All") {
                            ProcessListView(server: server.liveModel, id: server.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    processGrid(server: server)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.accent.opacity(0.1), in: RoundedProgressRectangle(cornerRadius: 15))
        .padding()
        .containerRelativeFrame(.vertical, count: 2, spacing: 10)
    }
    
    @ViewBuilder
    private func processGrid(server: Server) -> some View {
        ScrollView{
            Grid{
                processHeaderRow(server: server)
                ForEach(processes.results.prefix(10)) { process in
                    processRow(process: process, server: server)
                    Divider()
                }
            }
            .gridCellAnchor(.topLeading)
        }
    }
    
    @ViewBuilder
    private func processHeaderRow(server: Server) -> some View {
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
        .gridCellAnchor(.topLeading)
    }
    
    @ViewBuilder
    private func processRow(process: Process, server: Server) -> some View {
        GridRow{
            Text(process.pid, format: .number)
            Text(process.command)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(process.user)
            Text(process.cpuUsage, format: .number)
            Text(process.memoryUsage, format: .number)
        }
        .gridCellAnchor(.topLeading)
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
    }
    
    @ViewBuilder
    private var containersSection: some View {
        VStack {
            HStack {
                Text("Containers")
                    .font(.headline)

                if let server = server, server.containerRuntime != nil {
                    Label(server.containerRuntimeDisplayName, systemImage: server.containerRuntimeIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }

                Spacer()
                AsyncButton("Clear Cache", role: .destructive) {
                    showingClearContainersAlert = true
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            
            if containers.results.isEmpty {
                ContentUnavailableView((containers.didLoad) ? "No cached containers" :"Fetching servers from cache...", systemImage: "shippingbox", description: Text("ContainEye is loading them for you."))
            } else {
                ForEach(containers.results) { container in
                    NavigationLink(value: container){
                        ContainerSummaryView(container: container.liveModel)
                    }
                    .matchedTransitionSource(id: container.id, in: namespace!)
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    @ViewBuilder
    private func dockerComposeSection(server: Server) -> some View {
        VStack {
            HStack {
                Text("Docker Compose Files")
                    .font(.headline)
                Spacer()
                if dockerComposeFiles.results.count > 3 {
                    NavigationLink("View All") {
                        DockerComposeListView(server: server, id: server.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)
            
            if dockerComposeFiles.results.isEmpty {
                ContentUnavailableView("No Docker Compose files found", systemImage: "doc.text", description: Text("No compose files detected on the server"))
                    .padding()
            } else {
                let displayedFiles = Array(dockerComposeFiles.results.prefix(3))
                let remainingCount = max(0, dockerComposeFiles.results.count - 3)
                
                ForEach(displayedFiles) { composeFile in
                    NavigationLink {
                        DockerComposeDetailView(composeFile: composeFile, server: server)
                    } label: {
                        DockerComposeRowView(composeFile: composeFile, server: server)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    
                    if composeFile.id != displayedFiles.last?.id {
                        Divider()
                    }
                }
                
                if remainingCount > 0 {
                    Divider()
                    NavigationLink {
                        DockerComposeListView(server: server, id: server.id)
                    } label: {
                        HStack {
                            Text("...and \(remainingCount) more")
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.secondary.opacity(0.1), in: RoundedProgressRectangle(cornerRadius: 15))
        .padding()
    }
}

#Preview {
    ServerDetailView(server: Server(credentialKey: UUID().uuidString).liveModel, id: UUID().uuidString)
}
