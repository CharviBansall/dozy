//
//  Profileview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import AuthenticationServices
import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var sleepVM: SleepViewModel
    @State private var notificationsEnabled = false
    @State private var healthConnected = true   // app reads HealthKit by design
    @State private var ouraConnected = Account.isCloudSourceConnected("oura")
    @State private var garminConnected = Account.isCloudSourceConnected("garmin")
    @State private var cloudNeedsSignIn = AppSession.needsSignIn
    @State private var connectingProvider: String? = nil
    @State private var connectError: String? = nil
    @State private var isRestoring = false
    @State private var linkSession: JunctionLinkSession? = nil

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

                VStack(spacing: 10) {
                    sourceRow(
                        icon: "heart.fill",
                        iconColor: Color(red: 0.95, green: 0.3, blue: 0.35),
                        title: "Apple Health",
                        subtitle: healthConnected
                            ? "Connected — reading your sleep"
                            : "Not connected",
                        connected: healthConnected,
                        isBusy: false,
                        action: nil
                    )

                    sourceRow(
                        icon: "circle.hexagongrid.fill",
                        iconColor: Color(red: 0.55, green: 0.45, blue: 0.95),
                        title: "Oura",
                        subtitle: cloudSubtitle("Oura", connected: ouraConnected),
                        connected: ouraConnected,
                        isBusy: connectingProvider == "oura",
                        actionLabel: ouraConnected ? "Sign in" : "Connect",
                        action: cloudAction("oura", connected: ouraConnected)
                    )

                    sourceRow(
                        icon: "watch.analog",
                        iconColor: Color(red: 0.25, green: 0.55, blue: 0.95),
                        title: "Garmin",
                        subtitle: cloudSubtitle("Garmin", connected: garminConnected),
                        connected: garminConnected,
                        isBusy: connectingProvider == "garmin",
                        actionLabel: garminConnected ? "Sign in" : "Connect",
                        action: cloudAction("garmin", connected: garminConnected)
                    )
                }

                if let connectError {
                    Text(connectError)
                        .font(Theme.body(12))
                        .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.5))
                }

                Text("Oura and Garmin often already appear via Apple Health. Connect here if you want a direct cloud sync.")
                    .font(Theme.body(13))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .onAppear {
            refreshNotificationStatus()
            ouraConnected = Account.isCloudSourceConnected("oura")
            garminConnected = Account.isCloudSourceConnected("garmin")
            cloudNeedsSignIn = AppSession.needsSignIn
        }
    }

    // MARK: - Source row

    private func sourceRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        connected: Bool,
        isBusy: Bool,
        actionLabel: String = "Connect",
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(Theme.serif(22))
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.serif(16))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if isBusy {
                    ProgressView().tint(accent)
                } else if action != nil {
                    Text(actionLabel)
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(accent)
                } else if connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(action == nil || isBusy)
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

    // MARK: - Junction cloud connect

    private func cloudSubtitle(_ name: String, connected: Bool) -> String {
        guard connected else { return "Connect your \(name) account" }
        return cloudNeedsSignIn ? "Sign in again to keep syncing" : "Connected — cloud sleep"
    }

    /// Not connected: start the connect flow. Connected but the server wants a new session:
    /// sign in again. Otherwise the row has nothing to do.
    private func cloudAction(_ provider: String, connected: Bool) -> (() -> Void)? {
        if !connected { return { connectCloudSource(provider) } }
        if cloudNeedsSignIn { return { resumeCloudSync(provider) } }
        return nil
    }

    /// Asks for the tracker link, signing in to Dozy again first if the server requires it.
    private func linkURL(clientUserId: String, provider: String) async throws -> URL {
        do {
            return try await JunctionAPI.createLinkURL(clientUserId: clientUserId, provider: provider)
        } catch where JunctionAPI.isSignInRequired(error) {
            try await AppSession.renewWithApple()
            cloudNeedsSignIn = false
            return try await JunctionAPI.createLinkURL(clientUserId: clientUserId, provider: provider)
        }
    }

    private func resumeCloudSync(_ provider: String) {
        connectingProvider = provider
        connectError = nil

        Task {
            do {
                try await AppSession.renewWithApple()
                await sleepVM.load()
            } catch {
                if !AppSession.isAppleSheetCancelled(error) {
                    connectError = error.localizedDescription
                }
            }
            connectingProvider = nil
            cloudNeedsSignIn = AppSession.needsSignIn
        }
    }

    private func connectCloudSource(_ provider: String) {
        guard let clientUserId = Account.userID, !clientUserId.isEmpty else {
            connectError = "Sign in with Apple again so Dozy can link this tracker."
            return
        }

        connectingProvider = provider
        connectError = nil

        Task {
            do {
                let url = try await linkURL(clientUserId: clientUserId, provider: provider)
                await MainActor.run {
                    let session = JunctionLinkSession()
                    linkSession = session
                    session.start(url: url) { result in
                        connectingProvider = nil
                        linkSession = nil
                        switch result {
                        case .success(let connectedProvider):
                            let slug = connectedProvider ?? provider
                            Account.setCloudSourceConnected(slug, true)
                            if slug == "oura" { ouraConnected = true }
                            if slug == "garmin" { garminConnected = true }
                            Task { await sleepVM.load() }
                        case .failure(let error):
                            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                                return
                            }
                            connectError = error.localizedDescription
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    connectingProvider = nil
                    cloudNeedsSignIn = AppSession.needsSignIn
                    if !AppSession.isAppleSheetCancelled(error) {
                        connectError = error.localizedDescription
                    }
                }
            }
        }
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

// MARK: - Junction Link session

final class JunctionLinkSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func start(url: URL, completion: @escaping (Result<String?, Error>) -> Void) {
        let auth = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "dozy"
        ) { callbackURL, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let callbackURL else {
                completion(.failure(URLError(.badURL)))
                return
            }
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
            let state = items?.first(where: { $0.name == "state" })?.value
            let provider = items?.first(where: { $0.name == "provider" })?.value
            if state == "success" {
                completion(.success(provider))
            } else {
                let message = items?.first(where: { $0.name == "error" })?.value
                    ?? "Connection didn’t finish."
                completion(.failure(NSError(
                    domain: "JunctionLink",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )))
            }
        }
        auth.prefersEphemeralWebBrowserSession = false
        auth.presentationContextProvider = self
        session = auth
        auth.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
    }
}
