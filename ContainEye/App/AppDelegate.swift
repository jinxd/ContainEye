//
//  AppDelegate.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/24/25.
//


import SwiftUI
import Blackbird
import StoreKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var launched: Date? = nil

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        var req = URLRequest(url: URL(string: "https://containeye.hannesnagel.com/push-notifications/update")!)
        req.httpMethod = "PUT"
        req.httpBody = deviceToken.map { String(format: "%02x", $0) }.joined().data(using: .utf8)
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        Task {
            let _ = try? await URLSession.shared.data(for: req)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Logger.telemetry("silent push notification registration failed", with: ["error" : error.generateDescription()])
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("started background task")
        let backgroundTaskID = application.beginBackgroundTask(withName: "SilentPushBackgroundTask") {
            print("completion handler no data")
            completionHandler(.noData)
        }

        let testTask = Task {
            Logger.telemetry("received remote notification")
            let tests = (try? await ServerTest.read(from: SharedDatabase.db, matching: \.$credentialKey != "-", orderBy: .ascending(\.$lastRun), limit: 10)) ?? []
            let intent = TestServers()
            intent.tests = tests.map { $0.entity }

            let _ = try? await intent.perform()
            let _ = try? await intent.donate()
print("completion handler new data, ending bg task")
            completionHandler(.newData)
            application.endBackgroundTask(backgroundTaskID)
        }

        Task {
            try? await Task.sleep(for: .seconds(25))
            if !testTask.isCancelled {
                print("timeout, ending bg task")
                testTask.cancel()
                application.endBackgroundTask(backgroundTaskID)
            }
        }
    }

    override init() {
        Logger.initTelemetry()

        NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { _ in
            Logger.telemetry("screenshot.taken")
        }

        super.init()

        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .current) { _ in
            Task { await self.activated() }
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .current) { _ in
            Task { await self.hidden() }
        }
    }

    func activated() async {
        print("activated")
        if launched == nil {
            launched = .now
            Logger.telemetry("app.launched")
        }
    }

    func hidden() async {
        print("hidden")
        if launched != nil {
            Logger.telemetry("app.closed")
            launched = nil
        }

        let app = UIApplication.shared
        backgroundTaskID = app.beginBackgroundTask(withName: "KeepAlive") {
            app.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }

        defer {
            if backgroundTaskID != .invalid {
                app.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }

        Logger.telemetry("starting background task")
        do {
            try await Task.sleep(for: .seconds(29))
            Logger.telemetry("background task done")
        } catch {
            Logger.telemetry("background task interrupted", with: ["error": error.localizedDescription])
        }
    }

    func fetchOriginalPurchaseDate() async -> Date? {
        for await result in Transaction.all {
            if case .verified(let transaction) = result {
                return transaction.originalPurchaseDate
            }
        }
        return nil
    }
}
