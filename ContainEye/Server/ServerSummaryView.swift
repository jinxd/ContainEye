//
//  ServerSummaryView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/14/25.
//

import SwiftUI


struct ServerSummaryView: View {
    let server: Server
    let hostInsteadOfLabel: Bool
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        VStack {
            Text((hostInsteadOfLabel ? server.credential?.host : server.credential?.label) ?? "Unknown")
            Grid {
                GridRow{
                    GridItemView.Percentage(title: "CPU Usage", percentage: server.cpuUsage)
                }
                .gridCellColumns(2)
                GridRow {
                    GridItemView.Percentage(title: "Memory Usage", percentage: server.memoryUsage)

                    GridItemView.Percentage(title: "IO Wait", percentage: server.ioWait)
                }
                GridRow{
                    GridItemView.Date(title: "Up Time", value: server.uptime)

                    GridItemView.Percentage(title: "Disk Usage", percentage: server.diskUsage)
                }
                GridRow{
                    GridItemView.Text(title: "Upstream", text: server.networkUpstream?.formatted(.number))

                    GridItemView.Text(title: "Downstream", text: server.networkDownstream?.formatted(.number))
                }
            }
        }
        .padding()
        .background(server.isConnected ? .accent.opacity(0.1) : .gray.opacity(0.2), in: .rect(cornerRadius: 15))
    }
}


