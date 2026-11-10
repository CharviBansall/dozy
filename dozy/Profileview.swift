//
//  Profileview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var notificationsEnabled = false
    @State private var healthConnected = true   // app reads HealthKit by design
    @State private var isRestoring = false

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: .now)
    }

    private let accent = Color(red: 0.30, green: 0.80, blue: 0.85)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(title: "Profile", date: dateString)

                accountCard

                subscriptionCard

                // Notifications
                Text("Notifications")
                    .font(Theme.serif(20))
                    .foregroundStyle(.white)

                Toggle(isOn: $notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nap alarms")
                            .font(Theme.serif(16))
                            .foregroundStyle(.white)
                        Text("Wake you when a nap is complete.")
                            .font(Theme.body(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .tint(accent)
                .padding(18)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onChange(of: notificationsEnabled) { _, newValue in
                    if newValue { requestNotifications() }
                    else { openSettingsHint() }
                }

                // Data sources
                Text("Data")
                    .font(Theme.serif(20))
                    .foregroundStyle(.white)

                HStack(spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(Theme.serif(22))
                        .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.35))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health")
                            .font(Theme.serif(16))
                            .foregroundStyle(.white)
                        Text(healthConnected ? "Connected — reading your sleep"
                                             : "Not connected")
                            .font(Theme.body(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: healthConnected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(healthConnected ? accent : .white.opacity(0.3))
                }
                .padding(18)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("Trackers like Oura or Whoop appear here automatically once they're syncing to Apple Health.")
                    .font(Theme.body(13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .onAppear { refreshNotificationStatus() }
    }

    // MARK: - Account card

    private var accountCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(LinearGradient(colors: [accent, Color(red: 0.05, green: 0.4, blue: 0.95)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 56, height: 56)
                .overlay(
                    Text(initials)
                        .font(Theme.serif(22))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(Account.name ?? "Welcome")
                    .font(Theme.serif(20))
                    .foregroundStyle(.white)
                if let email = Account.email {
                    Text(email)
                        .font(Theme.body(14))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text("Signed in with Apple")
                        .font(Theme.body(14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Subscription

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Subscription")
                .font(Theme.serif(20))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscriptions.isEntitled ? "Dozy Premium" : "Inactive")
                            .font(Theme.serif(17))
                            .foregroundStyle(.white)
                        Text(subscriptions.statusDetailText)
                            .font(Theme.body(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: subscriptions.isEntitled
                          ? "checkmark.seal.fill"
                          : "exclamationmark.circle")
                        .foregroundStyle(subscriptions.isEntitled ? accent : .white.opacity(0.35))
                }

                Button {
                    Task {
                        isRestoring = true
                        await subscriptions.restore()
                        isRestoring = false
                    }
                } label: {
                    HStack {
                        if isRestoring || subscriptions.isPurchasing {
                            ProgressView().tint(.white)
                        }
                        Text("Restore Purchases")
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isRestoring || subscriptions.isPurchasing)

                if let errorMessage = subscriptions.errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(12))
                        .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.5))
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var initials: String {
        guard let name = Account.name, !name.isEmpty else { return "D" }
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }

    // MARK: - Notifications

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = (settings.authorizationStatus == .authorized)
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    notificationsEnabled = granted
                    if !granted { openSettingsHint() }
                }
            }
    }

    /// If already decided, iOS won't re-prompt — send the user to Settings.
    private func openSettingsHint() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
