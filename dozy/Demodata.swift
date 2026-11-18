//
//  Demodata.swift
//  dozy
//
//  Sample nights for taking App Store screenshots. Debug builds only: none of
//  this is compiled into the build that ships.
//

#if DEBUG
import Foundation

enum DemoData {
    private static let key = "debug.demoData"

    /// The "Demo Data" switch under You → About.
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Minutes asleep for the last 30 nights, oldest first; the last is last night.
    /// Chosen so the plan lands on about 1 hr 20 min owed, with last night paying some back.
    private static let recentMinutes: [Double] = [
        462, 471, 455, 480, 468, 449, 476, 470, 458, 483, 466, 452, 474, 481, 460, 472,
        478, 512, 470, 496, 528, 484, 462, 515, 474, 492, 448, 506, 452, 520,
    ]

    /// Five months of nights ending this morning.
    static func nights(now: Date = .now, calendar: Calendar = .current) -> [NightSleep] {
        let today = calendar.startOfDay(for: now)
        let total = 150
        var result: [NightSleep] = []

        for daysAgo in 0..<total {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let i = Double(daysAgo)

            let asleepMinutes: Double
            if daysAgo < recentMinutes.count {
                asleepMinutes = recentMinutes[recentMinutes.count - 1 - daysAgo]
            } else {
                asleepMinutes = 468 + 22 * sin(i * 0.7) + 14 * sin(i * 1.9)
            }

            // Last night matches the figures in the design; earlier nights wander a little.
            let deep = daysAgo == 0 ? 72.0 : asleepMinutes * (0.16 + 0.025 * sin(i * 1.3))
            let rem = daysAgo == 0 ? 94.0 : asleepMinutes * (0.21 + 0.03 * sin(i * 0.8 + 1))
            let core = asleepMinutes - deep - rem
            let awake = 18 + 6 * sin(i * 1.1)

            let wakeOffset = (12 * sin(i * 0.9) + 6 * sin(i * 2.1)).rounded()
            let wake = day.addingTimeInterval((7 * 60 + wakeOffset) * 60)
            let start = wake.addingTimeInterval(-(asleepMinutes + awake) * 60)

            result.append(NightSleep(day: day, core: core * 60, deep: deep * 60, rem: rem * 60,
                                     awake: awake * 60, wake: wake, start: start))
        }
        return result
    }

    static let signals = SleepViewModel.OvernightSignals(
        heartRate: .init(lastNight: 54, usual: 56.4),
        hrv: .init(lastNight: 62, usual: 57.2),
        breathing: .init(lastNight: 14.2, usual: 14.4)
    )
}
#endif
