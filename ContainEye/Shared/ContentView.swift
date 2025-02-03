//
//  ContentView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import SwiftUI
import KeychainAccess
import ButtonKit

struct ContentView: View {
    @State private var dataStreamer = DataStreamer.shared
    @State private var sheet = Sheet?.none
    @AppStorage("screen") private var screen = Screen.ServerList
    @Environment(\.scenePhase) private var scenePhase

    enum Screen: String, CaseIterable, Identifiable {
        case ServerList
        case TestList

        var localizedTitle: String {
            switch self {
            case .ServerList:
                "Servers"
            case .TestList:
                "Tests"
            }
        }
        var id: String {
            "\(rawValue)"
        }
    }

    enum Sheet: Identifiable {
        case addServer, addTest

        var id: String {
            switch self {
            case .addServer:
                "add_server"
            case .addTest:
                "add_test"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack{
                if screen == .TestList {
                    ServerTestView(sheet: $sheet)
                        .transition(.move(edge: .trailing))
                } else {
                    ServersView(sheet: $sheet)
                        .transition(.move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.smooth, value: screen)
            .toolbar{
                Picker("", selection: $screen) {
                    ForEach(Screen.allCases) { screen in
                        Text(screen.localizedTitle)
                            .tag(screen)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            .navigationTitle("ContainEye")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .animation(.spring, value: dataStreamer.servers)
            .sheet(item: $sheet) { sheet in
                SheetView(sheet: sheet)
            }
            .navigationDestination(for: Server.self) { server in
                ServerDetailView(server: server)
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container)
            }
            .navigationDestination(for: ServerTest.self) { test in
                ServerTestDetail(test: .init(test, updatesEnabled: true))
            }
        }
        .task(id: scenePhase){
            switch scenePhase{
            case .active:
                await dataStreamer.initialize()
            default:
                try? await Task.sleep(for: .seconds(1))
                await dataStreamer.disconnectAllServers()
            }
        }
    }
}







#Preview {
    ContentView()
}
