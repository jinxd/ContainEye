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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let db = SharedDatabase.db
    @Environment(\.scenePhase) var scenePhase

    init() {
        Logger.initTelemetry()
    }


    var body: some Scene {
        WindowGroup {
            ContentView()
                .confirmator()
                .environment(\.blackbirdDatabase, db)
#if !os(macOS)
                .onAppear{
                    try? BGTaskScheduler.shared.submit(
                        BGAppRefreshTaskRequest(identifier: "apprefresh")
                    )

                    Task(priority: .background){
                        await ServerTest.ServerTestAppEntitiy.updateSpotlightIndex()
                        AppIntent.updateAppShortcutParameters()
                        await loadDefaultData()
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
#endif
                .onReceive(ServerTest.changePublisher(in: db)){ _ in
                    WidgetCenter.shared.reloadAllTimelines()
                    Task{try await Logger.updateData()}
                }
                .onReceive(Server.changePublisher(in: db)) { _ in
                    Task{try await Logger.updateData()}
                }
        }
#if !os(macOS)
        .backgroundTask(.appRefresh("apprefresh")) {    //e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"apprefresh"]
            await BGTaskScheduler.shared.pendingTaskRequests().forEach{print($0.identifier)}
            BGTaskScheduler.shared.cancelAllTaskRequests()
            try? BGTaskScheduler.shared.submit(
                BGAppRefreshTaskRequest(identifier: "apprefresh")
            )
            let tests = (try? await ServerTest.read(from: db, matching: \.$credentialKey != "-", orderBy: .ascending(\.$lastRun), limit: 10)) ?? []
            let intent = TestServers()
            intent.tests = tests.map{$0.entity}
            let _ = try? await intent.perform()
            let _ = try? await intent.donate()
        }
#endif
    }

    nonisolated func loadDefaultData() async {
        guard let url = Bundle.main.url(forResource: "DefaultTests", withExtension: "json") else {
            print("Failed to find DefaultTests.json")
            return
        }
        do {
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
