//
//  Summaryview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI

/// Home. Reads top to bottom as one chain: what last night did, the one thing to do
/// today, what you owe, and the two measures behind that number.
struct SummaryView: View {
    @EnvironmentObject var vm: SleepViewModel
    @State private var showRingsInfo = false

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(Theme.serif(40))
                            .foregroundStyle(.white)
                        Text(dateString)
                            .font(Theme.body(14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }

                if vm.lastUpdated != nil {
                    TodayPlanSection()

                    ZStack(alignment: .topTrailing) {
                        ProgressRings(
                            restorative: vm.restorativeFraction / 0.40,    // 40% night = full ring
                            debt: min(vm.totalDebt / (8 * 3600), 1.0),     // 8h debt = full ring
                            nap: vm.napLength / (90 * 60)                  // 90 min = full ring
                        )
                        // The orb lives in the centre of the rings and reacts to debt.
                        .overlay { DozyOrb(debt: vm.totalDebt, size: 112) }
                        .frame(maxWidth: .infinity)

                        Button { showRingsInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(Theme.serif(20))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(height: 252)

                    NavigationLink { SleepDebtView() } label: { DebtCard() }
                        .buttonStyle(.plain)
                } else if let message = vm.errorMessage, !vm.isLoading {
                    Text(message)
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        // 1pt keeps scrolled content from sliding under the status bar.
        .padding(.top, 1)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .task { await vm.load() }
        .overlay {
            if vm.isLoading { ProgressView().tint(.white) }
        }
        .sheet(isPresented: $showRingsInfo) {
            RingsInfoSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// The debt number, with the 14-day balance behind it.
struct DebtCard: View {
    @EnvironmentObject var vm: SleepViewModel

    private var maxBalance: TimeInterval {
        max(vm.ledger.map(\.balance).max() ?? 0, 60)
    }

    /// Only draw the balance chart when there is a balance to show.
    private var hasHistory: Bool { vm.ledger.contains { $0.balance >= 60 } }

    private var headline: String {
        if vm.nightsInWindow == 0 { return "No sleep data yet" }
        if vm.totalDebt < 60 { return "Caught up" }
        return SleepViewModel.duration(vm.totalDebt)
    }

    private var detail: String {
        let need = SleepViewModel.duration(vm.sleepNeed)
        let nights = vm.nightsInWindow
        if nights == 0 {
            return "Wear your watch or tracker to bed tonight and Dozy will work out what you owe."
        }
        if nights < 3 {
            return "Based on only \(nights) night\(nights == 1 ? "" : "s") in the last two weeks, so treat this as a first guess."
        }
        if vm.totalDebt < 60 { return "No sleep debt. You need about \(need) a night." }
        return "Owed against the \(need) a night you need."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SLEEP DEBT")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.debtPink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.body(12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(headline)
                .font(Theme.serif(vm.nightsInWindow == 0 ? 34 : 44))
                .foregroundStyle(.white)

            Text(detail)
                .font(Theme.body(14))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            if let payoff = vm.payoffText {
                Label(payoff, systemImage: "flag.checkered")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.cyan)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasHistory {
                // Running balance, oldest day on the left, today on the right.
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(vm.ledger) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.debtPink.opacity(day.day == vm.ledger.last?.day ? 1 : 0.4))
                            .frame(height: max(3, 40 * CGFloat(day.balance / maxBalance)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 40, alignment: .bottom)
                .padding(.top, 4)

                Text("Last 14 days")
                    .font(Theme.body(11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A compact supporting measure: icon, title, value, one line of guidance.
struct DetailRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let note: String
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(Theme.body(16))
                .foregroundStyle(tint)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(Theme.serif(16))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(value)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(tint)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(Theme.body(12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Text(note)
                    .font(Theme.body(13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Three concentric activity rings driven by the real metrics.
/// Each ring shows progress 0...1 toward its goal, with a faint track behind.
struct ProgressRings: View {
    var restorative: Double   // 0...1, fills toward the 40% goal
    var debt: Double          // 0...1, normalized debt (fuller = more debt)
    var nap: Double           // 0...1, nap length vs a 90-min max

    @State private var animate = false

    private let debtColor = Color(red: 0.90, green: 0.25, blue: 0.45)
    private let napColor  = Color(red: 0.30, green: 0.80, blue: 0.85)
    private let restColor = Theme.violet

    var body: some View {
        ZStack {
            ring(progress: debt,        color: debtColor, size: 236)
            ring(progress: nap,         color: napColor,  size: 204)
            ring(progress: restorative, color: restColor, size: 172)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animate = true }
        }
    }

    private func ring(progress: Double, color: Color, size: CGFloat) -> some View {
        ZStack {
            // Faint track behind the fill.
            Circle()
                .stroke(color.opacity(0.15),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
            // Filled progress.
            Circle()
                .trim(from: 0, to: animate ? CGFloat(min(max(progress, 0), 1)) : 0)
                .stroke(color,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 6)
        }
        .frame(width: size, height: size)
    }
}

/// Explains what each of the three rings represents.
struct RingsInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your Rings")
                        .font(Theme.serif(28))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.serif(24))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.bottom, 4)

                ringBox(
                    color: Color(red: 0.90, green: 0.25, blue: 0.45),
                    title: "Sleep Debt",
                    body: "How much sleep you've missed versus what your body needs, added up over the last two weeks. This ring fills as debt grows — an emptier ring is better."
                )
                ringBox(
                    color: Color(red: 0.30, green: 0.80, blue: 0.85),
                    title: "Nap Window",
                    body: "The nap length Dozy recommends right now, based on your current debt. A longer recommended nap fills the ring more. It's a suggestion, not a goal."
                )
                ringBox(
                    color: Theme.violet,
                    title: "Restorative",
                    body: "The share of last night that was deep or REM sleep — the stages that actually repair you. The goal is about 40% of your night, which fills the ring completely."
                )
            }
            .padding(24)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
        .presentationBackground(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    private func ringBox(color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .stroke(color, lineWidth: 5)
                .frame(width: 26, height: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.serif(17))
                    .foregroundStyle(.white)
                Text(body)
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// The two measures behind the debt number: wake-up consistency and deep + REM.
struct BehindTheNumberRows: View {
    @EnvironmentObject var vm: SleepViewModel

    var body: some View {
        VStack(spacing: 10) {
            DetailRow(icon: "alarm.fill",
                      tint: Theme.accentBlue,
                      title: "Wake-up consistency",
                      value: wakeValue,
                      note: wakeNote,
                      showsChevron: false)

            if let night = vm.latestNight, night.deep + night.rem > 0 {
                NavigationLink { RestorativeView() } label: {
                    DetailRow(icon: "bed.double.fill",
                              tint: Theme.accentBlue,
                              title: "Deep sleep last night",
                              value: SleepViewModel.duration(night.deep),
                              note: stageNote(night.deep, usual: vm.usualDeep),
                              showsChevron: true)
                }
                .buttonStyle(.plain)

                NavigationLink { RestorativeView() } label: {
                    DetailRow(icon: "sparkles",
                              tint: Theme.violet,
                              title: "REM sleep last night",
                              value: SleepViewModel.duration(night.rem),
                              note: stageNote(night.rem, usual: vm.usualREM),
                              showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                DetailRow(icon: "sparkles",
                          tint: Theme.violet,
                          title: "Deep and REM sleep",
                          value: "–",
                          note: "No sleep stages were recorded last night. They come from a watch or tracker worn overnight.",
                          showsChevron: false)
            }
        }
    }

    /// Compares last night with the person's own average, not a universal target.
    private func stageNote(_ value: TimeInterval, usual: TimeInterval?) -> String {
        guard let usual else { return "Dozy needs a few more nights to learn your usual." }
        let difference = value - usual
        let usualText = SleepViewModel.duration(usual)
        if abs(difference) < 5 * 60 { return "About your usual \(usualText)." }
        let direction = difference > 0 ? "more" : "less"
        return "\(SleepViewModel.duration(abs(difference))) \(direction) than your usual \(usualText)."
    }

    private var wakeValue: String {
        guard let spread = vm.wakeSpreadMinutes else { return "–" }
        return "±\(spread) min"
    }

    private var wakeNote: String {
        guard let spread = vm.wakeSpreadMinutes, let usual = vm.usualWakeText else {
            return "Dozy needs a few more nights to learn your usual wake-up."
        }
        if spread <= 30 {
            return "Steady around \(usual). A regular wake-up makes every night easier."
        } else if spread <= 60 {
            return "Drifting a little. Try to wake within 30 minutes of \(usual)."
        }
        return "Your wake-up moves around a lot. Waking near \(usual) every day, weekends included, helps most."
    }
}
