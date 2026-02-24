//
//  ContainerDetailView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//


import SwiftUI
import ButtonKit
import Blackbird

struct ContainerDetailView: View {
    @BlackbirdLiveModel var container: Container?
    @Environment(\.agenticContextStore) private var contextStore

    var body: some View {
        if let container {
            ContainerSummaryView(container: container.liveModel)
            ScrollViewReader {scroll in
                ScrollView {
                    if container.logs.isEmpty{
                        ContentUnavailableView("No logs available yet", systemImage: "tree", description: Text("ContainEye is trying to load them..."))
                    } else {
                        Text(container.logs)
                            .frame(maxWidth: .infinity)
                            .task{scroll.scrollTo("end")}
                        VStack{}.id("end")
                    }
                }
                .defaultScrollAnchor(.center)
                .padding()
                .background(.accent.opacity(0.1), in: .rect(cornerRadius: 15))
                .padding()
            }
            .navigationTitle(container.name)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .task{
                while !Task.isCancelled {
                    if await !(container.server?.isConnected ?? false) {
                        try? await container.server?.connect()
                    }
                    
                    // Update container stats and details
                    await container.server?.fetchDockerStats()
                    try? await container.fetchDetails()
                    
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .onAppear {
                updateAgenticContext(container: container)
            }
            .onChange(of: container.name) {
                updateAgenticContext(container: container)
            }
            .safeAreaInset(edge: .bottom) {
                AgenticDetailFABInset()
            }
        }
    }

    private func updateAgenticContext(container: Container) {
        contextStore.set(
            chatTitle: "Container \(container.name)",
            draftMessage: """
            Use this container as reference:
            - container: \(container.name)
            - serverId: \(container.serverId)
            - status: \(container.status)
            - id: \(container.id)

            Help me with:
            """
        )
    }
}

#Preview(traits: .sampleData) {
    NavigationStack {
        ContainerDetailView(container: .init(PreviewSamples.container, updatesEnabled: false))
    }
}
