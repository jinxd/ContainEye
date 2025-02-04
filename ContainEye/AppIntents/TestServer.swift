//
//  TestServer.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/3/25.
//

import AppIntents
import SwiftUI


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

