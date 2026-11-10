//
//  PaywallView.swift
//  dozy
//
//  Full-app gate after the free trial / before subscription.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var appeared = false

    var body: some View {
        ZStack {
            DozyBackground()

            VStack(spacing: 0) {
                Spacer()

                Text("Dozy")
                    .font(Theme.serif(56))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)

                Text("Unlock your sleep plan")
                    .font(Theme.serif(20))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)

                GlowOrb(size: 130)
                    .padding(.top, 40)
                    .scaleEffect(appeared ? 1 : 0.88)
                    .opacity(appeared ? 1 : 0)

                planCard
                    .padding(.top, 40)
                    .padding(.horizontal, 28)
                    .opacity(appeared ? 1 : 0)

                if let errorMessage = subscriptions.errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(13))
                        .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 14)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        Task { await subscriptions.purchase() }
                    } label: {
                        HStack(spacing: 10) {
                            if subscriptions.isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(ctaTitle)
                                .font(Theme.serif(18))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.1, green: 0.45, blue: 1.0),
                                    Color(red: 0.04, green: 0.30, blue: 0.95)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .disabled(subscriptions.isPurchasing || subscriptions.product == nil)

                    Button {
                        Task { await subscriptions.restore() }
                    } label: {
                        Text("Restore Purchases")
                            .font(Theme.body(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .disabled(subscriptions.isPurchasing)

                    Text("Cancel anytime in Settings → Apple ID → Subscriptions.")
                        .font(Theme.body(12))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if subscriptions.product == nil {
                await subscriptions.loadProducts()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { appeared = true }
        }
    }

    private var ctaTitle: String {
        if subscriptions.product?.subscription?.introductoryOffer != nil {
            return "Start 3-day free trial"
        }
        return "Subscribe · \(subscriptions.priceText)/mo"
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dozy Premium")
                    .font(Theme.serif(22))
                    .foregroundStyle(.white)
                Spacer()
                Text("Monthly")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.cyan)
            }

            Text(subscriptions.trialBadgeText)
                .font(Theme.body(15))
                .foregroundStyle(.white.opacity(0.75))

            VStack(alignment: .leading, spacing: 10) {
                benefitRow("Sleep debt from Apple Health")
                benefitRow("Personalized nap windows")
                benefitRow("Full access after a 3-day trial")
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.cyan)
            Text(text)
                .font(Theme.body(14))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
