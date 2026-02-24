//
//  DockerComposeRowView.swift
//  ContainEye
//
//  Created by Claude on 6/22/25.
//

import SwiftUI
import ButtonKit

struct DockerComposeRowView: View {
    let composeFile: DockerCompose
    let server: Server
    @State private var isOperating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(composeFile.projectName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(composeFile.filePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Status indicator
                    Circle()
                        .fill(composeFile.isRunning ? .green : .gray)
                        .frame(width: 8, height: 8)
                    
                    Text(composeFile.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(composeFile.isRunning ? .green : .secondary)
                }
            }
            
            // Services
            if !composeFile.serviceList.isEmpty {
                HStack {
                    Text("Services:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(composeFile.serviceList, id: \.self) { service in
                                Text(service)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            
            // Control buttons
            HStack(spacing: 8) {
                if composeFile.isRunning {
                    AsyncButton("Stop") {
                        isOperating = true
                        try await server.stopDockerCompose(at: composeFile.filePath)
                        isOperating = false
                    }
                    .controlSize(.small)
                    .disabled(isOperating)
                    
                    AsyncButton("Restart") {
                        isOperating = true
                        try await server.restartDockerCompose(at: composeFile.filePath)
                        isOperating = false
                    }
                    .controlSize(.small)
                    .disabled(isOperating)
                } else {
                    AsyncButton("Start") {
                        isOperating = true
                        try await server.startDockerCompose(at: composeFile.filePath)
                        isOperating = false
                    }
                    .controlSize(.small)
                    .disabled(isOperating)
                }
                
                // Pull images button
                Menu {
                    AsyncButton("Pull Images") {
                        isOperating = true
                        try await server.pullDockerComposeImages(at: composeFile.filePath)
                        isOperating = false
                    }
                    .disabled(isOperating)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption)
                }
                .controlSize(.small)
                .disabled(isOperating)
                
                Spacer()
                
                if let lastModified = composeFile.lastModified {
                    Text(lastModified, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if isOperating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
        .padding()
        .background(.tertiary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview(traits: .sampleData) {
    DockerComposeRowView(
        composeFile: DockerCompose(
            serverId: "test",
            filePath: "/home/user/app/docker-compose.yml",
            projectName: "MyApp",
            services: ["web", "database", "redis"],
            lastModified: Date(),
            isRunning: true
        ),
        server: Server(credentialKey: "test")
    )
}