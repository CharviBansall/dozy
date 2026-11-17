//
//  Morningbrief.swift
//  dozy
//
//  The morning notification: what last night did to the debt, and today's one thing.
//
//  HealthKit wakes the app when new sleep data lands. Dozy recomputes, then schedules
//  the notification 30 minutes out. If more sleep arrives in the meantime (the user
//  was still asleep), it is rescheduled with the new numbers, so it only goes out
//  once the night has settled.
//

import Foundation
import UIKit
import UserNotifications

enum MorningBrief {
    private static let enabledKey = "morning.brief.enabled"
    private static let entitledKey = "morning.brief.entitled"
    private static let lastNightKey = "morning.brief.lastNight"
    private static let notificationID = "dozy.morning.brief"
    private static let settleDelay: TimeInterval = 30 * 60

    /// The Profile toggle. On unless the user turned it off.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { startObserving() } else { cancelPending() }
        }
    }

    /// Mirrors the subscription, so a background launch knows without asking StoreKit.
    static var isEntitled: Bool {
        get { UserDefaults.standard.bool(forKey: entitledKey) }
        set { UserDefaults.standard.set(newValue, forKey: entitledKey) }
    }

    /// Call at every launch, and again once Health access has been granted.
    static func startObserving() {
        guard isEnabled, isEntitled,
              UserDefaults.standard.bool(forKey: "hasOnboarded") else { return }
        SleepHealthStore.shared.observeSleep { await refresh() }
    }

    /// The user is looking at the app, so the notification would only repeat it.
    static func cancelPending() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    /// Runs whenever HealthKit reports new sleep data.
    static func refresh() async {
        guard isEnabled, isEntitled else { return }
        // Mornings only: a nap logged in the afternoon must not trigger it.
        let hour = Calendar.current.component(.hour, from: .now)
        guard (4..<13).contains(hour) else { return }

        let vm = SleepViewModel()
        await vm.load()
        guard let brief = vm.morningBrief, let night = vm.latestNight else { return }

        // One notification per version of the night: same data, nothing new to say.
        let stamp = "\(Int(night.day.timeIntervalSince1970))-\(Int(night.wake?.timeIntervalSince1970 ?? 0))-\(Int(night.totalAsleep))"
        guard stamp != UserDefaults.standard.string(forKey: lastNightKey) else { return }
        UserDefaults.standard.set(stamp, forKey: lastNightKey)

        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = brief.title
        content.body = brief.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: settleDelay, repeats: false)
        // Same identifier each time, so a newer version replaces the pending one.
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
