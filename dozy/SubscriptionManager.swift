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

    /// Must match the App Store Connect product ids exactly.
    static let monthlyProductID = "dozy_premium_monthly"
    static let yearlyProductID = "dozy_premium_yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    @Published private(set) var monthly: Product?
    /// Nil until the yearly product exists in App Store Connect; the paywall then shows monthly only.
    @Published private(set) var yearly: Product?
    /// The plan chosen on the paywall.
    @Published var selectedID = SubscriptionManager.monthlyProductID

    /// The plan a purchase will buy: the chosen one, or whichever is on sale.
    var product: Product? {
        selectedID == Self.yearlyProductID ? (yearly ?? monthly) : (monthly ?? yearly)
    }

    /// How much cheaper a year is than twelve months, as a whole percentage.
    var yearlySavingsPercent: Int? {
        guard let monthly, let yearly, monthly.price > 0 else { return nil }
        let fullYear = monthly.price * 12
        let saved = (fullYear - yearly.price) / fullYear * 100
        let percent = NSDecimalNumber(decimal: saved).intValue
        return percent > 0 ? percent : nil
    }
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
            let products = try await Product.products(for: Self.productIDs)
            monthly = products.first { $0.id == Self.monthlyProductID }
            yearly = products.first { $0.id == Self.yearlyProductID }
            // Yearly is the default choice whenever it is on sale.
            selectedID = yearly != nil ? Self.yearlyProductID : Self.monthlyProductID
            if product == nil {
                // Empty catalog usually means the Run scheme’s StoreKit Configuration
                // isn’t loading Products.storekit (wrong path / file outside the synced folder).
                errorMessage = "Subscription isn’t available right now. Try again later."
                print("[Dozy] StoreKit returned 0 products for \(Self.productIDs.sorted()). Edit Scheme → Run → Options → StoreKit Configuration must point at dozy/Products.storekit (not red).")
            } else {
                errorMessage = nil
                print("[Dozy] Loaded StoreKit product \(product!.id) @ \(product!.displayPrice)")
            }
        } catch {
            errorMessage = "Couldn’t load subscription options."
            print("[Dozy] StoreKit product load failed: \(error)")
        }
    }

    #if DEBUG
    /// Unlocks the app locally when StoreKit Configuration fails to load in Simulator.
    func unlockForLocalTesting() {
        isEntitled = true
        isInTrial = true
        expirationDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
        errorMessage = nil
        print("[Dozy] DEBUG unlockForLocalTesting() — not a real StoreKit purchase")
    }
    #endif

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
            guard Self.productIDs.contains(transaction.productID) else { continue }
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
                guard Self.productIDs.contains(renewal.currentProductID) else { continue }

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
