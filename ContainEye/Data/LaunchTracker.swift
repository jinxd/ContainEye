//
//  LaunchTracker.swift
//  ContainEye
//
//  Created by Hannes Nagel on 3/24/25.
//

import Foundation
import StoreKit
import Blackbird

enum LaunchTracker {
    private static let launchCountKey = "appLaunchCount"
    private static let firstLaunchDateKey = "firstLaunchDate"
    private static let lastReviewRequestDateKey = "lastReviewRequestDate"

    // Configuration: when to prompt for review
    private static let minimumLaunchCount = 5
    private static let daysBetweenPrompts = 90

    /// Call this when the app is activated
    static func recordLaunch() {
        let currentCount = UserDefaults.standard.integer(forKey: launchCountKey)
        UserDefaults.standard.set(currentCount + 1, forKey: launchCountKey)

        // Record first launch date if not set
        if UserDefaults.standard.object(forKey: firstLaunchDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchDateKey)
        }
    }

    /// Check if we should request a review
    static func shouldRequestReview() async -> Bool {
        // Check launch count threshold
        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        guard launchCount >= minimumLaunchCount else {
            return false
        }

        // Check if we've asked recently
        if let lastRequestDate = UserDefaults.standard.object(forKey: lastReviewRequestDateKey) as? Date {
            let daysSinceLastRequest = Calendar.current.dateComponents([.day], from: lastRequestDate, to: Date()).day ?? 0
            guard daysSinceLastRequest >= daysBetweenPrompts else {
                return false
            }
        }

        // Check if user has servers (they're actually using the app)
        do {
            let serverCount = try await Server.count(in: SharedDatabase.db)
            guard serverCount > 0 else {
                return false
            }
        } catch {
            return false
        }

        return true
    }

    /// Request a review from the user
    @MainActor
    static func requestReview() {
        // Record that we asked
        UserDefaults.standard.set(Date(), forKey: lastReviewRequestDateKey)

        // Request review using StoreKit
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }

    /// Check and potentially request review (call this on app activation)
    @MainActor
    static func checkAndRequestReview() async {
        guard await shouldRequestReview() else {
            return
        }

        requestReview()
    }

    // MARK: - Debug helpers

    #if DEBUG
    static func resetTracking() {
        UserDefaults.standard.removeObject(forKey: launchCountKey)
        UserDefaults.standard.removeObject(forKey: firstLaunchDateKey)
        UserDefaults.standard.removeObject(forKey: lastReviewRequestDateKey)
    }

    static func getDebugInfo() -> String {
        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date
        let lastRequest = UserDefaults.standard.object(forKey: lastReviewRequestDateKey) as? Date

        var info = "Launch Count: \(launchCount)\n"
        if let firstLaunch {
            info += "First Launch: \(firstLaunch.formatted())\n"
        } else {
            info += "First Launch: Never\n"
        }
        if let lastRequest {
            info += "Last Review Request: \(lastRequest.formatted())\n"
        } else {
            info += "Last Review Request: Never\n"
        }

        return info
    }
    #endif
}
