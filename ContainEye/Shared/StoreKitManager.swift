//
//  StoreKitManager.swift
//  ContainEye
//
//  Created by Claude Code
//

import Foundation
import StoreKit
import SwiftUI

@MainActor
@Observable
class StoreKitManager {
    static let shared = StoreKitManager()

    var products: [Product] = []
    var purchasedSubscriptions: Set<String> = ["loading"]
    var subscriptionStatus: Product.SubscriptionInfo.Status?

    private var updateListenerTask: Task<Void, Error>?

    private init() {
        updateListenerTask = listenForTransactions()

        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    @MainActor deinit {
        updateListenerTask?.cancel()
    }

    // Product IDs from the .storekit file
    private let productIDs = [
        "containeye.monthly",
        "containeye.yearly",
        "containeye.largeyearly"
    ]

    func loadProducts() async {
        do {
            let products = try await Product.products(for: productIDs)
            self.products = products.sorted { product1, product2 in
                // Sort by price: monthly, yearly, large yearly
                guard let price1 = Decimal(string: product1.displayPrice.filter { $0.isNumber || $0 == "." }),
                      let price2 = Decimal(string: product2.displayPrice.filter { $0.isNumber || $0 == "." }) else {
                    return false
                }
                return price1 < price2
            }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateSubscriptionStatus()
            await transaction.finish()
            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            print("Failed to restore purchases: \(error)")
        }
    }

    func updateSubscriptionStatus() async {
        var purchasedSubscriptions: Set<String> = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if transaction.revocationDate == nil {
                    purchasedSubscriptions.insert(transaction.productID)
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }

        self.purchasedSubscriptions = purchasedSubscriptions

        // Get the subscription status for the current subscription group
        if let product = products.first(where: { purchasedSubscriptions.contains($0.id) }) {
            self.subscriptionStatus = try? await product.subscription?.status.first
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    await self.updateSubscriptionStatus()

                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    var hasActiveSubscription: Bool {
        !purchasedSubscriptions.isEmpty
    }
}

enum StoreError: Error {
    case failedVerification
}
