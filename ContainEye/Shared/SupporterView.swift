//
//  SupporterView.swift
//  ContainEye
//
//  Created by Claude Code
//

import SwiftUI
import StoreKit
import ButtonKit

struct SupporterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.storeKitManager) private var storeManager
    @State private var isPurchasing = false

    var body: some View {
        ScrollView {
            VStack {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(.red.gradient)
                        .symbolEffect(.pulse)

                    Text("Become a Supporter")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("ContainEye is free and open source. Support the development with a small donation!")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top)

                // Current Status
                if storeManager.hasActiveSubscription {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)

                        Text("Thank You!")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.green.opacity(0.1))
                            .stroke(.green.opacity(0.3), lineWidth: 2)
                    )
                    .padding(.horizontal)
                }

                // Subscription Options
                VStack {
                    ForEach(storeManager.products, id: \.id) { product in
                        SubscriptionCard(
                            product: product,
                            isPurchasing: isPurchasing,
                            isActive: storeManager.purchasedSubscriptions.contains(product.id)
                        ) {
                            await purchaseProduct(product)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 50)
                // Benefits Section
                VStack(alignment: .leading) {
                    Text("Why Support?")
                        .font(.title2)
                        .fontWeight(.semibold)

                    BenefitRow(icon: "heart.fill", text: "Support ongoing development", color: .red)
                    BenefitRow(icon: "wrench.and.screwdriver.fill", text: "Help maintain the app", color: .orange)
                    BenefitRow(icon: "sparkles", text: "Enable new features", color: .yellow)
                    BenefitRow(icon: "shield.fill", text: "Keep ContainEye free for everyone", color: .blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                )
                .padding(.horizontal)

                // Restore Button
                Button {
                    Task {
                        await restorePurchases()
                    }
                } label: {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom)

                // Legal Links
                HStack(spacing: 20) {
                    Link("Privacy Policy", destination: URL(string: "https://hannesnagel.com/containeye/privacy")!)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Footer
                Text("ContainEye will always be free and open source. Your support helps keep it that way!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .navigationTitle("Supporter")
        .navigationBarTitleDisplayMode(.inline)
        .trackView("supporter")
    }

    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        _ = try? await storeManager.purchase(product)
    }

    private func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }

        await storeManager.restorePurchases()
    }
}

struct SubscriptionCard: View {
    let product: Product
    let isPurchasing: Bool
    let isActive: Bool
    let onPurchase: () async -> Void

    private var isMonthly: Bool {
        product.id == "containeye.monthly"
    }

    private var isLargeYearly: Bool {
        product.id == "containeye.largeyearly"
    }

    private var highlightColor: Color {
        if isLargeYearly {
            return .purple
        } else if !isMonthly {
            return .blue
        }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(highlightColor)

                    if let subscription = product.subscription {
                        Text(subscription.subscriptionPeriod.localizedDescription())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !isActive {
                    AsyncButton {
                        await onPurchase()
                    } label: {
                            Text("Subscribe")
                                .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(highlightColor)
                    .disabled(isPurchasing)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .stroke(isActive ? .green : highlightColor.opacity(0.3), lineWidth: isActive ? 5 : (isMonthly ? 1 : isLargeYearly ? 3 : 2))
        )
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.body)
        }
    }
}

// Helper extension for subscription period localization
extension Product.SubscriptionPeriod {
    func localizedDescription() -> String {
        switch self.unit {
        case .day:
            return value == 1 ? "per day" : "every \(value) days"
        case .week:
            return value == 1 ? "per week" : "every \(value) weeks"
        case .month:
            return value == 1 ? "per month" : "every \(value) months"
        case .year:
            return value == 1 ? "per year" : "every \(value) years"
        @unknown default:
            return ""
        }
    }
}

#Preview {
    SupporterView()
}
