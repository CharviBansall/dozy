//
//  Account.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation

/// Persists the small amount of account info Apple gives us at sign-in.
/// Apple only returns name/email on the FIRST authorization, so we save it then.
enum Account {

    static func save(name: String?, email: String?) -> Void {
        let d = UserDefaults.standard
        if let name, !name.isEmpty { d.set(name, forKey: "account.name") }
        if let email, !email.isEmpty { d.set(email, forKey: "account.email") }
    }

    static var name: String? { UserDefaults.standard.string(forKey: "account.name") }
    static var email: String? { UserDefaults.standard.string(forKey: "account.email") }

    static func saveUserID(_ id: String) {
        UserDefaults.standard.set(id, forKey: "account.userID")
    }
    static var userID: String? { UserDefaults.standard.string(forKey: "account.userID") }
    static var isSignedIn: Bool { userID != nil }

    static func clear() {
        let d = UserDefaults.standard
        d.removeObject(forKey: "account.name")
        d.removeObject(forKey: "account.email")
        d.removeObject(forKey: "account.userID")
        for provider in cloudProviders {
            d.removeObject(forKey: cloudKey(provider))
        }
    }

    // MARK: - Junction cloud sources

    static let cloudProviders = ["oura", "garmin", "whoop_v2"]

    private static func cloudKey(_ provider: String) -> String {
        "account.cloud.\(provider)"
    }

    static func isCloudSourceConnected(_ provider: String) -> Bool {
        UserDefaults.standard.bool(forKey: cloudKey(provider))
    }

    static func setCloudSourceConnected(_ provider: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: cloudKey(provider))
    }

    static var hasCloudSourceConnected: Bool {
        cloudProviders.contains { isCloudSourceConnected($0) }
    }
}

// MARK: - Junction HTTP client

enum JunctionAPI {
    private static let baseURL = URL(string: "https://www.appdozy.com")!

    struct LinkTokenResponse: Decodable {
        let linkWebUrl: String?
        let error: String?
    }

    struct SleepResponse: Decodable {
        let sleep: [SleepSummary]?
        let error: String?
    }

    struct SleepSummary: Decodable {
        let calendar_date: String?
        let light: Double?
        let deep: Double?
        let rem: Double?
        let awake: Double?
        let stage_light_second: Double?
        let stage_deep_second: Double?
        let stage_rem_second: Double?
        let stage_awake_second: Double?
        let bedtime_stop: String?
        let source: Source?

        struct Source: Decodable {
            let provider: String?
        }

        func asNightSleep(calendar: Calendar = .current) -> NightSleep? {
            let core = stage_light_second ?? light ?? 0
            let deepSec = stage_deep_second ?? deep ?? 0
            let remSec = stage_rem_second ?? rem ?? 0
            let awakeSec = stage_awake_second ?? awake ?? 0
            let asleep = core + deepSec + remSec
            guard asleep >= 30 * 60 else { return nil }

            let day: Date
            if let calendar_date, let parsed = Self.parseCalendarDay(calendar_date, calendar: calendar) {
                day = parsed
            } else if let bedtime_stop, let stop = Self.parseISO(bedtime_stop) {
                day = calendar.startOfDay(for: stop)
            } else {
                return nil
            }

            return NightSleep(
                day: day,
                core: core,
                deep: deepSec,
                rem: remSec,
                awake: awakeSec
            )
        }

        private static func parseCalendarDay(_ raw: String, calendar: Calendar) -> Date? {
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var comps = DateComponents()
            comps.year = parts[0]
            comps.month = parts[1]
            comps.day = parts[2]
            guard let date = calendar.date(from: comps) else { return nil }
            return calendar.startOfDay(for: date)
        }

        private static func parseISO(_ raw: String) -> Date? {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFraction.date(from: raw) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: raw)
        }
    }

    static func createLinkURL(clientUserId: String, provider: String) async throws -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/junction/link-token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "clientUserId": clientUserId,
            "provider": provider,
            "redirectUrl": "dozy://junction-connected",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(LinkTokenResponse.self, from: data)
        guard http.statusCode == 200, let raw = decoded.linkWebUrl, let url = URL(string: raw) else {
            throw NSError(
                domain: "JunctionAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "Couldn’t start \(provider) connect."]
            )
        }
        return url
    }

    static func fetchSleep(
        clientUserId: String,
        startDate: Date,
        endDate: Date? = nil,
        calendar: Calendar = .current
    ) async throws -> [NightSleep] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/junction/sleep"),
            resolvingAgainstBaseURL: false
        )!
        var items = [
            URLQueryItem(name: "clientUserId", value: clientUserId),
            URLQueryItem(name: "startDate", value: dayString(startDate, calendar: calendar)),
        ]
        if let endDate {
            items.append(URLQueryItem(name: "endDate", value: dayString(endDate, calendar: calendar)))
        }
        comps.queryItems = items

        guard let url = comps.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SleepResponse.self, from: data)
        guard http.statusCode == 200 else {
            throw NSError(
                domain: "JunctionAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "Sleep fetch failed."]
            )
        }
        return (decoded.sleep ?? []).compactMap { $0.asNightSleep(calendar: calendar) }
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
