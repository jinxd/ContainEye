//
//  ContentView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import SwiftUI
import KeychainAccess
import ButtonKit
import CoreSpotlight

struct ContentView: View {
    @State private var dataStreamer = DataStreamer.shared
    @State private var sheet = Sheet?.none
    @AppStorage("screen") private var screen = Screen.ServerList
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blackbirdDatabase) var db

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
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack{
                TabView(selection: $screen) {
                    Tab("Servers", systemImage: "server.rack", value: Screen.ServerList){
                        ServersView(sheet: $sheet)
                    }
                    Tab("Tests", systemImage: "testtube.2", value: Screen.TestList){
                        ServerTestView(sheet: $sheet)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .onContinueUserActivity(CSQueryContinuationActionType){ activity in
                handleActivity(activity)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                handleActivity(activity)
            }
            .onContinueUserActivity("test.selected") { activity in
                handleActivity(activity)
            }
            .onOpenURL { url in
                let string = url.absoluteString.replacingOccurrences(of: "https://hannesnagel.com/open/containeye/", with: "")
                let components = string.components(separatedBy: "/")
                if components[0] == "test" {
                    navigationPath.append(
                        ServerTest(id: Int(components[1])!, title: "", credentialKey: "", command: "", expectedOutput: "", status: .notRun)
                    )
                }
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
    func handleActivity(_ activity: NSUserActivity) {
        screen = .TestList
        if let string = (activity.userInfo!["kCSSearchableItemActivityContentKey"] as? String) ?? (activity.userInfo!["kCSSearchableItemActivityIdentifier"] as? String),
           string.components(separatedBy: "/").count >= 2,
           let id = Int(string.components(separatedBy: "/")[1] ){
            navigationPath.append(
                ServerTest(
                    id: id,
                    title: "",
                    credentialKey: "",
                    command: "",
                    expectedOutput: "",
                    status: .notRun
                )
            )
        } else if let url = activity.contentAttributeSet?.url {
            let string = url.absoluteString.replacingOccurrences(of: "https://hannesnagel.com/open/containeye/", with: "")
            let components = string.components(separatedBy: "/")
            if components[0] == "test" {
                navigationPath.append(
                    ServerTest(id: Int(components[1])!, title: "", credentialKey: "", command: "", expectedOutput: "", status: .notRun)
                )
            }
        } else if let id = activity.userInfo!["id"] as? Int {
            navigationPath.append(
                ServerTest(
                    id: id,
                    title: "",
                    credentialKey: "",
                    command: "",
                    expectedOutput: "",
                    status: .notRun
                )
            )
        }
    }
}





#Preview {
    ContentView()
}
