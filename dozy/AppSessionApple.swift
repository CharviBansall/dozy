//
//  AppSessionApple.swift
//  dozy
//

import AuthenticationServices
import Foundation
import Security
import UIKit

// MARK: - Session storage

/// Keeps the session token in the Keychain rather than UserDefaults, since anyone holding it
/// can read that user's tracker sleep data.
enum SessionKeychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "charvibansall.dozy.app-session",
        kSecAttrAccount as String: "session",
    ]

    static func read() -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func write(_ data: Data) {
        delete()
        var attributes = base
        attributes[kSecValueData as String] = data
        // Sleep reloads can run before the phone is unlocked again.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

// MARK: - Getting a fresh identity token

extension AppSession {
    /// Shows Apple's sign-in sheet for the already signed-in user and swaps the fresh
    /// identity token for a new session. Apple only issues identity tokens through that sheet.
    static func renewWithApple() async throws {
        guard let userID = Account.userID, !userID.isEmpty else {
            throw Failure.signInRequired
        }
        let credential = try await AppleReauthorizer().requestIdentityToken(for: userID)
        guard credential.userID == userID else { throw Failure.wrongAppleAccount }
        try await exchange(identityToken: credential.identityToken, expectedUserID: userID)
    }

    /// True when the user dismissed Apple's sheet, which is not worth an error message.
    static func isAppleSheetCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue
    }
}

final class AppleReauthorizer: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    struct Credential {
        let userID: String
        let identityToken: String
    }

    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<Credential, Error>?

    func requestIdentityToken(for userID: String) async throws -> Credential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.user = userID

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8)
        else {
            finish(.failure(AppSession.Failure.missingIdentityToken))
            return
        }
        finish(.success(Credential(userID: credential.user, identityToken: token)))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<Credential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}
