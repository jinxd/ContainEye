//
//  Logger.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/6/25.
//

import Foundation
import OSLog
import Aptabase

enum Logger {
    static let ui = os.Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ui")

    static func initTelemetry() {
        Aptabase.shared.initialize(appKey: "A-SH-1638672524", with: .init(host: "https://analytics.hannesnagel.com"), userDefaultsGroup: "group.com.nagel.ContainEye")
    }

    static func telemetry(_ message: String, with parameters: [String: any Value] = [:]) {
        Aptabase.shared.trackEvent(message, with: parameters)
    }

    static func flushTelemetry() async {
        await Aptabase.shared.flushNow()
    }
}
