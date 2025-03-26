//
//  ContainerSummaryView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/25/25.
//


import SwiftUI
import ButtonKit
import Blackbird

struct ContainerSummaryView: View {
    @BlackbirdLiveModel var container: Container?
    @Environment(\.namespace) var namespace

    var body: some View {
        if let container {
            VStack{
                HStack {
                    Text(container.name)
                    Spacer()
                    containerStatusText(for: container.status)
                }
                Divider()
                HStack {
                    Spacer()
                    GridItemView.Percentage(title: "CPU Usage", percentage: container.cpuUsage)
                    Spacer()
                    GridItemView.Percentage(title: "Memory Usage", percentage: container.memoryUsage)
                    Spacer()
                    let isRunning = container.status.localizedCaseInsensitiveContains("up")
                    if isRunning {
                        AsyncButton(progress: .estimated(for: .seconds(2))) { progress in
                            try await container.stop()
                        } label: {
                            GridItemView.Text(title: "Control", text: "Stop")
                        }
                        .asyncButtonStyle(GridItemView.AsyncProgressButtonStyle(title: "Stopping..."))
                        .buttonStyle(.plain)
                    } else {
                        AsyncButton(progress: .estimated(for: .seconds(2))) { progress in
                            try await container.start()
                        } label: {
                            GridItemView.Text(title: "Control", text: "Start")
                        }
                        .asyncButtonStyle(GridItemView.AsyncProgressButtonStyle(title: "Starting..."))
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(minHeight: 100)
                .padding(.vertical)
                .tint(
                    container.status.localizedCaseInsensitiveContains("up") ? Color.accentColor.secondary : Color.primary.secondary
                )
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor.quaternary.quaternary, in: RoundedProgressRectangle(cornerRadius: 15))
            .padding(.horizontal)
#if !os(macOS)
            .navigationTransition(.zoom(sourceID: container.id, in: namespace!))
#endif
        }
    }

    @ViewBuilder
    func containerStatusText(for text: String) -> some View {
        HStack{
            Circle()
                .fill(text.localizedCaseInsensitiveContains("up") ? Color.green : Color.orange)
                .frame(width: 10)
            Text(text)
        }
    }
}
