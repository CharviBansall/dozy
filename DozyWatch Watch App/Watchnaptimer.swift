//
//  Watchnaptimer.swift
//  dozy
//
//  Created by Charvi Bansal on 6/10/26.
//

import Foundation
import SwiftUI
import WatchKit
import UserNotifications
import Combine
/// Watch nap timer. Counts down on screen and fires WRIST HAPTICS plus a
/// local notification when the nap ends — the gentle wake Dozy promises.
@MainActor
final class WatchNapTimer: ObservableObject {

    @Published var isRunning = false
    @Published var remaining: TimeInterval = 0
    @Published var total: TimeInterval = 0

    private var endDate: Date?
    private var ticker: Timer?

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    var remainingDisplay: String {
        let s = max(Int(remaining.rounded()), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func toggle(minutes: Int) {
        isRunning ? stop() : start(minutes: minutes)
    }

    func start(minutes: Int) {
        let length = TimeInterval(minutes * 60)
        total = length
        remaining = length
        let end = Date().addingTimeInterval(length)
        endDate = end
        isRunning = true

        scheduleNotification(at: end)
        WKInterfaceDevice.current().play(.start)   // confirm tap

        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stop() {
        isRunning = false
        endDate = nil
        remaining = 0
        ticker?.invalidate(); ticker = nil
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["dozy.watch.nap"])
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        isRunning = false
        ticker?.invalidate(); ticker = nil
        endDate = nil
        // Strong haptic wake on the wrist.
        let device = WKInterfaceDevice.current()
        device.play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { device.play(.notification) }
    }

    private func scheduleNotification(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Time to wake up"
        content.body = "Your nap is complete."
        content.sound = .default
        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let req = UNNotificationRequest(identifier: "dozy.watch.nap", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
