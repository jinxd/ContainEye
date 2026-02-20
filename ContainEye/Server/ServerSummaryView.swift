//
//  ServerSummaryView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/14/25.
//

import SwiftUI
import Blackbird

struct ServerSummaryView: View {
    @BlackbirdLiveModel var server: Server?
    let hostInsteadOfLabel: Bool
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        if let server {
            VStack {
                HStack {
                    Text((hostInsteadOfLabel ? server.credential?.host : server.credential?.label) ?? "Unknown")
                    Spacer()
                    if let lastUpdate = server.lastUpdate {
                        if lastUpdate.timeIntervalSinceNow.magnitude > 15{
                            Circle().foregroundStyle(.orange).frame(maxWidth: 10, maxHeight: 10)
                            Text(lastUpdate, style: .relative)
                                .minimumScaleFactor(0.2)
                                .lineLimit(1)
                        } else {
                            Circle().foregroundStyle(.green).frame(maxWidth: 10, maxHeight: 10)
                            Text("Online")
                        }
                    }
                }
                HStack{
                    Label(server.cpuCores == 1 ? "1 Core" : "\(server.cpuCores?.formatted() ?? "loading") Cores", systemImage: "cpu")
                        .frame(maxWidth: .infinity)
                    Label("\((server.totalMemory ?? 0)/1_073_741_824.0, format: .number.precision(.fractionLength(1))) G", systemImage: "memorychip")
                        .redacted(reason: server.totalMemory == nil ? .placeholder : [])
                        .frame(maxWidth: .infinity)
                    Label("\((server.totalDiskSpace ?? 0)/1_073_741_824.0, format: .number.precision(.fractionLength(0))) G", systemImage: "opticaldiscdrive")
                        .redacted(reason: server.totalDiskSpace == nil ? .placeholder : [])
                        .frame(maxWidth: .infinity)

                    Group {
                        if let uptime = server.uptime {
                            Text("\(Image(systemName: "power")) \(uptime, style: .relative)")
                        } else {
                            Text("\(Image(systemName: "power")) loading")
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
                .lineLimit(1)
                .padding(.vertical)
                Divider()
                HStack {
                    GridItemView.Percentage(title: "CPU", percentage: server.cpuUsage)
                        .frame(maxWidth: .infinity)
                    GridItemView.Percentage(title: "RAM", percentage: server.memoryUsage)
                        .frame(maxWidth: .infinity)
                    if server.isMacOS != true {
                        VStack {
                            if let networkUpstream = server.networkUpstream, let networkDownstream = server.networkDownstream {
                                Text("Network")
                                    .font(.caption2)
                                    .bold()
                                    .padding(.bottom, 10)
                                Label("\((networkUpstream/1024).formatted(.number.precision(.fractionLength(2)))) kb", systemImage: "arrow.up.circle")
                                    .animation(.smooth, value: networkUpstream)
                                    .lineLimit(1)
                                Label("\((networkDownstream/1024).formatted(.number.precision(.fractionLength(2)))) kb", systemImage: "arrow.down.circle")
                                    .animation(.smooth, value: networkDownstream)
                                    .lineLimit(1)
                            } else {
                                Text("loading up-/downstream")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    GridItemView.Percentage(title: "Disk", percentage: server.diskUsage)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical)
            }
            .padding()
            .background(server.isConnected ? .accent.opacity(0.1) : .gray.opacity(0.2), in: .rect(cornerRadius: 15))
            .contentTransition(.numericText())
            .monospacedDigit()
            .minimumScaleFactor(0.7)
        }
    }
}


#Preview {
    ServerSummaryView(server: .init(.init(credentialKey: "lol")), hostInsteadOfLabel: true)
}
