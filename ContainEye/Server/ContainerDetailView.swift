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
                    if await !(container.server?.isConnected ?? false) {try? await container.server?.connect()}
                    await container.server?.fetchServerStats()
                    try? await container.fetchDetails()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
}

