//
//  ProcessListView.swift
//  ContainEye
//
//  Created by Claude on 6/22/25.
//

import SwiftUI
import ButtonKit
import Blackbird

struct ProcessListView: View {
    @BlackbirdLiveModels({try await Process.read(from: $0, matching: .all)}) var processes
    @BlackbirdLiveModel var server: Server?
    @Environment(\.blackbirdDatabase) var db
    @State private var searchText = ""
    @State private var showingKillConfirmation = false
    @State private var processToKill: Process?
    @State private var isRefreshing = false
    
    init(server: BlackbirdLiveModel<Server>, id serverId: String) {
        self._server = server
        self._processes = .init({try await Process.read(from: $0, matching: \.$serverId == serverId)})
    }
    
    var filteredProcesses: [Process] {
        if searchText.isEmpty {
            return processes.results
        } else {
            return processes.results.filter { process in
                process.command.localizedCaseInsensitiveContains(searchText) ||
                process.user.localizedCaseInsensitiveContains(searchText) ||
                String(process.pid).contains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if let server {
                    VStack {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search processes...", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal)
                        
                        // Refresh button
                        HStack {
                            Spacer()
                            AsyncButton(action: {
                                isRefreshing = true
                                await server.fetchProcesses()
                                isRefreshing = false
                            }) {
                                HStack {
                                    if isRefreshing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Refresh")
                                }
                            }
                            .disabled(isRefreshing)
                            .padding(.horizontal)
                        }
                        
                        if filteredProcesses.isEmpty {
                            if searchText.isEmpty {
                                ContentUnavailableView(
                                    "Processes not yet loaded",
                                    systemImage: "rectangle.stack.badge.person.crop",
                                    description: Text("Wait a second...")
                                )
                            } else {
                                ContentUnavailableView(
                                    "No matching processes",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try a different search term")
                                )
                            }
                        } else {
                            // Process list
                            ScrollView {
                                LazyVStack {
                                    // Header row with adaptive layout
                                    GeometryReader { geometry in
                                        HStack(spacing: 8) {
                                            AsyncButton("PID") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .pid ? .pidReversed : .pid
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            .frame(width: geometry.size.width * 0.12, alignment: .leading)
                                            
                                            AsyncButton("Command") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .command ? .commandReversed : .command
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            .frame(width: geometry.size.width * 0.45, alignment: .leading)
                                            
                                            AsyncButton("User") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .user ? .userReversed : .user
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            .frame(width: geometry.size.width * 0.15, alignment: .leading)
                                            
                                            AsyncButton("CPU") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .cpu ? .cpuReversed : .cpu
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            .frame(width: geometry.size.width * 0.14, alignment: .trailing)
                                            
                                            AsyncButton("Memory") {
                                                var server = server
                                                server.processSortOrder = server.processSortOrder == .memory ? .memoryReversed : .memory
                                                try await server.write(to: db!)
                                                await server.fetchProcesses()
                                            }
                                            .frame(width: geometry.size.width * 0.14, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                        .background(Color.secondary.opacity(0.1))
                                        .font(.caption.bold())
                                    }
                                    .frame(height: 32)
                                    
                                    ForEach(filteredProcesses) { process in
                                        ProcessRowView(
                                            process: process,
                                            onKill: {
                                                processToKill = process
                                                showingKillConfirmation = true
                                            }
                                        )
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Processes")
                    .navigationBarTitleDisplayMode(.inline)
                    .alert("Kill Process", isPresented: $showingKillConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Kill", role: .destructive) {
                            if let processToKill {
                                Task {
                                    await killProcess(processToKill, server: server)
                                }
                            }
                        }
                        Button("Force Kill", role: .destructive) {
                            if let processToKill {
                                Task {
                                    await forceKillProcess(processToKill, server: server)
                                }
                            }
                        }
                    } message: {
                        if let processToKill {
                            Text("Are you sure you want to kill process \(processToKill.pid) (\(processToKill.command))?")
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No server selected",
                        systemImage: "server.rack",
                        description: Text("Select a server to view processes")
                    )
                }
            }
        }
        .task {
            guard let server else { return }
            while !Task.isCancelled {
                if !server.isConnected { try? await server.connect() }
                await server.fetchProcesses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    
    private func killProcess(_ process: Process, server: Server) async {
        do {
            let _ = try await server.execute("kill \(process.pid)")
            await server.fetchProcesses()
        } catch {
            print("Failed to kill process \(process.pid): \(error)")
        }
    }
    
    private func forceKillProcess(_ process: Process, server: Server) async {
        do {
            let _ = try await server.execute("kill -9 \(process.pid)")
            await server.fetchProcesses()
        } catch {
            print("Failed to force kill process \(process.pid): \(error)")
        }
    }
}

struct ProcessRowView: View {
    let process: Process
    let onKill: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                Text(process.pid, format: .number)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: geometry.size.width * 0.12, alignment: .leading)
                
                Text(process.command)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(width: geometry.size.width * 0.45, alignment: .leading)
                
                Text(process.user)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: geometry.size.width * 0.15, alignment: .leading)
                
                Text(process.cpuUsage, format: .number.precision(.fractionLength(1)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(process.cpuUsage > 50 ? .red : .primary)
                    .frame(width: geometry.size.width * 0.14, alignment: .trailing)
                
                Text(process.memoryUsage, format: .number.precision(.fractionLength(1)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(process.memoryUsage > 50 ? .red : .primary)
                    .frame(width: geometry.size.width * 0.14, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy PID") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(process.pid), forType: .string)
                #else
                UIPasteboard.general.string = String(process.pid)
                #endif
            }
            
            Button("Copy Command") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(process.command, forType: .string)
                #else
                UIPasteboard.general.string = process.command
                #endif
            }
            
            Divider()
            
            Button("Kill Process", role: .destructive) {
                onKill()
            }
        }
    }
}

#Preview {
    ProcessListView(server: Server(credentialKey: UUID().uuidString).liveModel, id: UUID().uuidString)
}