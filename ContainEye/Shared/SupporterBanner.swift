//
//  SupporterBanner.swift
//  ContainEye
//
//  Created by Claude Code
//

import SwiftUI

struct SupporterBanner: View {
    @State private var storeManager = StoreKitManager.shared
    @State private var isDismissed = false
    @Environment(\.namespace) var namespace

    // UserDefaults keys
    private let lastDismissedKey = "supporterBannerLastDismissed"
    private let dismissIntervalDays = 90.0 // Show again after 3 months

    var body: some View {
        if shouldShowBanner && !isDismissed {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: "heart.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red.gradient)
                        .symbolEffect(.pulse)

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Support ContainEye")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Help keep this app free and open source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Dismiss button
                    Button {
                        withAnimation(.smooth) {
                            dismissBanner()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.red.opacity(0.1))
                        .stroke(.red.opacity(0.3), lineWidth: 1)
                )

                // Action button
                NavigationLink(value: Sheet.supporter) {
                    HStack {
                        Text("Become a Supporter")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.red.gradient)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var shouldShowBanner: Bool {
        // Don't show if user already has an active subscription
        if storeManager.hasActiveSubscription {
            return false
        }

        // Check if banner was dismissed recently
        if let lastDismissed = UserDefaults.standard.object(forKey: lastDismissedKey) as? Date {
            let daysSinceDismissal = Date().timeIntervalSince(lastDismissed) / (60 * 60 * 24)
            return daysSinceDismissal >= dismissIntervalDays
        }

        // Show banner if never dismissed before
        return true
    }

    private func dismissBanner() {
        isDismissed = true
        UserDefaults.standard.set(Date(), forKey: lastDismissedKey)
    }
}

#Preview {
    NavigationStack {
        VStack {
            SupporterBanner()
            Spacer()
        }
    }
}
