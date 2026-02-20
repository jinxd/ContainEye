//
//  TestSummaryView.swift
//  ContainEye
//
//  Created by Claude on 6/26/25.
//

import Blackbird
import SwiftUI
import ButtonKit

struct TestSummaryView: View {
    @BlackbirdLiveModel var test: ServerTest?
    @Environment(\.blackbirdDatabase) var db
    @Environment(\.namespace) var namespace
    @State private var isRunning = false
    
    var body: some View {
        if let test {
            NavigationLink(value: test) {
                VStack {
                    // Header section with status indicator
                    HStack {
                        statusIndicator
                        Spacer()
                        actionMenu
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    
                    // Content section
                    VStack(alignment: .leading) {
                        // Test title
                        Text(test.title)
                            .font(.headline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Server/host info
                        HStack {
                            Image(systemName: "server.rack")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Text(hostDisplayText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        // Status and timing info
                        VStack(alignment: .leading) {
                            HStack {
                                Text(test.status.displayText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(test.status.color)
                                
                                Spacer()
                                
                                if let lastRun = test.lastRun {
                                    Text(lastRun, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text("Never run")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            
                            // Progress bar for running tests
                            if test.status == .running || isRunning {
                                ProgressView()
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    .scaleEffect(y: 0.5)
                            } else {
                                Rectangle()
                                    .fill(test.status.color.opacity(0.3))
                                    .frame(height: 2)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    
                    // Quick action button
                    if test.credentialKey != "-" {
                        Divider()
                        
                        AsyncButton {
                            await executeTest()
                        } label: {
                            HStack {
                                if isRunning {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(.blue)
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                
                                Text("Run Test")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .disabled(isRunning || test.status == .running)
                        .buttonStyle(.plain)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(test.status.color.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: test.id, in: namespace!)
        }
    }
    
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(test?.status.color.opacity(0.15) ?? .gray.opacity(0.15))
                .frame(width: 28, height: 28)
            
            if test?.status == .running || isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .tint(test?.status.color ?? .blue)
            } else {
                Image(systemName: test?.status.icon ?? "questionmark")
                    .font(.caption)
                    .foregroundStyle(test?.status.color ?? .gray)
            }
        }
    }
    
    private var actionMenu: some View {
        Menu {
            if let test, test.credentialKey != "-" {
                Button("Run Test", systemImage: "play.fill") {
                    Task { await executeTest() }
                }
                
                NavigationLink(value: test) {
                    Label("Edit Test", systemImage: "pencil")
                }
                
                Divider()
                
                Button("Delete Test", systemImage: "trash", role: .destructive) {
                    deleteTest()
                }
            } else if test != nil {
                Button("Add to Active Tests", systemImage: "plus") {
                    addToActiveTests()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
    }
    
    private var hostDisplayText: String {
        guard let test else { return "Unknown" }
        
        if test.credentialKey == "-" {
            return "Suggested Test"
        } else if test.credentialKey.isEmpty {
            return "Local Test"
        } else {
            let credential = keychain().getCredential(for: test.credentialKey)
            return credential?.label ?? "Unknown Server"
        }
    }
    
    private func executeTest() async {
        guard let test else { return }
        
        isRunning = true
        var updatedTest = test
        
        do {
            updatedTest.status = .running
            try await updatedTest.write(to: db!)
            updatedTest = await updatedTest.test()
            
#if !os(macOS)
            if updatedTest.status == .failed {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
#endif
            
            try await updatedTest.write(to: db!)
            try await updatedTest.testIntent().donate()
        } catch {
            if updatedTest.status == .running {
                updatedTest.status = .failed
                try? await updatedTest.write(to: db!)
            }
        }
        
        isRunning = false
    }
    
    private func deleteTest() {
        guard let test else { return }
        Task {
            try await test.delete(from: db!)
        }
    }
    
    private func addToActiveTests() {
        guard let test else { return }
        Task {
            var newTest = test
            newTest.id = Int.random(in: 1000...999999)
            newTest.credentialKey = "placeholder" // User will need to configure
            try await newTest.write(to: db!)
        }
    }
}


#Preview {
    let db = try! Blackbird.Database.inMemoryDatabase()
    let test1 = ServerTest(id: 1, title: "Disk Space Check", credentialKey: "server1", command: "df -h", expectedOutput: "Available", status: .success)
    let test2 = ServerTest(id: 2, title: "Memory Usage Monitor", credentialKey: "server1", command: "free -m", expectedOutput: "free", status: .failed)
    let test3 = ServerTest(id: 3, title: "Service Status", credentialKey: "server2", command: "systemctl status nginx", expectedOutput: "active", status: .running)
    
    Task {
        try await test1.write(to: db)
        try await test2.write(to: db)
        try await test3.write(to: db)
    }
    
    return VStack(spacing: 16) {
        TestSummaryView(test: test1.liveModel)
        TestSummaryView(test: test2.liveModel)
        TestSummaryView(test: test3.liveModel)
    }
    .padding()
    .environment(\.blackbirdDatabase, db)
}
