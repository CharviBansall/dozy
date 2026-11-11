//
//  AppSession.swift
//  dozy
//

import Foundation

/// The Dozy server session for the signed-in Apple user.
///
/// The server hands one out in exchange for a Sign in with Apple identity token, and the
/// Junction routes accept it as `Authorization: Bearer …`. It lasts about 90 days; after
/// that the user has to confirm with Apple again (`renewWithApple()`).
enum AppSession {
    private static let baseURL = URL(string: "https://www.appdozy.com")!
    private static let needsSignInKey = "account.session.needsSignIn"

    struct Stored: Codable {
        let userID: String
        let token: String
        let expiresAt: Date
    }

    enum Failure: LocalizedError {
        case signInRequired
        case wrongAppleAccount
        case missingIdentityToken
        case server(String)

        var errorDescription: String? {
            switch self {
            case .signInRequired:
                return "Sign in with Apple again so Dozy can sync this tracker."
            case .wrongAppleAccount:
                return "That’s a different Apple Account from the one Dozy is signed in with."
            case .missingIdentityToken:
                return "Apple didn’t confirm the sign in. Please try again."
            case .server(let message):
                return message
            }
        }
    }

    /// True once the server has refused a request for lack of a session.
    /// Cleared again as soon as a session is issued or a request goes through.
    static var needsSignIn: Bool {
        get { UserDefaults.standard.bool(forKey: needsSignInKey) }
        set { UserDefaults.standard.set(newValue, forKey: needsSignInKey) }
    }

    /// The session token for the signed-in user, or nil if there is none or it has expired.
    static func token(now: Date = Date()) -> String? {
        guard let userID = Account.userID,
              let data = SessionKeychain.read(),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              // Keychain items outlive a reinstall, so make sure this one is for this user.
              stored.userID == userID,
              stored.expiresAt > now
        else { return nil }
        return stored.token
    }

    /// Adds the session to a request. Returns false when there is no session to add.
    @discardableResult
    static func authorize(_ request: inout URLRequest) -> Bool {
        guard let token = token() else { return false }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return true
    }

    /// Swaps a Sign in with Apple identity token for a Dozy session and stores it.
    static func exchange(identityToken: String, expectedUserID: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["identityToken": identityToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        struct Body: Decodable {
            let userId: String?
            let sessionToken: String?
            let expiresAt: String?
            let error: String?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)

        guard http.statusCode == 200,
              let userId = body?.userId,
              let sessionToken = body?.sessionToken,
              let expiresAt = body?.expiresAt.flatMap(parseDate)
        else {
            throw Failure.server(body?.error ?? "Couldn’t sign in to Dozy (\(http.statusCode)).")
        }
        // A session only works for the user id it was issued for.
        guard userId == expectedUserID else { throw Failure.wrongAppleAccount }

        let stored = Stored(userID: userId, token: sessionToken, expiresAt: expiresAt)
        SessionKeychain.write(try JSONEncoder().encode(stored))
        needsSignIn = false
    }

    /// Forgets the stored session but keeps `needsSignIn` as it is.
    static func discard() {
        SessionKeychain.delete()
    }

    /// Forgets everything, for sign out.
    static func clear() {
        SessionKeychain.delete()
        UserDefaults.standard.removeObject(forKey: needsSignInKey)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
