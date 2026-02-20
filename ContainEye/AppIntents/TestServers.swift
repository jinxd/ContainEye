//
//  TestServers.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/3/25.
//

import AppIntents
import UserNotifications
import WidgetKit

struct TestServers: AppIntents.AppIntent {
    static var title: LocalizedStringResource { "Test the servers" }
    static let openAppWhenRun: Bool = false

    static let isDiscoverable: Bool = true


    @Parameter(title: "Test", requestValueDialog: "What tests would you like to run?")
    var tests: [ServerTest.ServerTestAppEntitiy]

    static var parameterSummary: some ParameterSummary {
            Summary("Run the tests: \(\.$tests)")

    }

    init(){}

    func perform() async throws -> some IntentResult & ReturnsValue<[ServerTest.ServerTestAppEntitiy]> & ProvidesDialog {
        Logger.initTelemetry()
        let db = SharedDatabase.db
        let tests = tests.map { $0.getServerTest() }
        var finishedTests: [ServerTest] = []


        for test in tests.filter({ test in
            test.credentialKey != "-"
        }) {
            var test = test
            test = await test.test()
            if test.status == .failed {
                await sendPushNotification(title: test.title, output: (test.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty ? "Empty output" : test.output!)
            }
            try? await test.write(to: db)
            finishedTests.append(test)
        }


            WidgetCenter.shared.reloadAllTimelines()

        let failedCount = finishedTests.filter { $0.status == .failed }.count
        let dialog: IntentDialog = if failedCount == 0 {
            IntentDialog("Finished \(finishedTests.count) tests successfully.")
        } else {
            IntentDialog("Finished \(finishedTests.count) tests. \(failedCount) failed.")
        }

        return .result(value: finishedTests.map(\.entity), dialog: dialog)
    }
    private func sendPushNotification(title: String, output: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Test failed"
        content.body = output
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
}
