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

    /// Day-by-day debt balance for the 14-day window; the last entry is today.
    @Published var ledger: [DebtDay] = []
    /// The single thing to do today: a nap, or tonight's bedtime.
    @Published var todayAction: TodayAction? = nil
    /// The morning the debt is cleared if the plan is followed. Nil when debt-free.
    @Published var payoffDate: Date? = nil
    /// Average deep and REM sleep over the previous nights (up to 14), not counting
    /// last night. Nil until three earlier nights carry stage data.
    @Published var usualDeep: TimeInterval? = nil
    @Published var usualREM: TimeInterval? = nil
    /// Usual wake-up, as minutes after midnight. Nil until three nights carry one.
    @Published var usualWakeMinutes: Int? = nil
    /// Average distance of the last week's wake-ups from the usual one, in minutes.
    @Published var wakeSpreadMinutes: Int? = nil
    /// Set after a nap finishes, so the Nap screen can show what it paid back.
    @Published var napPayback: NapPayback? = nil

    struct NapPayback {
        let before: TimeInterval
        let after: TimeInterval
        var paidBack: TimeInterval { max(0, before - after) }
    }

    enum LastNightResult {
        case paidBack(TimeInterval)
        case added(TimeInterval)
        case steady
    }

    /// Nights with sleep data in the 14-day window. Zero debt means little without them.
    var nightsInWindow: Int { ledger.filter(\.hadNight).count }

    /// What last night did to the debt. Nil until today has a recorded night.
    var lastNightResult: LastNightResult? {
        guard let today = ledger.last, today.hadNight else { return nil }
        if today.shortfall >= 60 { return .added(today.shortfall) }
        if today.nightCredit >= 60 { return .paidBack(today.nightCredit) }
        return .steady
    }

    @Published var lastUpdated: Date? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = SleepHealthStore.shared
    private let analyzer = SleepAnalyzer()
    private var loadedNights: [NightSleep] = []
    private static let napSkippedDayKey = "action.napSkippedDay"

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
            let ledger = analyzer.debtLedger(nights: nights, need: need, windowDays: 14)
            let total = ledger.last?.balance ?? 0
            let restorative = analyzer.latestRestorativeFraction(nights: nights) ?? 0
            let latest = nights
                .filter { $0.totalAsleep >= 2 * 3600 }   // night sleep only, not naps
                .sorted { $0.day > $1.day }
                .first
            let nap = analyzer.napRecommendation(totalDebt: total)

            self.sleepNeed = need
            self.dailyDebt = daily
            self.totalDebt = total
            self.ledger = ledger
            self.loadedNights = nights
            self.usualWakeMinutes = analyzer.typicalWakeMinutes(nights: nights)
            let plan = analyzer.bedtimePlan(nights: nights, need: need, totalDebt: total)
            self.payoffDate = analyzer.payoffDate(totalDebt: total, firstWake: plan.wake)
            self.wakeSpreadMinutes = analyzer.wakeSpreadMinutes(nights: nights)
            self.todayAction = analyzer.todayAction(
                nights: nights, need: need, totalDebt: total,
                napSkipped: Self.napSkippedToday
            )
            self.restorativeFraction = restorative
            self.latestNight = latest

            // Personal baseline for deep and REM: earlier nights that have stage data.
            let staged = nights
                .filter { $0.totalAsleep >= 2 * 3600 && $0.deep + $0.rem > 0 }
                .sorted { $0.day > $1.day }
                .filter { $0.day != latest?.day }
                .prefix(14)
            if staged.count >= 3 {
                self.usualDeep = staged.map(\.deep).reduce(0, +) / Double(staged.count)
                self.usualREM = staged.map(\.rem).reduce(0, +) / Double(staged.count)
            } else {
                self.usualDeep = nil
                self.usualREM = nil
            }
            self.napLength = nap.length
            self.napEarliest = nap.earliest
            self.napLatest = nap.latest
            self.lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Today's action and its result

    /// Logs a finished nap to Health, reloads, and records how much debt it paid back.
    func completeNap(start: Date, end: Date) async {
        let before = totalDebt
        try? await store.logNap(start: start, end: end)
        await load()
        napPayback = NapPayback(before: before, after: totalDebt)
    }

    /// The user can't nap today: switch today's action to tonight's bedtime.
    func skipNapToday() {
        UserDefaults.standard.set(Self.dayKey(.now), forKey: Self.napSkippedDayKey)
        todayAction = analyzer.todayAction(
            nights: loadedNights, need: sleepNeed, totalDebt: totalDebt, napSkipped: true
        )
    }

    private static var napSkippedToday: Bool {
        UserDefaults.standard.string(forKey: napSkippedDayKey) == dayKey(.now)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Keeps every HealthKit entry (nights and naps) untouched, then fills days that
    /// have no HealthKit night with the longest Junction night for that day.
    /// Longest-per-day avoids double counting when two cloud trackers report the same night.
    static func mergeNights(healthKit: [NightSleep], junction: [NightSleep]) -> [NightSleep] {
        let cal = Calendar.current
        let nightThreshold: TimeInterval = 2 * 3600

        let daysWithHealthKitNight = Set(
            healthKit
                .filter { $0.totalAsleep >= nightThreshold }
                .map { cal.startOfDay(for: $0.day) }
        )

        var cloudByDay: [Date: NightSleep] = [:]
        for night in junction where night.totalAsleep >= nightThreshold {
            let day = cal.startOfDay(for: night.day)
            guard !daysWithHealthKitNight.contains(day) else { continue }
            if let existing = cloudByDay[day], existing.totalAsleep >= night.totalAsleep { continue }
            cloudByDay[day] = night
        }

        return (healthKit + Array(cloudByDay.values)).sorted { $0.day > $1.day }
    }

    // MARK: - Formatting helpers for the UI

    var debtDisplay: String { Self.minutes(totalDebt) }
    var napDisplay: String { Self.minutes(napLength) }
    var restorativeDisplay: String { "\(Int((restorativeFraction * 100).rounded()))" }

    /// A duration with its unit, for sentences: "35 min" or "1h 40m".
    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m) min"
    }

    static func clockText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// "Debt-free by Saturday morning if you stick to the plan."
    var payoffText: String? {
        guard let payoffDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: payoffDate).day ?? 0
        let when: String
        switch days {
        case ...0: when = "this morning"
        case 1:    when = "tomorrow morning"
        case 2...6:
            let f = DateFormatter(); f.dateFormat = "EEEE"
            when = "\(f.string(from: payoffDate)) morning"
        default:
            let f = DateFormatter(); f.dateFormat = "MMM d"
            when = f.string(from: payoffDate)
        }
        return "Debt-free by \(when) if you stick to the plan."
    }

    /// The morning notification: last night's result, then today's one thing.
    var morningBrief: (title: String, body: String)? {
        guard let result = lastNightResult, let action = todayAction else { return nil }

        let title: String
        switch result {
        case .paidBack(let amount): title = "Last night paid back \(Self.duration(amount))"
        case .added(let amount):    title = "Last night added \(Self.duration(amount)) to your sleep debt"
        case .steady:               title = "Last night kept your sleep debt level"
        }

        var body: String
        switch action {
        case .nap(let length, let earliest, let latest):
            body = "Today: a \(Self.duration(length)) nap between \(Self.clockText(earliest)) and \(Self.clockText(latest))."
        case .bedtime(let plan):
            body = "Tonight: be in bed by \(Self.clockText(plan.bedtime))."
        }
        body += " " + (payoffText ?? "You're all caught up.")
        return (title, body)
    }

    /// The usual wake-up as a clock time, e.g. "7:05 AM".
    var usualWakeText: String? {
        guard let minutes = usualWakeMinutes,
              let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                               second: 0, of: .now)
        else { return nil }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)"
    }
}
