//
//  Sleepanalyzer.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation
import HealthKit

/// Computes Dozy's three metrics from raw HealthKit samples.
/// Pure functions where possible so the logic is testable without HealthKit.
struct SleepAnalyzer {

    var calendar: Calendar = .current

    // MARK: - Step 1: collapse overlapping samples

    /// Apple Watch + third-party apps can both write sleep, producing overlapping
    /// intervals that would double-count. We flatten to a timeline where each instant
    /// belongs to exactly one stage, preferring the more "specific/deeper" stage on overlap.
    private func stagePriority(_ stage: SleepStage) -> Int {
        switch stage {
        case .deep: return 5
        case .rem:  return 4
        case .core: return 3
        case .unspecified: return 2
        case .awake: return 1
        case .inBed: return 0   // lowest: inBed is a container, never counted as asleep
        }
    }

    struct Interval { let start: Date; let end: Date; let stage: SleepStage }

    private func flatten(_ samples: [HKCategorySample]) -> [Interval] {
        let raw: [Interval] = samples.compactMap { s in
            guard let stage = SleepStage(rawValue: s.value) else { return nil }
            return Interval(start: s.startDate, end: s.endDate, stage: stage)
        }
        guard !raw.isEmpty else { return [] }

        // Build a sorted list of all boundary points.
        var points = Set<Date>()
        for i in raw { points.insert(i.start); points.insert(i.end) }
        let sorted = points.sorted()

        var result: [Interval] = []
        for idx in 0..<(sorted.count - 1) {
            let segStart = sorted[idx]
            let segEnd = sorted[idx + 1]
            guard segEnd > segStart else { continue }
            let mid = segStart.addingTimeInterval(segEnd.timeIntervalSince(segStart) / 2)

            // Which stages cover this segment? Pick highest priority.
            let covering = raw.filter { $0.start <= mid && $0.end > mid }
            guard let winner = covering.max(by: { stagePriority($0.stage) < stagePriority($1.stage) })
            else { continue }

            result.append(Interval(start: segStart, end: segEnd, stage: winner.stage))
        }
        return result
    }

    // MARK: - Step 2: group into nights

    /// Group flattened intervals into nights. A gap longer than `nightGap`
    /// (default 3h) starts a new night. Each night is attributed to its wake-up day.
    func nights(from samples: [HKCategorySample], nightGap: TimeInterval = 3 * 3600) -> [NightSleep] {
        let intervals = flatten(samples).sorted { $0.start < $1.start }
        guard !intervals.isEmpty else { return [] }

        var groups: [[Interval]] = []
        var current: [Interval] = [intervals[0]]

        for iv in intervals.dropFirst() {
            if let last = current.last, iv.start.timeIntervalSince(last.end) > nightGap {
                groups.append(current)
                current = [iv]
            } else {
                current.append(iv)
            }
        }
        groups.append(current)

        return groups.map { group in
            var core = 0.0, deep = 0.0, rem = 0.0, awake = 0.0
            for iv in group {
                let dur = iv.end.timeIntervalSince(iv.start)
                switch iv.stage {
                case .core, .unspecified: core += dur
                case .deep:  deep += dur
                case .rem:   rem += dur
                case .awake: awake += dur
                case .inBed: break
                }
            }
            // Attribute to the wake-up day (end of the last interval).
            let wakeDay = calendar.startOfDay(for: group.last!.end)
            return NightSleep(day: wakeDay, core: core, deep: deep, rem: rem, awake: awake)
        }
    }

    // MARK: - Step 3: personalized sleep need

    /// Estimate the user's nightly sleep NEED from their own history.
    /// Rationale: daily average understates need because it's already suppressed by debt.
    /// We use a high percentile of nightly asleep duration — closer to how long they
    /// sleep when unconstrained. Falls back to 8h if there isn't enough data.
    func sleepNeed(from nights: [NightSleep], percentile: Double = 0.80) -> TimeInterval {
        let durations = nights.map(\.totalAsleep).filter { $0 > 2 * 3600 } // ignore naps/junk
        guard durations.count >= 5 else { return 8 * 3600 }

        let sorted = durations.sorted()
        let rank = percentile * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        let value = sorted[lo] + (sorted[hi] - sorted[lo]) * frac

        // Clamp to a sane human range (5h–10h).
        return min(max(value, 5 * 3600), 10 * 3600)
    }

    // MARK: - Step 4: the three metrics

    /// Per-day NIGHT debt over a window (used by the bar chart).
    /// Each day's debt = how far that night's sleep fell short of need.
    /// Naps are handled separately in `totalSleepDebt` so they draw down the
    /// accumulated backlog rather than distorting individual days.
    func dailyDebt(nights: [NightSleep], need: TimeInterval, windowDays: Int = 14) -> [(day: Date, debt: TimeInterval)] {
        let today = calendar.startOfDay(for: .now)
        let napThreshold: TimeInterval = 2 * 3600     // under 2h = a nap

        // Only night sleep counts toward a day's debt.
        var nightByDay: [Date: TimeInterval] = [:]
        for n in nights where n.totalAsleep >= napThreshold {
            nightByDay[n.day, default: 0] += n.totalAsleep
        }

        return (0..<windowDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let night = nightByDay[day] ?? 0
            // No night sleep for the day → treat as missing, not a deficit.
            let debt = night == 0 ? 0 : max(0, need - night)
            return (day, debt)
        }
    }

    /// Total accumulated sleep debt (the Summary number).
    ///
    /// = sum of nightly shortfalls over the window, MINUS recovery from naps.
    /// Naps count at full 1:1 credit (WHOOP), capped at 30 min per day so a single
    /// day's napping can't erase a multi-night backlog. A nap can only reduce
    /// existing debt — it never creates any.
    func totalSleepDebt(nights: [NightSleep], need: TimeInterval, windowDays: Int = 14) -> TimeInterval {
        let napThreshold: TimeInterval = 2 * 3600
        let napCreditCap: TimeInterval = 30 * 60
        let today = calendar.startOfDay(for: .now)
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today)!

        // Base debt from nights.
        let baseDebt = dailyDebt(nights: nights, need: need, windowDays: windowDays)
            .reduce(0) { $0 + $1.debt }

        // Recovery from naps in the window, capped per day, full credit.
        var napByDay: [Date: TimeInterval] = [:]
        for n in nights where n.totalAsleep < napThreshold && n.day >= windowStart {
            napByDay[n.day, default: 0] += n.totalAsleep
        }
        let totalNapCredit = napByDay.values.reduce(0) { $0 + min($1, napCreditCap) }

        return max(0, baseDebt - totalNapCredit)
    }

    /// Restorative % for the most recent night with data. (Deep + REM) / total asleep.
    func latestRestorativeFraction(nights: [NightSleep]) -> Double? {
        // Only NIGHT sleep counts for restorative — naps (short sessions) are
        // excluded so a quick core-only nap can't distort the percentage.
        let nightThreshold: TimeInterval = 2 * 3600
        return nights
            .filter { $0.totalAsleep >= nightThreshold }
            .sorted { $0.day > $1.day }
            .first?
            .restorativeFraction
    }

    /// Nap recommendation. Length scales with current debt, capped to avoid sleep inertia
    /// and clipped so it ends before evening (won't wreck tonight's sleep).
    /// Returns recommended length in seconds and a suggested start window.
    func napRecommendation(totalDebt: TimeInterval, now: Date = .now) -> (length: TimeInterval, earliest: Date, latest: Date) {
        // More debt -> longer nap, but stay in restorative-without-grogginess ranges.
        // 0 debt -> 10 min refresher; lots of debt -> up to a full 90-min cycle.
        let length: TimeInterval
        switch totalDebt {
        case ..<(20 * 60):           length = 10 * 60
        case ..<(60 * 60):           length = 20 * 60
        case ..<(120 * 60):          length = 30 * 60
        default:                     length = 90 * 60   // full cycle for heavy debt
        }

        // Circadian dip is roughly early-to-mid afternoon. Recommend a window then,
        // but never so late it cuts into night sleep.
        let cal = calendar
        let earliest = cal.date(bySettingHour: 13, minute: 0, second: 0, of: now) ?? now
        let latest   = cal.date(bySettingHour: 15, minute: 30, second: 0, of: now) ?? now
        return (length, earliest, latest)
    }
}
