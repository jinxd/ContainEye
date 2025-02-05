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


@main
struct ContainEyeApp: App {
    let db = SharedDatabase.db


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
                    }
                }
#endif
        }
#if !os(macOS)
        .backgroundTask(.appRefresh("apprefresh")) {
            await BGTaskScheduler.shared.pendingTaskRequests().forEach{print($0.identifier)}
            BGTaskScheduler.shared.cancelAllTaskRequests()
            try! BGTaskScheduler.shared.submit(
                BGAppRefreshTaskRequest(identifier: "apprefresh")
            )
            let serverTests = (try? await ServerTest.query(in: db, columns: [\.$id], matching: .all)) ?? []
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
    func sendPushNotification(title: String, output: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Test failed"
        content.body = output
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try await UNUserNotificationCenter.current().add(request)
    }
}
