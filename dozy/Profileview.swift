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
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var notificationsEnabled = false
    @State private var morningSummaryOn = MorningBrief.isEnabled
    @State private var wakeTime = ProfileView.time(minutes: PlanPreferences.wakeMinutes ?? 7 * 60)
    @State private var ouraConnected = Account.isCloudSourceConnected("oura")
    @State private var garminConnected = Account.isCloudSourceConnected("garmin")
    @State private var whoopConnected = Account.isCloudSourceConnected("whoop_v2")
    @State private var cloudNeedsSignIn = AppSession.needsSignIn
    @State private var connectingProvider: String? = nil
    @State private var connectError: String? = nil
    @State private var isRestoring = false
    @State private var linkSession: JunctionLinkSession? = nil
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var accountError: String? = nil
    @State private var exportFile: URL? = nil

    private let accent = Theme.cyan
    private static let privacyURL = URL(string: "https://www.appdozy.com/privacy")!

    private static func time(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(title: "You", date: "Account")
                    .padding(.bottom, 16)

                accountCard

                if !SubscriptionManager.isFreeLaunch {
                    subscriptionCard.padding(.top, 24)
                }

                sectionTitle("Sleep Sources")
                group {
                    sourceRow(title: "Apple Health", connected: true, isBusy: false, action: nil)
                    divider
                    sourceRow(title: "Oura", connected: ouraConnected,
                              isBusy: connectingProvider == "oura",
                              action: cloudAction("oura", connected: ouraConnected))
                    divider
                    sourceRow(title: "Garmin", connected: garminConnected,
                              isBusy: connectingProvider == "garmin",
                              action: cloudAction("garmin", connected: garminConnected))
                    if Account.isWhoopAvailable {
                        divider
                        sourceRow(title: "Whoop", connected: whoopConnected,
                                  isBusy: connectingProvider == "whoop_v2",
                                  action: cloudAction("whoop_v2", connected: whoopConnected))
                    }
                }
                if let connectError {
                    footnote(connectError, color: Theme.debtRed)
                } else {
                    footnote("Trackers often reach Dozy through Apple Health already. Connect one here for a direct sync.")
                }

                sectionTitle("Plan")
                group {
                    DatePicker("Wake Time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.text)
                        .tint(accent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 50)
                        .onChange(of: wakeTime) { _, newValue in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            PlanPreferences.wakeMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                            Task { await sleepVM.load() }
                        }
                    divider
                    toggleRow("Morning Summary", isOn: $morningSummaryOn)
                        .onChange(of: morningSummaryOn) { _, newValue in
                            MorningBrief.isEnabled = newValue
                            if newValue {
                                UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .sound]) { _, _ in }
                            }
                        }
                    divider
                    toggleRow("Nap Alarms", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            if newValue { requestNotifications() }
                            else { openSettingsHint() }
                        }
                }
                footnote("Tonight’s bedtime is worked back from your wake time.")

                sectionTitle("About")
                group {
                    NavigationLink { HowDozyWorksView() } label: { linkRow("How Dozy Works") }
                        .buttonStyle(.plain)
                    divider
                    if let exportFile {
                        ShareLink(item: exportFile) { linkRow("Export My Data") }
                            .buttonStyle(.plain)
                    } else {
                        linkRow("Export My Data").opacity(0.4)
                    }
                    divider
                    Link(destination: Self.privacyURL) { linkRow("Privacy") }
                        .buttonStyle(.plain)
                }

                sectionTitle("Account")
                group {
                    Button { confirmingSignOut = true } label: {
                        actionRow("Sign Out", color: accent)
                    }
                    .buttonStyle(.plain)
                    divider
                    Button { confirmingDelete = true } label: {
                        HStack {
                            actionRow("Delete Account", color: Theme.debtRed)
                            if isDeleting { ProgressView().tint(Theme.secondary).padding(.trailing, 16) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
                if let accountError {
                    footnote(accountError, color: Theme.debtRed)
                } else {
                    footnote("Deleting your account disconnects your trackers and erases the sleep data Dozy’s server holds. Apple Health is not affected.")
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 32)
        }
        // 1pt keeps scrolled content from sliding under the status bar.
        .padding(.top, 1)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            refreshNotificationStatus()
            ouraConnected = Account.isCloudSourceConnected("oura")
            garminConnected = Account.isCloudSourceConnected("garmin")
            whoopConnected = Account.isCloudSourceConnected("whoop_v2")
            cloudNeedsSignIn = AppSession.needsSignIn
            exportFile = writeExport()
        }
        .confirmationDialog("Sign out of Dozy?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Account.signOut()
                hasOnboarded = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sleep data stays in Apple Health. Sign in again to pick up where you left off.")
        }
        .confirmationDialog("Delete your Dozy account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This disconnects your trackers, erases the sleep data on Dozy’s server and clears Dozy on this phone. It can’t be undone.")
        }
    }

    // MARK: - Grouped list pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.body(13))
            .foregroundStyle(Theme.secondary)
            .padding(.leading, 16)
            .padding(.top, 28)
            .padding(.bottom, 8)
    }

    private func footnote(_ text: String, color: Color = Theme.secondary) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16)
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).font(Theme.body(17)).foregroundStyle(Theme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private func actionRow(_ title: String, color: Color) -> some View {
        HStack {
            Text(title).font(Theme.body(17)).foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(Theme.body(17)).foregroundStyle(Theme.text)
        }
        .tint(accent)
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }

    private func sourceRow(title: String, connected: Bool, isBusy: Bool,
                           action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 6) {
                Text(title).font(Theme.body(17)).foregroundStyle(Theme.text)
                Spacer()
                if isBusy {
                    ProgressView().tint(accent)
                } else if connected && action == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(accent)
                    Text("Connected").font(Theme.body(17)).foregroundStyle(Theme.secondary)
                } else {
                    Text(connected ? "Sign In Again" : "Connect")
                        .font(Theme.body(17))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil || isBusy)
    }

    // MARK: - Account actions

    private func deleteAccount() {
        isDeleting = true
        accountError = nil
        Task {
            do {
                try await Account.delete()
                hasOnboarded = false
            } catch {
                if !AppSession.isSignInCancelled(error) {
                    accountError = "Couldn’t delete the account: \(error.localizedDescription)"
                }
            }
            isDeleting = false
        }
    }

    /// Writes the export to a temporary file so the share sheet has something to hand over.
    private func writeExport() -> URL? {
        guard !sleepVM.debtHistory.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dozy Sleep Export.csv")
        do {
            try sleepVM.exportCSV().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Account card

    private var accountCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(LinearGradient(colors: [accent, Theme.accentBlue],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(
                    Text(initials)
                        .font(Theme.body(20, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(Account.name ?? "Welcome")
                    .font(Theme.body(20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(Account.email
                     ?? (Account.provider == "google" ? "Signed in with Google" : "Signed in with Apple"))
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .healthCard()
    }

    // MARK: - Subscription

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Subscription")
                .font(Theme.serif(20))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscriptions.isEntitled ? "Dozy Premium" : "Inactive")
                            .font(Theme.serif(17))
                            .foregroundStyle(Theme.text)
                        Text(subscriptions.statusDetailText)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: subscriptions.isEntitled
                          ? "checkmark.seal.fill"
                          : "exclamationmark.circle")
                        .foregroundStyle(subscriptions.isEntitled ? accent : Theme.secondary)
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
                            ProgressView().tint(Theme.secondary)
                        }
                        Text("Restore Purchases")
                            .font(Theme.body(14, weight: .medium))
                            .foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.track)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isRestoring || subscriptions.isPurchasing)

                if let errorMessage = subscriptions.errorMessage {
                    Text(errorMessage)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.debtRed)
                }
            }
            .padding(18)
            .background(Theme.card)
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
            try await AppSession.renew()
            cloudNeedsSignIn = false
            return try await JunctionAPI.createLinkURL(clientUserId: clientUserId, provider: provider)
        }
    }

    private func resumeCloudSync(_ provider: String) {
        connectingProvider = provider
        connectError = nil

        Task {
            do {
                try await AppSession.renew()
                await sleepVM.load()
            } catch {
                if !AppSession.isSignInCancelled(error) {
                    connectError = error.localizedDescription
                }
            }
            connectingProvider = nil
            cloudNeedsSignIn = AppSession.needsSignIn
        }
    }

    private func connectCloudSource(_ provider: String) {
        guard let clientUserId = Account.userID, !clientUserId.isEmpty else {
            connectError = "Sign in again so Dozy can link this tracker."
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
                            var slug = connectedProvider ?? provider
                            if slug == "whoop" { slug = "whoop_v2" }
                            Account.setCloudSourceConnected(slug, true)
                            if slug == "oura" { ouraConnected = true }
                            if slug == "garmin" { garminConnected = true }
                            if slug == "whoop_v2" { whoopConnected = true }
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
                    if !AppSession.isSignInCancelled(error) {
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
