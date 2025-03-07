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
            ScrollView{
                Grid {
                    GridRow {
                        GridItemView.Text(title: "Container", text: container.name)
                    }
                    .gridCellColumns(2)
                    GridRow {
                        GridItemView.Text(title: "Started", text: container.cmd)
                    }
                    .gridCellColumns(2)
                    GridRow{
                        GridItemView.Percentage(title: "CPU Usage", percentage: container.cpuUsage)
                        GridItemView.Percentage(title: "Memory Usage", percentage: container.memoryUsage)
                    }
                }
                .tint(Color.accentColor)
                .padding()
                .background(Color.accentColor.quaternary.quaternary, in: RoundedProgressRectangle(cornerRadius: 15))
                .padding(.horizontal)
                
                
                Text(container.status)
                Grid{
                    GridRow{
                        let isRunning = container.status.localizedCaseInsensitiveContains("up")
                        if isRunning {
                            AsyncButton(progress: .estimated(for: .seconds(2))) { progress in
                                try await container.stop()
                            } label: {
                                GridItemView.Text(title: "Stop", text: "this container")
                            }
                            .asyncButtonStyle(GridItemView.AsyncProgressButtonStyle(title: "Stopping..."))
                            .padding(.horizontal)
                        } else {
                            AsyncButton(progress: .estimated(for: .seconds(2))) { progress in
                                try await container.start()
                            } label: {
                                GridItemView.Text(title: "Start", text: "this container")
                            }
                            .asyncButtonStyle(GridItemView.AsyncProgressButtonStyle(title: "Starting..."))
                            .padding(.horizontal)
                        }
                    }
                    .gridCellColumns(2)
                }
                .padding(.horizontal)
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
                }
            }
            .onDisappear{
                CurrentServerId.shared.setCurrentServerId(container.serverId)
            }
        }
    }
}

