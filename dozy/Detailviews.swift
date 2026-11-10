//
//  Detailviews.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI

struct NapWindowView: View {
    @EnvironmentObject var vm: SleepViewModel
    @StateObject private var timer = NapTimer()

    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: .now)
    }

    private let accent = Color(red: 0.30, green: 0.80, blue: 0.85)
    private var napMinutes: Int { Int((vm.napLength / 60).rounded()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(title: "Nap Window", date: dateString)

                // Hero copy.
                VStack(alignment: .leading, spacing: 6) {
                    Text(timer.isRunning ? "Napping…" : "A \(napMinutes)-minute nap")
                        .font(Theme.serif(30))
                        .foregroundStyle(.white)
                    Text(timer.isRunning
                         ? "Rest easy — Dozy will wake you when it's time."
                         : napReason)
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The tappable blob timer.
                NapBlob(timer: timer, napLength: vm.napLength)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                // Hide the planning details while a nap is running.
                if !timer.isRunning {
                    napTimeline

                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text("Best between \(time(vm.napEarliest)) and \(time(vm.napLatest))")
                                .foregroundStyle(.white)
                        } icon: {
                            Image(systemName: "clock").foregroundStyle(accent)
                        }
                        .font(Theme.serif(16))

                        Text(expectation)
                            .font(Theme.body(15))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .onAppear {
            timer.requestNotificationPermission()
            timer.onNapCompleted = { start, end in
                Task {
                    try? await SleepHealthStore.shared.logNap(start: start, end: end)
                    await vm.load()   // refresh debt now that the nap is logged
                }
            }
        }
    }

    // MARK: - Timeline

    private var napTimeline: some View {
        let dayStart: TimeInterval = 12 * 3600
        let dayEnd: TimeInterval = 18 * 3600
        let span = dayEnd - dayStart

        func frac(_ date: Date) -> CGFloat {
            let cal = Calendar.current
            let secs = TimeInterval(cal.component(.hour, from: date) * 3600
                                    + cal.component(.minute, from: date) * 60)
            return CGFloat(min(max((secs - dayStart) / span, 0), 1))
        }

        let startF = frac(vm.napEarliest)
        let endF = frac(vm.napLatest)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [accent, Color(red: 0.1, green: 0.5, blue: 0.95)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(w * (endF - startF), 12), height: 10)
                        .offset(x: w * startF)
                        .shadow(color: accent.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 10)

            HStack {
                Text("Noon").font(Theme.body(11)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("6 PM").font(Theme.body(11)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Copy

    private var napReason: String {
        if vm.totalDebt < 20 * 60 {
            return "You're well rested, so a short refresher is all you need. Tap to begin."
        } else if vm.totalDebt < 120 * 60 {
            return "You've built up a little sleep debt. This nap helps you catch up. Tap to begin."
        } else {
            return "You're carrying real sleep debt. A full cycle gives proper recovery. Tap to begin."
        }
    }

    private var expectation: String {
        switch napMinutes {
        case ..<15:
            return "A quick reset for alertness — short enough that you'll wake up sharp, not groggy."
        case 15..<35:
            return "Long enough to feel genuinely refreshed, while staying light enough to wake easily."
        default:
            return "A full sleep cycle for deeper recovery. Give yourself a few minutes to shake off sleepiness afterward."
        }
    }
}

/// The signature orb, now a tappable nap timer with a progress ring.
struct NapBlob: View {
    @ObservedObject var timer: NapTimer
    let napLength: TimeInterval

    @State private var breathing = false
    private let accent = Color(red: 0.30, green: 0.80, blue: 0.85)

    var body: some View {
        Button {
            timer.toggle(length: napLength)
        } label: {
            ZStack {
                // Progress ring (only while running).
                if timer.isRunning {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 6)
                        .frame(width: 196, height: 196)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: accent.opacity(0.6), radius: 6)
                }

                // The orb.
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.30, green: 0.80, blue: 0.85),
                                 Color(red: 0.04, green: 0.36, blue: 0.98)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 170, height: 170)
                    .scaleEffect(breathing ? 1.04 : 0.96)
                    .shadow(color: Color(red: 0.1, green: 0.5, blue: 1.0)
                                .opacity(breathing ? 0.7 : 0.35),
                            radius: breathing ? 45 : 25)

                // Center label.
                VStack(spacing: 2) {
                    if timer.isRunning {
                        Text(timer.remainingDisplay)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("tap to cancel")
                            .font(Theme.body(12))
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        Image(systemName: "play.fill")
                            .font(Theme.serif(30))
                            .foregroundStyle(.white)
                        Text("start nap")
                            .font(Theme.body(13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

struct RestorativeView: View {
    @EnvironmentObject var vm: SleepViewModel
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: .now)
    }

    private let restColor = Color(red: 0.95, green: 0.6, blue: 0.1)
    private let deepColor = Color(red: 0.10, green: 0.45, blue: 0.95)
    private let remColor  = Color(red: 0.55, green: 0.45, blue: 0.95)
    private let lightColor = Color(red: 0.30, green: 0.80, blue: 0.85)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(title: "Restorative", date: dateString)

                if let night = vm.latestNight, night.totalAsleep > 0 {
                    gauge(fraction: vm.restorativeFraction)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                    breakdown(night: night)

                    Text(verdict)
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No sleep recorded yet. Once you've tracked a night, you'll see how much of it was truly restorative.")
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
    }

    // MARK: - Circular gauge vs the 40% goal

    private func gauge(fraction: Double) -> some View {
        let goal = 0.40
        let progress = min(fraction / goal, 1.0)   // full circle = hit the 40% goal
        return ZStack {
            Circle()
                .stroke(restColor.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(restColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: restColor.opacity(0.5), radius: 6)
            VStack(spacing: 0) {
                Text(vm.restorativeDisplay)
                    .font(Theme.serif(52))
                    .foregroundStyle(restColor)
                Text("% restorative")
                    .font(Theme.body(13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: - Stage breakdown bar

    private func breakdown(night: NightSleep) -> some View {
        let total = night.totalAsleep
        func pct(_ v: TimeInterval) -> CGFloat { total > 0 ? CGFloat(v / total) : 0 }

        return VStack(alignment: .leading, spacing: 14) {
            // Stacked proportion bar.
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    Capsule().fill(deepColor).frame(width: w * pct(night.deep))
                    Capsule().fill(remColor).frame(width: w * pct(night.rem))
                    Capsule().fill(lightColor).frame(width: w * pct(night.core))
                }
            }
            .frame(height: 12)

            // Legend with minutes.
            stageRow(color: deepColor, name: "Deep", value: night.deep)
            stageRow(color: remColor, name: "REM", value: night.rem)
            stageRow(color: lightColor, name: "Light", value: night.core)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stageRow(color: Color, name: String, value: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name).foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(mins(value)).foregroundStyle(.white).fontWeight(.medium)
        }
        .font(Theme.body(15))
    }

    private func mins(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    private var verdict: String {
        if vm.restorativeFraction >= 0.40 {
            return "Deep and REM sleep — the stages that truly repair you — made up a healthy share of your night. This is exactly where you want to be."
        } else if vm.restorativeFraction >= 0.30 {
            return "You got a solid amount of deep and REM sleep, just shy of the ideal. Consistent bedtimes nudge this higher over time."
        } else {
            return "A smaller share of your night was deep or REM sleep. Winding down earlier and keeping a steady schedule helps your body reach these deeper stages."
        }
    }
}

// Shared header used by detail screens.
@ViewBuilder
func header(title: String, date: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(Theme.serif(40))
            .foregroundStyle(.white)
        Text(date)
            .font(Theme.body(14))
            .foregroundStyle(.white.opacity(0.6))
    }
}
