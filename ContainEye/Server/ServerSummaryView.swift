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

    var body: some View {
            VStack {

                Text(hostInsteadOfLabel ? server.credential.host : server.credential.label)

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
                ErrorView(server: server)
                    .padding(.horizontal, -15)
            }
            .padding()
            .background(Color.accentColor.quaternary.quaternary, in: RoundedProgressRectangle(cornerRadius: 15))
    }
}


