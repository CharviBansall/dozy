//
//  Naptimer.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//

import Foundation
import SwiftUI
import UserNotifications
import Combine


/// Drives a single nap timer: an on-screen countdown plus a local notification
/// that fires when the nap ends (even if the app is backgrounded or the phone
/// is locked). Everything is on-device.
@MainActor
final class NapTimer: ObservableObject {

    @Published var isRunning = false
    @Published var remaining: TimeInterval = 0   // seconds left
    @Published var total: TimeInterval = 0        // the full nap length

    private var endDate: Date?
    private var startDate: Date?
    private var ticker: Timer?
    private let notificationID = "dozy.nap.alarm"

    /// Called when a nap finishes naturally, with the nap's start/end times,
    /// so the app can log it to Health and refresh sleep debt.
    var onNapCompleted: ((Date, Date) -> Void)?

    /// Fraction elapsed, 0...1 — handy for a progress ring on the blob.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    var remainingDisplay: String {
        let s = max(Int(remaining.rounded()), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Start / stop

    func toggle(length: TimeInterval) {
        isRunning ? stop() : start(length: length)
    }

    func start(length: TimeInterval) {
        total = length
        remaining = length
        let now = Date()
        startDate = now
        let end = now.addingTimeInterval(length)
        endDate = end
        isRunning = true

        scheduleNotification(at: end)
        startTicking()
    }

    func stop() {
        isRunning = false
        endDate = nil
        remaining = 0
        ticker?.invalidate(); ticker = nil
        cancelNotification()
    }

    // MARK: - Ticking (foreground display)

    private func startTicking() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                RunLoop.main.add(timer, forMode: .common)
                ticker = timer
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        isRunning = false
        ticker?.invalidate(); ticker = nil
        // Log the completed nap (start → now) so it counts toward recovery.
        if let start = startDate {
            onNapCompleted?(start, Date())
        }
        endDate = nil
        startDate = nil
        // The notification handles the actual alert; nothing else needed here.
    }

    // MARK: - Notifications

    /// Ask for permission once (call when entering the nap screen).
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Time to wake up"
        content.body = "Your nap is complete. Ease back in gently."
        content.sound = .default

        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID,
                                            content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
