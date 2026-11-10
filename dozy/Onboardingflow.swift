//
//  Onboardingflow.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI
import AuthenticationServices

// MARK: - Shared visual atoms

/// The deep navy→black radial gradient backdrop seen across the frames.
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
            .shadow(color: Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.6),
                    radius: 40, x: 0, y: 0)
    }
}

// MARK: - Onboarding container

/// Drives the whole pre-auth experience. Sets `hasOnboarded` when finished.
struct OnboardingFlow: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var stage: Stage = .launch
    @State private var page = 0

    enum Stage { case launch, intro }

    var body: some View {
        ZStack {
            DozyBackground()

            switch stage {
            case .launch:
                LaunchScreen { withAnimation(.easeInOut) { stage = .intro } }
                    .transition(.opacity)
            case .intro:
                IntroPager(page: $page) {
                    hasOnboarded = true   // finishing onboarding flips into the app
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Launch ("Dozy / Reads your sleep. Plans your nap.")

struct LaunchScreen: View {
    var onStart: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            Text("Dozy")
                .font(Theme.serif(64))
                .foregroundStyle(.white)
            Text("Reads your sleep. Plans your nap.")
                .font(Theme.serif(17))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)

            GlowOrb(size: 150)
                .padding(.top, 48)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()

            Button(action: onStart) {
                Text("Get started")
                    .font(Theme.serif(18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [Color(red: 0.1, green: 0.45, blue: 1.0),
                                                Color(red: 0.04, green: 0.30, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { appeared = true }
        }
    }
}

// MARK: - Paged intro cards

struct IntroPage: Identifiable {
    let id = UUID()
    let title: [TitleSpan]   // supports a colored accent word
    let subtitle: String
}

/// A run of title text, optionally accented (blue/italic) like the frames.
struct TitleSpan: Identifiable {
    let id = UUID()
    let text: String
    let accent: Bool
}

private let introPages: [IntroPage] = [
    IntroPage(
        title: [TitleSpan(text: "You slept.\nBut did you ", accent: false),
                TitleSpan(text: "rest?", accent: true)],
        subtitle: "Hours in bed don't always mean real recovery."
    ),
    IntroPage(
        title: [TitleSpan(text: "Small losses\nadd up quietly.", accent: false)],
        subtitle: "30 minutes less, five nights in a row.\nYour body keeps score."
    ),
    IntroPage(
        title: [TitleSpan(text: "Only some sleep\n", accent: false),
                TitleSpan(text: "actually heals", accent: true),
                TitleSpan(text: " you.", accent: false)],
        subtitle: "Deep and REM sleep do the real work.\nThe goal is 40% of your night."
    ),
    IntroPage(
        title: [TitleSpan(text: "The ", accent: false),
                TitleSpan(text: "right nap", accent: true),
                TitleSpan(text: "\nat the right time.", accent: false)],
        subtitle: "Dozy finds the window where you wake\nup refreshed, every time."
    )
]

struct IntroPager: View {
    @Binding var page: Int
    var onFinish: () -> Void

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(introPages.enumerated()), id: \.offset) { idx, item in
                    IntroCard(page: item).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom page dots (matching the frames' small dots).
            HStack(spacing: 10) {
                ForEach(0..<introPages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 24)

            // On the last page, show Sign up with Apple; otherwise an invisible spacer
            // keeps layout stable.
            Group {
                if page == introPages.count - 1 {
                    SignUpWithAppleButton(onFinish: onFinish)
                        .padding(.horizontal, 40)
                        .transition(.opacity)
                } else {
                    Color.clear.frame(height: 54)
                }
            }
            .padding(.bottom, 40)
            .animation(.easeInOut, value: page)
        }
    }
}

struct IntroCard: View {
    let page: IntroPage

    var body: some View {
        VStack {
            Spacer()

            // Title with optional accent spans.
            titleView
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text(page.subtitle)
                .font(Theme.body(14))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 32)

            GlowOrb(size: 150)
                .padding(.top, 56)

            Spacer()
            Spacer()
        }
    }

    private var titleView: some View {
        page.title.reduce(Text("")) { partial, span in
            partial + Text(span.text)
                .foregroundColor(span.accent
                                 ? Color(red: 0.25, green: 0.6, blue: 1.0)
                                 : .white)
                .italic(span.accent)
        }
        .font(Theme.serif(34))
    }
}

// MARK: - Sign up with Apple

struct SignUpWithAppleButton: View {
    var onFinish: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.signUp) { request in
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
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(Capsule())

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(13))
                    .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.5))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
