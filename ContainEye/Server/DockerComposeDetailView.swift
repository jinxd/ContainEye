//
//  DockerComposeDetailView.swift
//  ContainEye
//
//  Created by Claude on 6/22/25.
//

import SwiftUI
import ButtonKit
import Blackbird

struct DockerComposeDetailView: View {
    let composeFile: DockerCompose
    let server: Server
    @State private var isOperating = false
    @State private var fileContent = ""
    @State private var isLoadingContent = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header info
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(composeFile.projectName)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text(composeFile.filePath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            HStack {
                                Circle()
                                    .fill(composeFile.isRunning ? .green : .gray)
                                    .frame(width: 12, height: 12)
                                
                                Text(composeFile.isRunning ? "Running" : "Stopped")
                                    .font(.headline)
                                    .foregroundColor(composeFile.isRunning ? .green : .secondary)
                            }
                            
                            if let lastModified = composeFile.lastModified {
                                Text("Modified \(lastModified, style: .relative)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(.tertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Services section
                if !composeFile.serviceList.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Services (\(composeFile.serviceList.count))")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 200))
                        ], spacing: 8) {
                            ForEach(composeFile.serviceList, id: \.self) { service in
                                HStack {
                                    Image(systemName: "cube.box")
                                        .foregroundColor(.blue)
                                    Text(service)
                                        .font(.body)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.blue.opacity(0.1))
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding()
                    .background(.tertiary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Control buttons
                VStack(alignment: .leading, spacing: 12) {
                    Text("Actions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        if composeFile.isRunning {
                            AsyncButton("Stop") {
                                isOperating = true
                                try await server.stopDockerCompose(at: composeFile.filePath)
                                isOperating = false
                            }
                            .buttonStyle(.bordered)
                            .disabled(isOperating)
                            
                            AsyncButton("Restart") {
                                isOperating = true
                                try await server.restartDockerCompose(at: composeFile.filePath)
                                isOperating = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isOperating)
                        } else {
                            AsyncButton("Start") {
                                isOperating = true
                                try await server.startDockerCompose(at: composeFile.filePath)
                                isOperating = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isOperating)
                        }
                        
                        AsyncButton("Pull Images") {
                            isOperating = true
                            try await server.pullDockerComposeImages(at: composeFile.filePath)
                            isOperating = false
                        }
                        .buttonStyle(.bordered)
                        .disabled(isOperating)
                        
                        if isOperating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Spacer()
                    }
                }
                .padding()
                .background(.tertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // File content section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("File Content")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        AsyncButton("Reload") {
                            await loadFileContent()
                        }
                        .controlSize(.small)
                        .disabled(isLoadingContent)
                    }
                    
                    if isLoadingContent {
                        ProgressView("Loading file content...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if fileContent.isEmpty {
                        Text("Tap 'Reload' to view file content")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ScrollView {
                            Text(fileContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(maxHeight: 300)
                        .background(.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
                .background(.tertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .navigationTitle("Docker Compose")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFileContent()
            
            // Poll for updates
            while !Task.isCancelled {
                if !server.isConnected {
                    try? await server.connect()
                }
                // Refresh compose file data
                await server.fetchDockerComposeFiles()
                
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    
    private func loadFileContent() async {
        isLoadingContent = true
        defer { isLoadingContent = false }
        
        do {
            let content = try await server.execute("cat '\(composeFile.filePath)'")
            await MainActor.run {
                fileContent = content
            }
        } catch {
            await MainActor.run {
                fileContent = "Error loading file: \(error.localizedDescription)"
            }
        }
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        DockerComposeDetailView(
            composeFile: DockerCompose(
                serverId: "test",
                filePath: "/home/user/app/docker-compose.yml",
                projectName: "MyApp",
                services: ["web", "database", "redis", "nginx", "worker"],
                lastModified: Date(),
                isRunning: true
            ),
            server: Server(credentialKey: "test")
        )
    }
}