//
//  SubscriptionManager.swift
//  dozy
//
//  StoreKit 2 subscription entitlement for Dozy Premium.
//

import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {

    /// Must match the App Store Connect product id exactly.
    static let monthlyProductID = "dozy_premium_monthly"

    @Published private(set) var product: Product?
    @Published private(set) var isEntitled = false
    @Published private(set) var isInTrial = false
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isLoading = true
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Bootstrap

    /// Load the catalog and resolve current entitlement. Call once at launch.
    func start() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.monthlyProductID])
            product = products.first
            if product == nil {
                errorMessage = "Subscription isn’t available right now. Try again later."
            }
        } catch {
            errorMessage = "Couldn’t load subscription options."
        }
    }

    // MARK: - Purchase / restore

    func purchase() async {
        guard let product else {
            errorMessage = "Subscription isn’t available right now."
            return
        }

        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase didn’t go through. Please try again."
        }
    }

    func restore() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isEntitled {
                errorMessage = "No active subscription found for this Apple ID."
            }
        } catch {
            errorMessage = "Couldn’t restore purchases. Please try again."
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var entitled = false
        var trial = false
        var expiry: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productID == Self.monthlyProductID else { continue }
            guard transaction.revocationDate == nil else { continue }

            entitled = true
            expiry = transaction.expirationDate
            if transaction.offer?.type == .introductory {
                trial = true
            }
        }

        // Prefer Product.SubscriptionInfo when available — more accurate trial state.
        if let product,
           let statuses = try? await product.subscription?.status {
            for status in statuses {
                guard case .verified(let renewal) = status.renewalInfo,
                      case .verified(let transaction) = status.transaction else { continue }
                guard renewal.currentProductID == Self.monthlyProductID else { continue }

                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    entitled = true
                    expiry = transaction.expirationDate
                    if renewal.offer?.type == .introductory {
                        trial = true
                    }
                case .expired, .revoked:
                    break
                default:
                    break
                }
            }
        }

        isEntitled = entitled
        isInTrial = entitled && trial
        expirationDate = expiry
    }

    // MARK: - Display helpers

    var priceText: String {
        if let product { return product.displayPrice }
        return "$19.00"
    }

    var trialBadgeText: String {
        "3-day free trial, then \(priceText)/month"
    }

    var statusDetailText: String {
        if isInTrial {
            if let expirationDate {
                return "Free trial · ends \(Self.shortDate(expirationDate))"
            }
            return "Free trial active"
        }
        if isEntitled {
            if let expirationDate {
                return "Dozy Premium · renews \(Self.shortDate(expirationDate))"
            }
            return "Dozy Premium active"
        }
        return "No active subscription"
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
