//
//  Onboardingflow.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
//  Onboarding gives before it asks: connect sleep, see what you owe, shape the
//  plan, and only then sign in. The paywall follows (see PaywallView).
//
import SwiftUI
import AuthenticationServices

// MARK: - Shared pieces

/// The dark navy backdrop from Dozy's first design. Kept for reference; unused.
struct DozyBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
            RadialGradient(
                colors: [Color(red: 0.05, green: 0.22, blue: 0.38).opacity(0.9),
                         Color(red: 0.07, green: 0.07, blue: 0.09)],
                center: .init(x: 0.3, y: 0.4),
                startRadius: 20, endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

/// The signature glowing blue orb.
struct GlowOrb: View {
    var size: CGFloat = 150
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.30, green: 0.80, blue: 0.85),
                             Color(red: 0.04, green: 0.36, blue: 0.98)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.45),
                    radius: size * 0.27, x: 0, y: size * 0.05)
    }
}

/// The main button on every onboarding screen and the paywall.
struct PrimaryButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy { ProgressView().tint(.white) }
                Text(title)
                    .font(Theme.body(17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Theme.accentBlue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isBusy)
    }
}

/// A white grouped list of ticked (or still open) lines.
struct CheckList: View {
    /// Each row: the text, and whether it is done.
    let rows: [(text: String, done: Bool)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(row.done ? Theme.cyan : Theme.secondary)
                    Text(row.text)
                        .font(Theme.body(17, weight: row.done ? .regular : .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if index < rows.count - 1 {
                    Theme.line.frame(height: 1).padding(.leading, 48)
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private func clockText(minutes: Int) -> String {
    let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    return SleepViewModel.clockText(date)
}

// MARK: - Flow

/// Drives everything before the paywall. Sets `hasOnboarded` when the user signs in.
struct OnboardingFlow: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @EnvironmentObject private var vm: SleepViewModel

    @State private var step: Step = .welcome
    @State private var isWorking = false
    /// True when the user tapped "I already have an account" and skipped the setup steps.
    @State private var isReturning = false
    @State private var wakeTime = OnboardingFlow.time(minutes: PlanPreferences.wakeMinutes ?? 7 * 60)
    @State private var napPreference = PlanPreferences.napOnWorkdays

    enum Step: Int {
        case welcome, connect, result, personalize, plan, signIn
    }

    private static func time(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    private var wakeMinutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
        return (c.hour ?? 7) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back, on every step after the first.
            HStack {
                if step != .welcome {
                    Button {
                        if step == .signIn, isReturning {
                            isReturning = false
                            step = .welcome
                        } else if let previous = Step(rawValue: step.rawValue - 1) {
                            step = previous
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 44, height: 44, alignment: .leading)
                    }
                    .disabled(isWorking)
                }
                Spacer()
            }
            .frame(height: 44)

            Group {
                switch step {
                case .welcome:     welcome
                case .connect:     connect
                case .result:      result
                case .personalize: personalize
                case .plan:        plan
                case .signIn:      signIn
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Building blocks

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(13, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.cyan)
    }

    private func title(_ text: String, size: CGFloat = 30) -> some View {
        Text(text)
            // The serif reads smaller than the system font at the same size.
            .font(Theme.brand(size * 1.25))
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(17))
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 1. Welcome

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            GlowOrb(size: 150)
                .padding(.bottom, 28)
            title("Find out how much sleep you owe.", size: 34)
                .multilineTextAlignment(.center)
            bodyText("Dozy reads the sleep you already track and tells you the one thing to do about it today.")
                .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "See My Sleep Debt") { step = .connect }
            Button {
                isReturning = true
                step = .signIn
            } label: {
                Text("I already have an account")
                    .font(Theme.body(16, weight: .medium))
                    .foregroundStyle(Theme.cyan)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
        }
    }

    // MARK: - 2. Connect Apple Health

    private var connect: some View {
        VStack(alignment: .leading, spacing: 14) {
            caption("STEP 1 OF 3")
            title("Connect your sleep")
            bodyText("Dozy reads sleep from Apple Health. It works with Apple Watch and anything that syncs to Health.")
            CheckList(rows: [("Reads your sleep only", true),
                             ("Logs naps you take in Dozy", true)])
                .padding(.top, 4)
            footnote("Wear Oura, Garmin or Whoop? You can add it later under You.")
            Spacer()
            PrimaryButton(title: "Connect Apple Health", isBusy: isWorking) {
                isWorking = true
                Task {
                    await vm.load()
                    // Pre-fill the wake time from their own nights, if there are enough.
                    if PlanPreferences.wakeMinutes == nil, let usual = vm.usualWakeMinutes {
                        wakeTime = Self.time(minutes: usual)
                    }
                    isWorking = false
                    step = .result
                }
            }
        }
    }

    // MARK: - 3. Your result

    private var hasNights: Bool { vm.nightsInWindow > 0 }

    private var result: some View {
        VStack(spacing: 14) {
            if hasNights {
                caption("YOUR LAST 14 NIGHTS")
                    .padding(.bottom, 12)
                Text(vm.totalDebt < 60 ? "You owe nothing" : "You owe")
                    .font(Theme.body(20))
                    .foregroundStyle(Theme.secondary)
                if vm.totalDebt >= 60 {
                    DurationText(seconds: vm.totalDebt, size: 60, color: Theme.debtPink)
                }
                bodyText(resultDetail)
                    .multilineTextAlignment(.center)

                if vm.dailyDebt.contains(where: { $0.debt >= 60 }) {
                    resultChart(vm.dailyDebt.map(\.debt))
                        .padding(.top, 8)
                }
            } else {
                // Nothing in Health yet: show what the result looks like, clearly marked.
                caption("EXAMPLE")
                    .padding(.bottom, 12)
                Text("You owe")
                    .font(Theme.body(20))
                    .foregroundStyle(Theme.secondary)
                DurationText(seconds: 100 * 60, size: 60, color: Theme.debtPink)
                bodyText("This is an example. Dozy didn’t find any sleep in Apple Health yet, so your own number appears after your first tracked night.")
                    .multilineTextAlignment(.center)
                resultChart(Self.exampleNights)
                    .padding(.top, 8)
            }
            Spacer()
            PrimaryButton(title: "Build My Plan") { step = .personalize }
        }
        .frame(maxWidth: .infinity)
    }

    private var resultDetail: String {
        let need = SleepViewModel.duration(vm.sleepNeed)
        let nights = vm.nightsInWindow
        if nights < 3 {
            return "Based on only \(nights) night\(nights == 1 ? "" : "s") so far, so treat this as a first guess. Your body needs about \(need) a night."
        }
        return "Your body needs about \(need) a night."
    }

    /// Fourteen made-up nightly shortfalls, in minutes, for the example state.
    private static let exampleNights: [TimeInterval] =
        [12, 21, 18, 36, 27, 30, 48, 60, 51, 42, 43, 57, 36, 24].map { $0 * 60 }

    private func resultChart(_ nights: [TimeInterval]) -> some View {
        let peak = max(nights.max() ?? 0, 60)
        return VStack(alignment: .leading, spacing: 10) {
            Text("SLEEP YOU MISSED EACH NIGHT")
                .font(Theme.body(12, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(nights.enumerated()), id: \.offset) { _, debt in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.debtPink.opacity(debt / peak > 0.7 ? 1 : 0.45))
                        .frame(height: max(4, 90 * CGFloat(debt / peak)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90, alignment: .bottom)
        }
        .healthCard()
    }

    // MARK: - 4. Make it yours

    private var personalize: some View {
        VStack(alignment: .leading, spacing: 14) {
            caption("STEP 2 OF 3")
            title("When do you need to be up?")

            HStack {
                Text("Wake Time")
                    .font(Theme.body(17))
                    .foregroundStyle(Theme.text)
                Spacer()
                DatePicker("Wake Time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            footnote(vm.usualWakeMinutes != nil
                     ? "Pre-filled from your last two weeks. Tap to change."
                     : "Tap the time to change it.")

            title("Can you nap on workdays?", size: 24)
                .padding(.top, 12)

            Picker("Can you nap on workdays?", selection: $napPreference) {
                Text("Yes").tag("yes")
                Text("Sometimes").tag("sometimes")
                Text("No").tag("no")
            }
            .pickerStyle(.segmented)

            Spacer()
            PrimaryButton(title: "Continue", isBusy: isWorking) {
                PlanPreferences.wakeMinutes = wakeMinutes
                PlanPreferences.napOnWorkdays = napPreference
                isWorking = true
                Task {
                    await vm.load()   // rebuild the plan around these answers
                    isWorking = false
                    step = .plan
                }
            }
        }
    }

    // MARK: - 5. Your plan

    private var plan: some View {
        VStack(alignment: .leading, spacing: 14) {
            caption("STEP 3 OF 3")
            title(planTitle)
            bodyText("Your plan is ready. One step left today.")
            CheckList(rows: [
                (hasNights ? "Sleep data connected" : "Apple Health connected", true),
                (vm.nightsInWindow >= 5
                    ? "Sleep need learned: \(SleepViewModel.duration(vm.sleepNeed))"
                    : "Sleep need set to \(SleepViewModel.duration(vm.sleepNeed)) to start", true),
                ("Plan built around \(clockText(minutes: wakeMinutes))", true),
                (todayStep, false),
            ])
            .padding(.top, 4)
            Spacer()
            PrimaryButton(title: "Start My Plan") { step = .signIn }
        }
    }

    private var planTitle: String {
        guard let payoff = vm.payoffDate else { return "You’re on track." }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: payoff).day ?? 0
        let f = DateFormatter()
        switch days {
        case ...0: return "Debt-free by morning."
        case 1:    return "Debt-free by tomorrow."
        case 2...6:
            f.dateFormat = "EEEE"
        default:
            f.dateFormat = "MMM d"
        }
        return "Debt-free by \(f.string(from: payoff))."
    }

    private var todayStep: String {
        switch vm.todayAction {
        case .nap(let length, let earliest, _)?:
            return "Today: a \(SleepViewModel.duration(length)) nap after \(SleepViewModel.clockText(earliest))"
        case .bedtime(let plan)?:
            return "Tonight: in bed by \(SleepViewModel.clockText(plan.bedtime))"
        case nil:
            return "Tonight: in bed on time"
        }
    }

    // MARK: - 6. Save your plan

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isReturning {
                title("Welcome back")
                bodyText("Sign in the same way you did before and Dozy picks up where you left off.")
            } else {
                caption("ALMOST THERE")
                title("Save your plan")
                bodyText("Sign in so your plan, your progress and your trackers stay with you on a new phone.")
            }
            HStack {
                Spacer()
                GlowOrb(size: 130)
                Spacer()
            }
            .padding(.top, 36)
            Spacer()
            SignUpWithAppleButton {
                hasOnboarded = true   // signing in finishes onboarding
            }
            footnote("Dozy only sees your name and email if you choose to share them.")
        }
    }
}

// MARK: - Sign in with Apple (and Google, once configured)

struct SignUpWithAppleButton: View {
    var onFinish: () -> Void
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                        errorMessage = "Couldn't complete sign in. Please try again."
                        return
                    }
                    // Apple only sends name/email on the FIRST authorization.
                    let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                        .compactMap { $0 }.joined(separator: " ")
                    Account.save(name: name, email: cred.email)
                    // The stable identifier is always present — store it as the account key.
                    Account.saveUserID(cred.user)
                    Account.saveProvider("apple")
                    // Swap Apple's identity token for a Dozy session so the tracker routes
                    // know who is calling. If this fails, You asks again when it's needed.
                    if let data = cred.identityToken,
                       let identityToken = String(data: data, encoding: .utf8) {
                        let userID = cred.user
                        Task {
                            do {
                                try await AppSession.exchange(
                                    identityToken: identityToken,
                                    expectedUserID: userID
                                )
                            } catch {
                                print("[Dozy] Session sign in failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    errorMessage = nil
                    onFinish()
                case .failure(let error):
                    // A real failure (not user-cancelled) — show it, do NOT proceed.
                    if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                        // User backed out; stay on the screen quietly.
                        return
                    }
                    errorMessage = "Sign in didn't work. Please try again."
                }
            }
            // Apple's button: black on light backgrounds, white on dark.
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .id(colorScheme)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Appears only once Google's package and client ID are configured.
            if GoogleAuth.isAvailable {
                GoogleSignInRow(onFinish: onFinish)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.debtPink)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
