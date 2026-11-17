//
//  Summaryview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI

/// Today. Reads top to bottom as one chain: the one thing to do, where the three
/// measures stand, then what you owe and what last night did about it.
struct SummaryView: View {
    @EnvironmentObject var vm: SleepViewModel
    @State private var showRingsInfo = false

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: .now)
    }

    private var updatedString: String {
        guard let updated = vm.lastUpdated else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: updated)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(title: "Today", date: dateString)
                    .padding(.bottom, 4)

                if vm.lastUpdated != nil {
                    if let action = vm.todayAction {
                        TodayActionCard(action: action)
                    }

                    ringsCard

                    Text("Pinned")
                        .font(Theme.serif(22))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 10)

                    NavigationLink { SleepDebtView() } label: { DebtCard(time: updatedString) }
                        .buttonStyle(.plain)

                    if let result = vm.lastNightResult {
                        LastNightCard(result: result, time: updatedString)
                    }

                    // When today's action is a nap, that card already opens the timer.
                    if case .bedtime? = vm.todayAction {
                        NavigationLink { NapWindowView() } label: { NapCard() }
                            .buttonStyle(.plain)
                    }
                } else if let message = vm.errorMessage, !vm.isLoading {
                    Text(message)
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        // 1pt keeps scrolled content from sliding under the status bar.
        .padding(.top, 1)
        .background(Theme.background.ignoresSafeArea())
        .task { await vm.load() }
        .overlay {
            if vm.isLoading { ProgressView().tint(Theme.secondary) }
        }
        .sheet(isPresented: $showRingsInfo) {
            RingsInfoSheet()
                .presentationDetents([.medium, .large])
        }
    }

    /// The three rings with their values beside them, like the Activity summary.
    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sleep Rings")
                    .font(Theme.body(15, weight: .semibold))
                Spacer()
                Button { showRingsInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .foregroundStyle(Theme.text)

            HStack(spacing: 20) {
                ProgressRings(
                    restorative: vm.restorativeFraction / 0.40,    // 40% night = full ring
                    debt: min(vm.totalDebt / (8 * 3600), 1.0),     // 8h debt = full ring
                    nap: vm.napLength / (90 * 60)                  // 90 min = full ring
                )

                VStack(alignment: .leading, spacing: 8) {
                    legend("Debt", SleepViewModel.duration(vm.totalDebt), Theme.debtPink)
                    legend("Nap", SleepViewModel.duration(vm.napLength), Theme.cyan)
                    legend("Deep + REM", "\(vm.restorativeDisplay)%", Theme.violet)
                }
                Spacer(minLength: 0)
            }
        }
        .healthCard()
    }

    private func legend(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(Theme.body(13))
                .foregroundStyle(Theme.secondary)
            Text(value)
                .font(Theme.number(20))
                .foregroundStyle(color)
        }
    }
}

/// Sleep debt as a pinned card: the figure, what it means, and the 14-day balance.
struct DebtCard: View {
    @EnvironmentObject var vm: SleepViewModel
    var time: String = ""

    private var maxBalance: TimeInterval {
        max(vm.ledger.map(\.balance).max() ?? 0, 60)
    }

    /// Only draw the balance chart when there is a balance to show.
    private var hasHistory: Bool { vm.ledger.contains { $0.balance >= 60 } }

    /// Shown in place of a figure when a number would mislead.
    private var statusWord: String? {
        if vm.nightsInWindow == 0 { return "No sleep data yet" }
        if vm.totalDebt < 60 { return "Caught up" }
        return nil
    }

    private var note: String {
        let need = SleepViewModel.duration(vm.sleepNeed)
        let nights = vm.nightsInWindow
        if nights == 0 { return "Wear your watch or tracker to bed tonight and Dozy will work out what you owe." }
        if nights < 3 { return "Based on only \(nights) night\(nights == 1 ? "" : "s") so far, so treat this as a first guess." }
        if vm.totalDebt < 60 { return "No sleep debt. You need about \(need) a night." }
        return vm.payoffText ?? "Owed against the \(need) a night you need."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: "moon.fill", title: "Sleep Debt", color: Theme.debtPink, trailing: time)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let statusWord {
                        Text(statusWord)
                            .font(Theme.number(24))
                            .foregroundStyle(Theme.text)
                    } else {
                        DurationText(seconds: vm.totalDebt)
                    }
                    Text(note)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if hasHistory {
                    // Running balance, oldest day on the left, today on the right.
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(vm.ledger) { day in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(day.day == vm.ledger.last?.day ? Theme.debtPink : Theme.track)
                                .frame(width: 4, height: max(3, 36 * CGFloat(day.balance / maxBalance)))
                        }
                    }
                    .frame(height: 36, alignment: .bottom)
                }
            }
        }
        .healthCard()
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
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(value)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(tint)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Text(note)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Three concentric rings: debt (outer), nap, deep + REM (inner).
/// They fill from empty each time the screen appears, one after another.
struct ProgressRings: View {
    var restorative: Double   // 0...1, fills toward the 40% goal
    var debt: Double          // 0...1, normalized debt (fuller = more debt)
    var nap: Double           // 0...1, nap length vs a 90-min max
    var diameter: CGFloat = 116
    var lineWidth: CGFloat = 10

    @State private var filled = false

    var body: some View {
        let step = (lineWidth + 4) * 2
        ZStack {
            ring(progress: debt,        color: Theme.debtPink, size: diameter,            delay: 0)
            ring(progress: nap,         color: Theme.cyan,     size: diameter - step,     delay: 0.15)
            ring(progress: restorative, color: Theme.violet,   size: diameter - 2 * step, delay: 0.3)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { filled = true }
        .onDisappear { filled = false }
    }

    private func ring(progress: Double, color: Color, size: CGFloat, delay: Double) -> some View {
        let target = CGFloat(min(max(progress, 0), 1))
        return ZStack {
            // Faint track behind the fill.
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: filled ? target : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // A rounded cap would leave a dot on an empty ring.
                .opacity(target > 0 ? 1 : 0)
                // Fill on appear, staggered; then follow the data when it changes.
                .animation(.easeOut(duration: 1.1).delay(delay), value: filled)
                .animation(.easeOut(duration: 0.8), value: target)
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
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.serif(24))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.bottom, 4)

                ringBox(
                    color: Theme.debtPink,
                    title: "Sleep Debt",
                    body: "How much sleep you've missed versus what your body needs, added up over the last two weeks. This ring fills as debt grows — an emptier ring is better."
                )
                ringBox(
                    color: Theme.cyan,
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
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
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
                    .foregroundStyle(Theme.text)
                Text(body)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
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
