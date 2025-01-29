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



@main
struct ContainEyeApp: App {
    let db = try! Blackbird.Database(path: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("db.sqlite").path)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.blackbirdDatabase, db)
#if !os(macOS)
                .onAppear{
                    try? BGTaskScheduler.shared.submit(
                        BGAppRefreshTaskRequest(identifier: "apprefresh")
                    )
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
            await withTaskCancellationHandler{
                await withTaskGroup(of: Void.self){group in
                    for test in tests {
                        group.addTask {
                            do {
                                var test = test
                                test.state = .running
                                try await test.write(to: db)
                                test = await test.test()
                                try await test.write(to: db)
                                if test.state == .failed {
                                    try await sendPushNotification(title: test.title, output: test.output ?? "No output")
                                }
                            } catch {
                                try? await sendPushNotification(title: test.title, output: "to execute: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                print(">>> Done")
            } onCancel: {
                print(">>> Cancelled")
            }

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
