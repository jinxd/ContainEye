//
//  Logger.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/6/25.
//

import Foundation
import OSLog
import TelemetryDeck
import Blackbird
import SwiftUI

import os

enum Logger {
    static let ui = os.Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ui")

    private static let lock = DispatchQueue(label: "com.nagel.ContainEye.LoggerLock", attributes: .concurrent)

    nonisolated(unsafe) private static var _serverCount = ""
    nonisolated(unsafe) private static var _serverTestCount = ""

    static var serverCount: String {
        get {
            lock.sync { _serverCount }
        }
        set {
            lock.async(flags: .barrier) { _serverCount = newValue }
        }
    }

    static var serverTestCount: String {
        get {
            lock.sync { _serverTestCount }
        }
        set {
            lock.async(flags: .barrier) { _serverTestCount = newValue }
        }
    }

    static func initTelemetry() {
        let config = TelemetryDeck.Config(appID: "B2672C22-5A71-4BAE-848E-894C4A3C1D78")
        config.defaultParameters = {
            [
                "tests": Logger.serverTestCount,
                "servers": Logger.serverCount
            ]
        }
        TelemetryDeck.initialize(config: config)

        Task{
            try await updateData()
        }
    }


    @MainActor
    static func startDurationSignal(_ name: String, parameters: [String: String] = [:], includeBackgroundTime: Bool = false) {
        TelemetryDeck.startDurationSignal(name, parameters: parameters, includeBackgroundTime: includeBackgroundTime)
    }
    @MainActor
    static func endDurationSignal(_ name: String, parameters: [String: String] = [:], floatValue: Double? = nil) {
        TelemetryDeck.stopAndSendDurationSignal(name, parameters: parameters, floatValue: floatValue)
    }

    static func updateData() async throws {
        let testCount = try await ServerTest.count(in: SharedDatabase.db).formatted()
        let count = try await Server.count(in: SharedDatabase.db).formatted()

        lock.async(flags: .barrier) {
            _serverTestCount = testCount
            _serverCount = count
        }
    }
}


extension View {
    func trackView(_ name: String) -> some View {
        self
            .onAppear{
                Logger.startDurationSignal(name)
            }
            .onDisappear{
                Logger.endDurationSignal(name)
            }
            .trackNavigation(path: name)
    }
}
