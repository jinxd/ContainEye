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
    @State private var bridge = AgenticContextBridge.shared
    @State private var contextStore = AgenticScreenContextStore.shared
    @State private var lastNonAgenticScreen: Screen = .serverList

    enum Screen: String, CaseIterable, Identifiable {
        case serverList, testList, agentic = "more", setup, terminal, sftp

        var localizedTitle: String {
            switch self {
            case .serverList:
                "Servers"
            case .testList:
                "Code"
            case .agentic:
                "agentic"
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
                        Tab("Code", systemImage: "curlybraces.square", value: .testList){
                            ServerTestView()
                        }
                        Tab("Agentic", systemImage: "lasso.badge.sparkles", value: .agentic, role: .search){
                            AgenticView()
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
            .toolbar {
                if screen == .serverList {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
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
            }
            .toolbar(screen == .terminal ? .hidden : .automatic, for: .navigationBar)
            .toolbarBackgroundVisibility(screen == .terminal ? .visible : .hidden, for: .navigationBar)
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
                    .onAppear {
                        setServerContext(server)
                    }
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: server.id, in: namespace))
#endif
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container.liveModel)
                    .onAppear {
                        setContainerContext(container)
                    }
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: container.id, in: namespace))
#endif
            }
            .navigationDestination(for: ServerTest.self) { test in
                ServerTestDetail(test: .init(test, updatesEnabled: true))
                    .onAppear {
                        setTestContext(test)
                    }
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: test.id, in: namespace))
#endif
            }
            .navigationDestination(for: Snippet.self) { snippet in
                SnippetDetailView(snippet: .init(snippet, updatesEnabled: true))
                    .onAppear {
                        setSnippetContext(snippet)
                    }
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: snippet.id, in: namespace))
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
                    .onAppear {
                        contextStore.set(
                            chatTitle: "Web Context",
                            draftMessage: """
                            Reference this webpage currently on screen:
                            - url: \(url.absoluteString)

                            Help me with:
                            """
                        )
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
            .onChange(of: screen) {
                if screen == .agentic {
                    navigationPath = NavigationPath()
                    Task { await queueAutomaticAgenticContextIfNeeded() }
                } else {
                    lastNonAgenticScreen = screen
                    Task { await refreshRootContext(for: screen) }
                }
            }
        }
        .environment(\.namespace, namespace)
        .task{
            lastNonAgenticScreen = screen == .agentic ? .serverList : screen
            if !servers.didLoad {try? await Task.sleep(for: .seconds(1))}
            for key in keychain().allKeys() {
                if !servers.results.contains(where: {$0.credentialKey == key}) {
                    try? await Server(credentialKey: key).write(to: db!)
                }
            }
            await refreshRootContext(for: lastNonAgenticScreen)
        }
    }

    private func queueAutomaticAgenticContextIfNeeded() async {
        if bridge.pendingContext != nil { return }
        if let explicitContext = contextStore.currentContext {
            bridge.queueContext(chatTitle: explicitContext.chatTitle, draftMessage: explicitContext.draftMessage)
            return
        }
        if let fallback = await buildContextForScreen(lastNonAgenticScreen) {
            bridge.queueContext(chatTitle: fallback.chatTitle, draftMessage: fallback.draftMessage)
        }
    }

    private func refreshRootContext(for source: Screen) async {
        guard navigationPath.isEmpty else { return }
        if let context = await buildContextForScreen(source) {
            contextStore.set(chatTitle: context.chatTitle, draftMessage: context.draftMessage)
        } else {
            contextStore.clear()
        }
    }

    private func buildContextForScreen(_ source: Screen) async -> AgenticScreenContext? {
        switch source {
        case .serverList:
            let items = servers.results.prefix(8).map { server in
                let credential = server.credential
                let label = credential?.label ?? server.id
                let host = credential?.host ?? "unknown host"
                return "- \(label) (\(host))"
            }
            guard !items.isEmpty else {
                return AgenticScreenContext(
                    chatTitle: "Servers",
                    draftMessage: "I'm in the servers tab. Help me with the next server action:"
                )
            }
            return AgenticScreenContext(
                chatTitle: "Servers",
                draftMessage: """
                I am in the servers tab.
                Visible servers:
                \(items.joined(separator: "\n"))

                Help me with:
                """
            )
        case .terminal:
            let workspace = TerminalWorkspaceStore.shared
            guard let controller = workspace.activeControllerInFocusedPane() else {
                return AgenticScreenContext(
                    chatTitle: "Terminal",
                    draftMessage: "I am in the terminal tab (no active session yet). Help me with:"
                )
            }
            let serverLabel = keychain().getCredential(for: controller.credentialKey)?.label ?? controller.credentialKey
            let selected = controller.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let activeCommand = sanitizedTerminalCommand(controller.activeCommand?.command) ?? "(none)"
            let selectedBlock = selected.isEmpty ? "(no selection)" : selected
            return AgenticScreenContext(
                chatTitle: "Terminal \(serverLabel)",
                draftMessage: """
                Reference this terminal session:
                - server: \(serverLabel)
                - credentialKey: \(controller.credentialKey)
                - cwd: \(controller.cwd)
                - activeCommand: \(activeCommand)
                - selectedText:
                \(selectedBlock)

                Help me with:
                """
            )
        case .testList:
            guard let db else {
                return AgenticScreenContext(
                    chatTitle: "Code",
                    draftMessage: "I am in the Code tab. Help me with tests or snippets:"
                )
            }
            let tests = (try? await ServerTest.read(from: db, matching: \.$credentialKey != "-", orderBy: .descending(\.$lastRun), limit: 6)) ?? []
            let snippets = (try? await Snippet.read(from: db, matching: .all, orderBy: .descending(\.$lastUse), limit: 6)) ?? []

            let testLines = tests.map { "- [test:\($0.id)] \($0.title)" }
            let snippetLines = snippets.map { "- [snippet:\($0.id)] \($0.comment.isEmpty ? $0.command : $0.comment)" }
            return AgenticScreenContext(
                chatTitle: "Code",
                draftMessage: """
                I am in the Code tab.
                Recent tests:
                \(testLines.isEmpty ? "- (none)" : testLines.joined(separator: "\n"))

                Recent snippets:
                \(snippetLines.isEmpty ? "- (none)" : snippetLines.joined(separator: "\n"))

                Help me with:
                """
            )
        case .sftp:
            return contextStore.currentContext ?? AgenticScreenContext(
                chatTitle: "SFTP",
                draftMessage: "I am in the SFTP tab. Help me with a file/server operation:"
            )
        case .setup:
            return AgenticScreenContext(
                chatTitle: "Setup",
                draftMessage: "I am in setup. Help me configure servers/tests:"
            )
        case .agentic:
            return nil
        }
    }

    private func setServerContext(_ server: Server) {
        let label = server.credential?.label ?? server.id
        let host = server.credential?.host ?? "unknown host"
        let username = server.credential?.username ?? "unknown"
        contextStore.set(
            chatTitle: "Server \(label)",
            draftMessage: """
            Use this server as reference:
            - label: \(label)
            - host: \(host)
            - username: \(username)
            - credentialKey: \(server.credentialKey)

            Help me with:
            """
        )
    }

    private func sanitizedTerminalCommand(_ command: String?) -> String? {
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Ignore shell integration noise generated by OSC/bootstrap hooks.
        let noisyPrefixes = [
            "printf '\\r\\033[2K'",
            "printf \"\\r\\033[2K\"",
            "_ce_osc4545_"
        ]
        if noisyPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return nil
        }
        if trimmed.contains("4545;SetCwd;") || trimmed.contains("osc4545") {
            return nil
        }

        return trimmed
    }

    private func setContainerContext(_ container: Container) {
        contextStore.set(
            chatTitle: "Container \(container.name)",
            draftMessage: """
            Use this container as reference:
            - container: \(container.name)
            - serverId: \(container.serverId)
            - status: \(container.status)
            - id: \(container.id)

            Help me with:
            """
        )
    }

    private func setTestContext(_ test: ServerTest) {
        let server = keychain().getCredential(for: test.credentialKey)?.label ?? test.credentialKey
        contextStore.set(
            chatTitle: "Test \(test.id)",
            draftMessage: """
            Edit this existing test using tool calls.

            Use `update_test` for this record:
            - id: \(test.id)
            - server: \(server)
            - title: \(test.title)
            - command: \(test.command)
            - expectedOutput: \(test.expectedOutput)
            - notes: \(test.notes ?? "(none)")

            Requested changes:
            """
        )
    }

    private func setSnippetContext(_ snippet: Snippet) {
        let key = snippet.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serverLabel = key.isEmpty ? "Global (no server)" : (keychain().getCredential(for: key)?.label ?? key)
        contextStore.set(
            chatTitle: "Snippet \(snippet.id)",
            draftMessage: """
            Edit this existing snippet.
            - id: \(snippet.id)
            - server: \(serverLabel)
            - command: \(snippet.command)
            - comment: \(snippet.comment.isEmpty ? "(none)" : snippet.comment)

            Requested changes:
            """
        )
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
