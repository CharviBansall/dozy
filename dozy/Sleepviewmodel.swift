//
//  Sleepviewmodel.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation
import SwiftUI
import Combine
@MainActor
final class SleepViewModel: ObservableObject {

    // Published metrics the views read.
    @Published var totalDebt: TimeInterval = 0          // seconds
    @Published var dailyDebt: [(day: Date, debt: TimeInterval)] = []
    @Published var restorativeFraction: Double = 0      // 0...1
    @Published var latestNight: NightSleep? = nil       // most recent night with data
    @Published var sleepNeed: TimeInterval = 8 * 3600
    @Published var napLength: TimeInterval = 0
    @Published var napEarliest: Date = .now
    @Published var napLatest: Date = .now

    @Published var lastUpdated: Date? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = SleepHealthStore.shared
    private let analyzer = SleepAnalyzer()

    /// Call once on launch / when the Summary appears / after a cloud connect.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await store.requestAuthorization()

            // Pull 30 days so the need-baseline has enough history.
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -30, to: end)!
            let samples = try await store.fetchSleepSamples(start: start, end: end)

            var nights = analyzer.nights(from: samples)

            // Merge Junction cloud sleep (Oura / Garmin / Whoop) for days
            // HealthKit doesn't already cover. HealthKit wins on the same day.
            if Account.hasCloudSourceConnected, let clientUserId = Account.userID {
                do {
                    let cloud = try await JunctionAPI.fetchSleep(
                        clientUserId: clientUserId,
                        startDate: start,
                        endDate: end
                    )
                    nights = Self.mergeNights(healthKit: nights, junction: cloud)
                } catch {
                    // Cloud is additive — don't fail the whole load if Junction blips.
                    print("[Dozy] Junction sleep fetch failed: \(error.localizedDescription)")
                }
            }

            guard !nights.isEmpty else {
                errorMessage = SleepError.noData.errorDescription
                return
            }

            let need = analyzer.sleepNeed(from: nights)
            let daily = analyzer.dailyDebt(nights: nights, need: need, windowDays: 14)
            let total = analyzer.totalSleepDebt(nights: nights, need: need, windowDays: 14)
            let restorative = analyzer.latestRestorativeFraction(nights: nights) ?? 0
            let latest = nights
                .filter { $0.totalAsleep >= 2 * 3600 }   // night sleep only, not naps
                .sorted { $0.day > $1.day }
                .first
            let nap = analyzer.napRecommendation(totalDebt: total)

            self.sleepNeed = need
            self.dailyDebt = daily
            self.totalDebt = total
            self.restorativeFraction = restorative
            self.latestNight = latest
            self.napLength = nap.length
            self.napEarliest = nap.earliest
            self.napLatest = nap.latest
            self.lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Prefer HealthKit when both sources have the same wake day; keep Junction-only nights.
    static func mergeNights(healthKit: [NightSleep], junction: [NightSleep]) -> [NightSleep] {
        let cal = Calendar.current
        var byDay: [Date: NightSleep] = [:]
        for night in junction {
            byDay[cal.startOfDay(for: night.day)] = night
        }
        for night in healthKit {
            byDay[cal.startOfDay(for: night.day)] = night
        }
        return Array(byDay.values).sorted { $0.day > $1.day }
    }

    // MARK: - Formatting helpers for the UI

    var debtDisplay: String { Self.minutes(totalDebt) }
    var napDisplay: String { Self.minutes(napLength) }
    var restorativeDisplay: String { "\(Int((restorativeFraction * 100).rounded()))" }

    static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)"
    }
}
