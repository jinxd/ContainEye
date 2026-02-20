//
//  ServerSelectionView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 6/26/25.
//


import SwiftUI
import Blackbird
import ButtonKit


struct ServerSelectionView: View {
    let test: ServerTest
    @Binding var selectedServer: String?
    @Binding var isAdding: Bool
    let onAdd: (String) async -> Void
    
    @Environment(\.dismiss) private var dismiss
    @BlackbirdLiveModels({
        try await Server.read(from: $0, matching: .all)
    }) var servers
    
    var body: some View {
        NavigationView {
            VStack {
                headerSection
                serverListSection
                Spacer()
                actionSection
            }
            .navigationTitle("Add Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            
            Text("Select Server")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose which server to add \"\(test.title)\" to")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }
    
    private var serverListSection: some View {
        Group {
            if servers.results.isEmpty {
                VStack {
                    Text("No servers available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Add a server first to create tests")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                LazyVStack {
                    ForEach(servers.results) { server in
                        serverSelectionRow(server)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func serverSelectionRow(_ server: Server) -> some View {
        Button {
            selectedServer = server.credentialKey
        } label: {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading) {
                    Text(server.credential?.label ?? "Unknown Server")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(server.credential?.host ?? "Unknown Host")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if selectedServer == server.credentialKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedServer == server.credentialKey ? .blue.opacity(0.1) : Color(.systemGray5))
                    .stroke(selectedServer == server.credentialKey ? .blue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var actionSection: some View {
        VStack {
            AsyncButton {
                if let serverKey = selectedServer {
                    await onAdd(serverKey)
                }
            } label: {
                HStack {
                    if isAdding {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("Add Test to Server")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(selectedServer == nil || isAdding)
            
            Button(role: .cancel) {
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
