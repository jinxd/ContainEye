//
//  ContainerDetailView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/16/25.
//


import SwiftUI
import ButtonKit

struct ContainerDetailView: View {
    let container: Container

    var body: some View {
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
        .onAppear{
            Task {
                try? await container.fetchDetails()
                try? await Task.sleep(for: .seconds(1))
                container.server.dockerUpdatesPaused = false
                container.fetchDetailedUpdates = true
            }
        }
        .onDisappear{
            container.fetchDetailedUpdates = false
        }
        .navigationTitle(container.name)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .background(
            Color.accentColor
                .opacity(0.1)
                .gradient
        )
    }
}

