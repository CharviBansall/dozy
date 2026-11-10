//
//  Nightsleep.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation
import HealthKit

/// One night's worth of consolidated sleep, broken down by stage.
/// Times are in seconds.
struct NightSleep: Identifiable {
    let id = UUID()
    /// The calendar day this night is attributed to (the wake-up day).
    let day: Date
    let core: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval
    /// Time scored as "awake" inside the sleep window (not counted as asleep).
    let awake: TimeInterval

    /// Total time actually asleep (excludes awake and inBed).
    var totalAsleep: TimeInterval { core + deep + rem }

    /// Deep + REM — the "restorative" stages from your onboarding copy.
    var restorative: TimeInterval { deep + rem }

    /// Restorative fraction of total sleep (0...1). Returns 0 if no sleep.
    var restorativeFraction: Double {
        totalAsleep > 0 ? restorative / totalAsleep : 0
    }
}

/// Maps HKCategoryValueSleepAnalysis raw values into our stage buckets.
enum SleepStage {
    case core, deep, rem, awake, inBed, unspecified

    init?(rawValue: Int) {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return nil }
        switch v {
        case .asleepCore:        self = .core
        case .asleepDeep:        self = .deep
        case .asleepREM:         self = .rem
        case .asleepUnspecified: self = .unspecified
        case .awake:             self = .awake
        case .inBed:             self = .inBed
        @unknown default:        return nil
        }
    }
}
