//
//  PaywallView.swift
//  dozy
//
//  "Keep your plan": the last step after onboarding, and the gate whenever
//  there is no active subscription.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager

    var body: some View {
        VStack(spacing: 14) {
            GlowOrb(size: 84)
                .padding(.top, 28)
                .padding(.bottom, 8)

            Text("Keep your plan.")
                .font(Theme.brand(38))
                .foregroundStyle(Theme.text)

            Text(hasTrial ? "Free for 3 days. Cancel anytime." : "Cancel anytime.")
                .font(Theme.body(17))
                .foregroundStyle(Theme.secondary)

            CheckList(rows: [("Your payoff date and daily action", true),
                             ("Morning summary on your Lock Screen", true),
                             ("Oura, Garmin and Whoop sync", true)])
                .padding(.top, 6)

            VStack(spacing: 10) {
                if let yearly = subscriptions.yearly {
                    planRow(id: SubscriptionManager.yearlyProductID,
                            name: "Yearly",
                            badge: subscriptions.yearlySavingsPercent.map { "SAVE \($0)%" },
                            product: yearly, period: "year")
                }
                if let monthly = subscriptions.monthly {
                    planRow(id: SubscriptionManager.monthlyProductID,
                            name: "Monthly",
                            badge: nil,
                            product: monthly, period: "month")
                }
            }

            if let errorMessage = subscriptions.errorMessage {
                Text(errorMessage)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.debtPink)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            PrimaryButton(title: ctaTitle, isBusy: subscriptions.isPurchasing) {
                Task { await subscriptions.purchase() }
            }
            .disabled(subscriptions.product == nil)
            .opacity(subscriptions.product == nil ? 0.5 : 1)

            Button {
                Task { await subscriptions.restore() }
            } label: {
                Text("Restore Purchases")
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.cyan)
            }
            .disabled(subscriptions.isPurchasing)

            #if DEBUG
            if subscriptions.product == nil {
                Button {
                    subscriptions.unlockForLocalTesting()
                } label: {
                    Text("DEBUG: Continue without StoreKit")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            #endif

            Text("Manage or cancel in Settings → Apple ID → Subscriptions.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task {
            if subscriptions.product == nil {
                await subscriptions.loadProducts()
            }
        }
    }

    private var hasTrial: Bool {
        subscriptions.product?.subscription?.introductoryOffer != nil
    }

    private var ctaTitle: String {
        if hasTrial { return "Start 3-Day Free Trial" }
        let yearlyChosen = subscriptions.product?.id == SubscriptionManager.yearlyProductID
        return "Subscribe · \(subscriptions.priceText)/\(yearlyChosen ? "yr" : "mo")"
    }

    /// One plan on sale. Tapping it selects it; the selected one has the cyan outline.
    private func planRow(id: String, name: String, badge: String?, product: Product, period: String) -> some View {
        let isSelected = subscriptions.product?.id == id
        let trial = product.subscription?.introductoryOffer != nil
        return Button {
            subscriptions.selectedID = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(Theme.body(17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if let badge {
                            Text(badge)
                                .font(Theme.body(11, weight: .bold))
                                .tracking(0.3)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text(trial
                         ? "3 days free, then \(product.displayPrice) per \(period)"
                         : "\(product.displayPrice) per \(period)")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Theme.cyan : Theme.secondary)
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Theme.cyan : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
