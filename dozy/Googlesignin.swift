//
//  Googlesignin.swift
//  dozy
//
//  Sign in with Google, as a second way into the same Dozy account system.
//
//  This file compiles with or without Google's package. The Google button only
//  appears once BOTH are true:
//    1. The GoogleSignIn-iOS package is added to the dozy target
//       (https://github.com/google/GoogleSignIn-iOS, products GoogleSignIn + GoogleSignInSwift).
//    2. Info.plist has `GIDClientID` (the iOS client ID from Google Cloud) and a URL
//       scheme equal to the reversed client ID.
//  The server must also accept `POST /api/auth/google` (see AppSession.exchangeGoogle).
//

import SwiftUI
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(GoogleSignInSwift)
import GoogleSignInSwift
#endif

enum GoogleAuth {

    enum Failure: LocalizedError {
        case unavailable
        case noScreen
        case missingToken

        var errorDescription: String? {
            switch self {
            case .unavailable:  return "Google sign in isn’t set up in this build."
            case .noScreen:     return "Couldn’t open Google sign in. Please try again."
            case .missingToken: return "Google didn’t confirm the sign in. Please try again."
            }
        }
    }

    /// True when the package is linked and a client ID is configured.
    static var isAvailable: Bool {
        #if canImport(GoogleSignIn)
        return Bundle.main.object(forInfoDictionaryKey: "GIDClientID") is String
        #else
        return false
        #endif
    }

    /// Shows Google's sign-in screen, then swaps the result for a Dozy session.
    static func signIn() async throws {
        #if canImport(GoogleSignIn)
        guard let presenter = topViewController() else { throw Failure.noScreen }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        try await finish(result.user)
        #else
        throw Failure.unavailable
        #endif
    }

    /// Gets a fresh Google token without showing UI and renews the Dozy session.
    static func renew() async throws {
        #if canImport(GoogleSignIn)
        let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        try await finish(try await user.refreshTokensIfNeeded())
        #else
        throw Failure.unavailable
        #endif
    }

    /// Google returns to the app through a URL; pass it on. Returns true if it was Google's.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    static func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    /// Withdraws Dozy's access to the Google account, for account deletion.
    static func disconnect() async {
        #if canImport(GoogleSignIn)
        _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
        try? await GIDSignIn.sharedInstance.disconnect()
        #endif
    }

    /// True when the user backed out of Google's screen, which is not worth an error message.
    static func isCancelled(_ error: Error) -> Bool {
        #if canImport(GoogleSignIn)
        return (error as? GIDSignInError)?.code == .canceled
        #else
        return false
        #endif
    }

    #if canImport(GoogleSignIn)
    private static func finish(_ user: GIDGoogleUser) async throws {
        guard let idToken = user.idToken?.tokenString else { throw Failure.missingToken }
        // When renewing, the session must come back for the same Dozy account.
        let expected = Account.provider == "google" ? Account.userID : nil
        let userID = try await AppSession.exchangeGoogle(idToken: idToken, expectedUserID: expected)
        Account.saveUserID(userID)
        Account.saveProvider("google")
        Account.save(name: user.profile?.name, email: user.profile?.email)
    }
    #endif

    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Renewing the session, whichever way the user signed in

extension AppSession {
    static func renew() async throws {
        if Account.provider == "google" {
            try await GoogleAuth.renew()
        } else {
            try await renewWithApple()
        }
    }

    static func isSignInCancelled(_ error: Error) -> Bool {
        isAppleSheetCancelled(error) || GoogleAuth.isCancelled(error)
    }
}

// MARK: - Button

/// Google's own branded button when their package is present; a plain one otherwise.
struct GoogleSignInRow: View {
    var onFinish: () -> Void
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 10) {
            button
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .disabled(isWorking)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.debtPink)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private static let googleScale: CGFloat = 1.3

    @ViewBuilder
    private var button: some View {
        #if canImport(GoogleSignInSwift)
        // Google's button is a fixed 40pt tall. Scale it up evenly so it fills the
        // same 52pt height as the Apple button, keeping its own proportions.
        GeometryReader { geo in
            GoogleSignInButton(scheme: .light, style: .wide, action: start)
                .frame(width: geo.size.width / Self.googleScale, height: 40)
                .scaleEffect(Self.googleScale, anchor: .topLeading)
        }
        .frame(height: 40 * Self.googleScale)
        #else
        Button(action: start) {
            Text("Continue with Google")
                .font(Theme.body(17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
        }
        #endif
    }

    private func start() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await GoogleAuth.signIn()
                onFinish()
            } catch {
                if !GoogleAuth.isCancelled(error) {
                    errorMessage = error.localizedDescription
                }
            }
            isWorking = false
        }
    }
}
