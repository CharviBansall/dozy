//
//  Recoveryplan.swift
//  dozy
//
//  The debt ledger, tonight's bedtime, and the single action Dozy asks for today.
//  Foundation only, so this logic can be tested without HealthKit.
//

import Foundation

/// One day in the running sleep-debt ledger.
struct DebtDay: Identifiable {
    var id: Date { day }
    let day: Date
    /// False when no night sleep was recorded for this day.
    let hadNight: Bool
    /// How far that night fell short of need. Adds to the balance.
    let shortfall: TimeInterval
    /// Debt actually paid back by sleeping longer than need that night.
    let nightCredit: TimeInterval
    /// Debt actually paid back by naps that day.
    let napCredit: TimeInterval
    /// Debt owed at the end of this day.
    let balance: TimeInterval
}

/// When to be in bed tonight, and why.
struct BedtimePlan {
    let bedtime: Date
    /// The wake-up this bedtime is planned around.
    let wake: Date
    /// Sleep beyond need that this bedtime allows for, to pay debt back.
    let extra: TimeInterval
}

/// The one thing Dozy asks the user to do today.
enum TodayAction {
    case nap(length: TimeInterval, earliest: Date, latest: Date)
    case bedtime(BedtimePlan)
}

/// What the user told Dozy during onboarding. The plan is built around these.
enum PlanPreferences {
    private static let wakeKey = "plan.wakeMinutes"
    private static let napKey = "plan.napOnWorkdays"

    /// The wake-up time the user needs, as minutes after midnight. Nil until they set one.
    static var wakeMinutes: Int? {
        get { UserDefaults.standard.object(forKey: wakeKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: wakeKey) }
    }

    /// "yes", "sometimes" or "no".
    static var napOnWorkdays: String {
        get { UserDefaults.standard.string(forKey: napKey) ?? "sometimes" }
        set { UserDefaults.standard.set(newValue, forKey: napKey) }
    }

    /// True on a weekday for someone who said they can't nap on workdays.
    static func napsOff(on date: Date, calendar: Calendar) -> Bool {
        guard napOnWorkdays == "no" else { return false }
        return (2...6).contains(calendar.component(.weekday, from: date))
    }
}

extension SleepAnalyzer {

    /// A session shorter than this is a nap, otherwise a night.
    static let nightThreshold: TimeInterval = 2 * 3600
    /// Naps pay back at most this much per day.
    static let napCreditCap: TimeInterval = 30 * 60
    /// Sleeping past need pays back at most this much per night.
    static let nightCreditCap: TimeInterval = 60 * 60
    /// Below this much debt a nap isn't worth asking for.
    static let napWorthwhileDebt: TimeInterval = 20 * 60
    /// Allowance for falling asleep once in bed.
    static let fallAsleepBuffer: TimeInterval = 15 * 60

    // MARK: - Ledger

    /// Walks the window day by day, oldest first, keeping a running balance.
    ///
    /// A short night adds its shortfall. A night longer than need pays debt back
    /// (capped per night), and so do naps (capped per day). Credits only ever pay
    /// off debt that already exists: the balance never goes below zero, so sleep
    /// can't be banked ahead of time.
    func debtLedger(nights: [NightSleep],
                    need: TimeInterval,
                    windowDays: Int = 14,
                    now: Date = .now) -> [DebtDay] {
        let today = calendar.startOfDay(for: now)

        var nightByDay: [Date: TimeInterval] = [:]
        var napByDay: [Date: TimeInterval] = [:]
        for n in nights {
            if n.totalAsleep >= Self.nightThreshold {
                nightByDay[n.day, default: 0] += n.totalAsleep
            } else {
                napByDay[n.day, default: 0] += n.totalAsleep
            }
        }

        var balance: TimeInterval = 0
        var ledger: [DebtDay] = []

        for offset in (0..<windowDays).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let night = nightByDay[day] ?? 0
            let hadNight = night > 0

            // A day with no recorded night is missing data, not a full miss.
            let shortfall = hadNight ? max(0, need - night) : 0
            balance += shortfall

            let surplus = hadNight ? max(0, night - need) : 0
            let nightCredit = min(surplus, Self.nightCreditCap, balance)
            balance -= nightCredit

            let napCredit = min(napByDay[day] ?? 0, Self.napCreditCap, balance)
            balance -= napCredit

            ledger.append(DebtDay(day: day, hadNight: hadNight, shortfall: shortfall,
                                  nightCredit: nightCredit, napCredit: napCredit,
                                  balance: balance))
        }
        return ledger
    }

    // MARK: - Bedtime

    /// The user's usual wake-up as minutes after midnight: the median over recent
    /// nights. Nil when fewer than three nights carry a wake time.
    func typicalWakeMinutes(nights: [NightSleep], recentNights: Int = 14) -> Int? {
        let minutes = nights
            .filter { $0.totalAsleep >= Self.nightThreshold }
            .sorted { $0.day > $1.day }
            .prefix(recentNights)
            .compactMap { night -> Int? in
                guard let wake = night.wake else { return nil }
                let c = calendar.dateComponents([.hour, .minute], from: wake)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
            .sorted()
        guard minutes.count >= 3 else { return nil }
        return minutes[minutes.count / 2]
    }

    /// How far recent wake-ups sit from the usual one, on average, in minutes.
    /// Small means a regular rhythm. Nil when fewer than three nights carry a wake time.
    func wakeSpreadMinutes(nights: [NightSleep], recentNights: Int = 7) -> Int? {
        let minutes = nights
            .filter { $0.totalAsleep >= Self.nightThreshold }
            .sorted { $0.day > $1.day }
            .prefix(recentNights)
            .compactMap { night -> Int? in
                guard let wake = night.wake else { return nil }
                let c = calendar.dateComponents([.hour, .minute], from: wake)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
            .sorted()
        guard minutes.count >= 3 else { return nil }
        let median = minutes[minutes.count / 2]
        let total = minutes.reduce(0) { $0 + abs($1 - median) }
        return Int((Double(total) / Double(minutes.count)).rounded())
    }

    /// Bedtime that covers tonight's need plus up to an hour of payback, counted
    /// back from the usual wake-up (7:00 AM until Dozy has seen enough nights).
    func bedtimePlan(nights: [NightSleep],
                     need: TimeInterval,
                     totalDebt: TimeInterval,
                     now: Date = .now) -> BedtimePlan {
        // The wake-up the user asked for wins; otherwise their usual one, else 7:00 AM.
        let wakeMinutes = PlanPreferences.wakeMinutes ?? typicalWakeMinutes(nights: nights) ?? 7 * 60
        let today = calendar.startOfDay(for: now)
        var wake = calendar.date(bySettingHour: wakeMinutes / 60, minute: wakeMinutes % 60,
                                 second: 0, of: today) ?? today
        // Plan around the next wake-up that still leaves a real night before it.
        while wake.timeIntervalSince(now) < 4 * 3600 {
            wake = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake.addingTimeInterval(86_400)
        }

        // Whole 5-minute steps keep the time easy to read and to hit.
        let step: TimeInterval = 5 * 60
        let extra = (min(totalDebt, Self.nightCreditCap) / step).rounded(.down) * step
        let raw = wake.addingTimeInterval(-(need + extra + Self.fallAsleepBuffer))
        let bedtime = Date(timeIntervalSinceReferenceDate:
                            (raw.timeIntervalSinceReferenceDate / step).rounded(.down) * step)

        return BedtimePlan(bedtime: bedtime, wake: wake, extra: extra)
    }

    // MARK: - Payoff

    /// The morning the debt reaches zero if every night from now pays back the most
    /// a night can (60 min). Naps would bring it sooner. Nil when there is nothing to pay.
    func payoffDate(totalDebt: TimeInterval, firstWake: Date) -> Date? {
        guard totalDebt >= 5 * 60 else { return nil }
        let nightsNeeded = Int((totalDebt / Self.nightCreditCap).rounded(.up))
        return calendar.date(byAdding: .day, value: nightsNeeded - 1,
                             to: calendar.startOfDay(for: firstWake))
    }

    // MARK: - Today's one action

    /// A nap while the afternoon window is still open and worth using,
    /// otherwise tonight's bedtime. Never both.
    func todayAction(nights: [NightSleep],
                     need: TimeInterval,
                     totalDebt: TimeInterval,
                     napSkipped: Bool,
                     now: Date = .now) -> TodayAction {
        let today = calendar.startOfDay(for: now)
        let nap = napRecommendation(totalDebt: totalDebt, now: now)
        let nappedToday = nights.contains {
            $0.totalAsleep < Self.nightThreshold && $0.day == today
        }

        let napsOff = napSkipped || PlanPreferences.napsOff(on: now, calendar: calendar)
        if totalDebt >= Self.napWorthwhileDebt, now <= nap.latest, !nappedToday, !napsOff {
            return .nap(length: nap.length, earliest: nap.earliest, latest: nap.latest)
        }
        return .bedtime(bedtimePlan(nights: nights, need: need, totalDebt: totalDebt, now: now))
    }
}
