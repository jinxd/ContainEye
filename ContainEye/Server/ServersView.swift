//
//  ServersView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/26/25.
//


import SwiftUI
import KeychainAccess
import ButtonKit

struct ServersView: View {
    @Binding var sheet : ContentView.Sheet?
    @State var dataStreamer = DataStreamer.shared

    var body: some View {
        ScrollView{
            VStack{
                if dataStreamer.servers.isEmpty {
                    if dataStreamer.serversLoaded && dataStreamer.errors.isEmpty {
                        ContentUnavailableView("You don't have any servers yet.", systemImage: "server.rack")
                    } else if !dataStreamer.errors.isEmpty {
                        DataStreamerErrorView()
                    } else {
                        ProgressView()
                            .controlSize(.extraLarge)
                    }
                }


                LazyVGrid(columns: [GridItem(.adaptive(minimum: 500, maximum: 800))]) {
                    ForEach(Array(dataStreamer.servers)) {server in
                        NavigationLink(value: server) {
                            ServerSummaryView(server: server, hostInsteadOfLabel: false)
                                .contextMenu{
                                    Menu {
                                        AsyncButton("Delete", systemImage: "trash", role: .destructive) {
                                            try await dataStreamer.removeHost(server.credential.key)
                                        }
                                        
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding()
            .padding(.top, 50)
            .containerRelativeFrame(dataStreamer.servers.isEmpty || !dataStreamer.serversLoaded ? .vertical : [])
        }
        .refreshable {
            await dataStreamer.initialize()
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add Server", systemImage: "plus"){
                sheet = .addServer
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
#if !os(macOS)
            .drawingGroup()
#endif
        }
    }
}


#Preview {
    ServersView(sheet: .constant(nil))
}
