//
//  ContainEyeApp.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import SwiftUI
import Blackbird
import Citadel
import KeychainAccess
#if !os(macOS)
import BackgroundTasks
#endif
import AppIntents
import UserNotifications
import CoreSpotlight
import WidgetKit


@main
struct ContainEyeApp: App {
    let db = SharedDatabase.db
    @Environment(\.scenePhase) var scenePhase
    let llm = LLMEvaluator()

    init() {
        Logger.initTelemetry()
    }


    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.blackbirdDatabase, db)
#if !os(macOS)
                .onAppear{
                    try? BGTaskScheduler.shared.submit(
                        BGAppRefreshTaskRequest(identifier: "apprefresh")
                    )

                    Task{
                        await ServerTest.ServerTestAppEntitiy.updateSpotlightIndex()
                        AppIntent.updateAppShortcutParameters()
                        await loadDefaultData()
                    }
                }
#endif
                .onReceive(ServerTest.changePublisher(in: db)){ _ in
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onChange(of: scenePhase) {
                    switch scenePhase {
                    case .active:
                        Task{
                            try? await Logger.telemetry(
                                "app launched",
                                with: [
                                    "servers":keychain().allKeys().count,
                                    "tests":ServerTest.count(in: db, matching: \.$credentialKey != "-")
                                ]
                            )
                        }
                    default:
                        Logger.telemetry("app closed")
                    }
                }
                .environment(llm)
        }
#if !os(macOS)
        .backgroundTask(.appRefresh("apprefresh")) {
            await BGTaskScheduler.shared.pendingTaskRequests().forEach{print($0.identifier)}
            BGTaskScheduler.shared.cancelAllTaskRequests()
            try? BGTaskScheduler.shared.submit(
                BGAppRefreshTaskRequest(identifier: "apprefresh")
            )
            let serverTests = (try? await ServerTest.query(in: db, columns: [\.$id])) ?? []
            var tests: [ServerTest] = []
            for serverTest in serverTests {
                guard let test = try? await ServerTest.read(from: db, id: serverTest[\.$id]) else {continue}
                tests.append(test)
            }
            let intent = TestServers()
            intent.tests = tests.map{$0.entity}
            let _ = try? await intent.perform()
        }
#endif
    }

    nonisolated func loadDefaultData() async {
        guard let url = Bundle.main.url(forResource: "DefaultTests", withExtension: "json") else {
            print("Failed to find DefaultTests.json")
            return
        }
        do {
            let chain = Keychain()
                .synchronizable(true)
                .accessibility(.afterFirstUnlock)
                .label("ContainEye")
            for key in chain.allKeys() {
                do {
                    if let credential = chain.getCredential(for: key),
                       try !keychain().contains(credential.key) {
                        let data = try JSONEncoder().encode(credential)
                        try keychain()
                            .set(data, key: credential.key)
                    }
                } catch {
                    print(error)
                }
            }
            let data = try Data(contentsOf: url)
            let tests = try JSONDecoder().decode([ServerTest].self, from: data)

            for test in tests {
                guard (try? await ServerTest.read(from: db, id: test.id)) == nil else {continue}

                try? await test.write(to: db)
            }

        } catch {
            print("Error loading JSON: \(error)")
            return
        }
    }
}
