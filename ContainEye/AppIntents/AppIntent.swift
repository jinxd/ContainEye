//
//  AppIntent.swift
//  AppIntent
//
//  Created by Hannes Nagel on 1/31/25.
//

import Blackbird
import AppIntents
import UserNotifications

struct AppIntent: AppShortcutsProvider {

    static let shortcutTileColor: ShortcutTileColor = .lightBlue

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TestServers(),
            phrases: [
                "Test all servers in \(.applicationName)",
                "Test servers in \(.applicationName)",
                "\(.applicationName) test servers",
                "\(.applicationName) test",
            ],
            shortTitle: "Test Servers",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: TestServer(),
            phrases: [
                "Test \(\.$test) in \(.applicationName)",
                "\(.applicationName) test \(\.$test)",
                "Execute \(\.$test) in \(.applicationName)",
                "Execute test in \(.applicationName)",
                "\(.applicationName) führe \(\.$test) aus",
                "\(.applicationName) \(\.$test)",
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


