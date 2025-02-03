//
//  AppIntent.swift
//  AppIntent
//
//  Created by Hannes Nagel on 1/31/25.
//

import Blackbird
import AppIntents
import UserNotifications
import SwiftUI

struct AppIntent: AppShortcutsProvider {

    static let shortcutTileColor: ShortcutTileColor = .lightBlue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TestServers(),
            phrases: [
                "Test all servers in \(.applicationName)",
            ],
            shortTitle: "Test Servers",
            systemImageName: "shippingbox",
            parameterPresentation: ParameterPresentation(
                for: \.$tests,
                summary: Summary("Execute tests: \(\.$tests)"),
                optionsCollections: {
                    OptionsCollection(ServerTest.ServerTestAppEntitiy.Query(), title: "Execute Tests", systemImageName: "testtube.2")
                }
            )
        )
        AppShortcut(
            intent: TestServer(),
            phrases: [
                "Test \(\.$test) in \(.applicationName)",
                "\(.applicationName) test \(\.$test)",
                "Execute \(\.$test) in \(.applicationName)",
                "Execute test in \(.applicationName)",
                "\(.applicationName) führe \(\.$test) aus",
            ],
            shortTitle: "Run a single Test",
            systemImageName: "shippingbox",
            parameterPresentation: ParameterPresentation(
                for: \.$test,
                summary: Summary("Execute test: \(\.$test)"),
                optionsCollections: {
                    OptionsCollection(ServerTest.ServerTestAppEntitiy.Query(), title: "Execute Test", systemImageName: "testtube.2")
                }
            )
        )
    }
}

struct TestServer: AppIntents.AppIntent {
    static var title: LocalizedStringResource { "Test a server" }
    static let openAppWhenRun: Bool = false

    static let isDiscoverable: Bool = true


    @Parameter(title: "Test" , requestValueDialog: "Which test would you like to run?")
    var test: ServerTest.ServerTestAppEntitiy

    static var parameterSummary: some ParameterSummary {
        Summary("Run the test: \(\.$test)")
    }
    init(){}

    func perform() async throws -> some IntentResult & ReturnsValue<ServerTest.ServerTestAppEntitiy?> & ProvidesDialog {
        let intent = TestServers()
        intent.tests = [test]

        let result = try await intent.perform()
        if let finishedTest = result.value?.first {
            return .result(value: finishedTest, dialog: IntentDialog("Finished \(finishedTest.title): \(finishedTest.status.localizedDescription)"))
        }
        let intentDialog = IntentDialog("Failed to run test")
        return .result(value: nil, dialog: intentDialog)
    }
}

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
        let db = SharedDatabase.db
        let tests = tests.map { $0.getServerTest() }
        var finishedTests: [ServerTest] = []

        await withTaskCancellationHandler{
            finishedTests = await withTaskGroup(of: ServerTest.self){group in
                for test in tests {
                    group.addTask {
                        var test = test
                        do {
                            test.status = .running
                            try await test.write(to: db)
                            test = await test.test()
                            if test.status == .failed {
                                try await sendPushNotification(title: test.title, output: test.output ?? "No output")
                            }
                        } catch {
                            test.status = .failed
                            try? await sendPushNotification(title: test.title, output: "to execute: \(error.generateDescription())")
                        }
                        try? await test.write(to: db)
                        return test
                    }
                }
                var result: [ServerTest] = []
                for await test in group {
                    result.append(test)
                }
                return result
            }
            print(">>> Done")
        } onCancel: {
            print(">>> Cancelled")
        }
        let retryIntent = TestServers()
        retryIntent.tests = finishedTests.map { $0.entity }

        return .result(value: retryIntent.tests, view: IntentReturnView(tests: finishedTests, retryIntent: finishedTests.contains(where: {$0.status != .success}) ? retryIntent : nil))
    }
    private func sendPushNotification(title: String, output: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Test failed"
        content.body = output
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try await UNUserNotificationCenter.current().add(request)
    }
}


struct IntentReturnView: View {
    let tests: [ServerTest]
    let retryIntent: TestServers?

    var body: some View {

        VStack{
            ForEach(tests) { test in
                HStack {
                    Text(test.title)
                    Spacer()
                    test.status.image
                        .foregroundStyle(test.status == .failed ? .red : test.status == .success ? .green : .gray)
                }
                .foregroundStyle(.white)
                if test != tests.last {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 2)
                }
            }
            if let retryIntent = retryIntent {
                Button("Retry (in background)", intent: retryIntent)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .padding(5)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.2), in: .rect(cornerRadius: 15))
        .padding()
    }
}
