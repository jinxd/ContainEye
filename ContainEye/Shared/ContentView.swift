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
import Blackbird

struct ContentView: View {
    @BlackbirdLiveModels({try await Server.read(from: $0, matching: .all, orderBy: .descending(\.$id))}) var servers
    @AppStorage("screen") private var screen = Screen.serverList
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blackbirdDatabase) var db
    @Namespace var namespace

    enum Screen: String, CaseIterable, Identifiable {
        case serverList, testList, more, setup, terminal, sftp

        var localizedTitle: String {
            switch self {
            case .serverList:
                "Servers"
            case .testList:
                "Tests"
            case .more:
                "more"
            case .setup:
                "setup"
            case .terminal:
                "terminal"
            case .sftp:
                "sftp"
            }
        }
        var id: String {
            "\(rawValue)"
        }
    }
    @State private var navigationPath = NavigationPath()


    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack{
                if screen == .setup {
                    SetupView()
                        .onDisappear{
                            UserDefaults.standard.set(1, forKey: "setupScreen")
                        }
                } else {
                    TabView(selection: $screen) {
                        Tab("SFTP", systemImage: "list.bullet", value: .sftp){
                            SFTPView()
                        }
                        Tab("Terminal", systemImage: "apple.terminal", value: .terminal){
                            RemoteTerminalView()
                        }
                        Tab("Servers", systemImage: "server.rack", value: .serverList){
                            ServersView()
                        }
                        Tab("Tests", systemImage: "testtube.2", value: .testList){
                            ServerTestView()
                        }
                        Tab("More", systemImage: "ellipsis", value: .more){
                            MoreView()
                        }
                    }
                }
            }
            .onAppear{
                if UserDefaults.standard.object(forKey: "setupScreen") == nil {
                    UserDefaults.standard.set(ContentView.Screen.setup.rawValue, forKey: "screen")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar{
                if screen == .serverList{
                    Button{
                        UserDefaults.standard.set(ContentView.Screen.setup.rawValue, forKey: "screen")
                        UserDefaults.standard.set(1, forKey: "setupScreen")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a server")
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationDestination(for: Sheet.self){sheet in
                SheetView(sheet: sheet)
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: sheet.id, in: namespace))
#endif
            }
            .navigationDestination(for: Server.self) { server in
                ServerDetailView(server: server.liveModel, id: server.id)
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: server.id, in: namespace))
#endif
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container.liveModel)
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: container.id, in: namespace))
#endif
            }
            .navigationDestination(for: ServerTest.self) { test in
                ServerTestDetail(test: .init(test, updatesEnabled: true))
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: test.id, in: namespace))
#endif
            }
            .navigationDestination(for: URL.self) { url in
                WebView(url: url)
                    .ignoresSafeArea()
                    .toolbar{
                        Button{
                            UIApplication.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        ShareLink(item: url)
                    }
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: url, in: namespace))
#endif
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
        .confirmator()
        .environment(\.namespace, namespace)
        .task{
            if !servers.didLoad {try? await Task.sleep(for: .seconds(1))}
            for key in keychain().allKeys() {
                if !servers.results.contains(where: {$0.credentialKey == key}) {
                    try? await Server(credentialKey: key).write(to: db!)
                }
            }
        }
    }
    func handleActivity(_ activity: NSUserActivity) {
        screen = .testList
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


