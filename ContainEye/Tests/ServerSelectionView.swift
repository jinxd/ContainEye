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
    @Binding var isPresented: Bool

    @Environment(\.blackbirdDatabase) private var db
    @Environment(\.dismiss) private var dismiss
    @BlackbirdLiveModels({
        try await Server.read(from: $0, matching: .all)
    }) var servers

    var body: some View {
        NavigationStack {
            VStack {
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
                    }
                    .padding(.horizontal)
                }

                Spacer()
                VStack {
                    AsyncButton("Add Test to Server", systemImage: "plus.circle.fill") {
                        guard let selectedServer else { return }
                        isAdding = true
                        defer { isAdding = false }

                        var newTest = test
                        newTest.id = Int.random(in: 1000...999999)
                        newTest.credentialKey = selectedServer
                        try? await newTest.write(to: db!)
                        isPresented = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(selectedServer == nil || isAdding)
                }
                .padding()
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
}

#Preview(traits: .sampleData) {
    @Previewable @State var selectedServer: String? = nil
    @Previewable @State var isAdding = false
    @Previewable @State var isPresented = true
    return ServerSelectionView(
        test: PreviewSamples.test,
        selectedServer: $selectedServer,
        isAdding: $isAdding,
        isPresented: $isPresented
    )
}
