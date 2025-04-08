//
//  TestServers.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/3/25.
//

import AppIntents
import UserNotifications
import SwiftUI
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

    func perform() async throws -> some IntentResult & ReturnsValue<[ServerTest.ServerTestAppEntitiy]> & ShowsSnippetView {
        Logger.initTelemetry()
        Logger.telemetry("using appintent testservers", with: ["count":tests.count])
        let db = SharedDatabase.db
        let tests = tests.map { $0.getServerTest() }
        var finishedTests: [ServerTest] = []


        for test in tests.filter({ test in
            test.credentialKey != "-"
        }) {
            var test = test
            test = await test.test()
            if test.status == .failed {
                await sendPushNotification(title: test.title, output: test.output ?? "No output")
            }
            try? await test.write(to: db)
            finishedTests.append(test)
        }


            WidgetCenter.shared.reloadAllTimelines()

        let retryIntent = TestServers()
        retryIntent.tests = finishedTests.map { $0.entity }

        return .result(value: retryIntent.tests, view: IntentReturnView(tests: finishedTests, retryIntent: finishedTests.contains(where: {$0.status != .success}) ? retryIntent : nil))
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
