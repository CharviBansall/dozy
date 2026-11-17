//
//  Todayviews.swift
//  dozy
//
//  Today's "one thing to do" card, and the cards that show it worked.
//

import SwiftUI

private func clockTime(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: date)
}

// MARK: - Today's action

struct TodayActionCard: View {
    @EnvironmentObject var vm: SleepViewModel
    let action: TodayAction

    var body: some View {
        switch action {
        case .nap(let length, let earliest, let latest):
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { NapWindowView() } label: {
                    card(icon: "moon.fill",
                         title: "Take a \(SleepViewModel.duration(length)) nap",
                         detail: napDetail(length: length, earliest: earliest, latest: latest),
                         showsChevron: true)
                }
                .buttonStyle(.plain)

                Button { vm.skipNapToday() } label: { link("Can't nap today?") }
            }

        case .bedtime(let plan):
            if plan.bedtime <= Date() {
                card(icon: "bed.double.fill",
                     title: "Head to bed now",
                     detail: "Your target was \(clockTime(plan.bedtime)). Every minute before your \(clockTime(plan.wake)) wake-up still counts.",
                     showsChevron: false)
            } else {
                card(icon: "bed.double.fill",
                     title: "Be in bed by \(clockTime(plan.bedtime))",
                     detail: bedtimeDetail(plan),
                     showsChevron: false)
            }
        }
    }

    private func link(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.cyan)
            .padding(.leading, 16)
    }

    private func napDetail(length: TimeInterval, earliest: Date, latest: Date) -> String {
        let payback = min(length, SleepAnalyzer.napCreditCap, vm.totalDebt)
        return "Best between \(clockTime(earliest)) and \(clockTime(latest)). It pays back about \(SleepViewModel.duration(payback)) of the \(SleepViewModel.duration(vm.totalDebt)) you owe."
    }

    private func bedtimeDetail(_ plan: BedtimePlan) -> String {
        if plan.extra >= 60 {
            return "That leaves room for \(SleepViewModel.duration(plan.extra)) of extra sleep before your \(clockTime(plan.wake)) wake-up, which comes straight off your debt."
        }
        return "You're on track. This covers what you need before your \(clockTime(plan.wake)) wake-up."
    }

    private func card(icon: String, title: String, detail: String, showsChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: icon, title: "Today's One Thing", color: Theme.cyan, showsChevron: showsChevron)

            Text(title)
                .font(Theme.serif(24))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)

            Text(detail)
                .font(Theme.body(15))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }
}

// MARK: - Nap

/// The way into the nap timer, as a proper card. Shown on Today whenever the
/// day's action is not already a nap.
struct NapCard: View {
    @EnvironmentObject var vm: SleepViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: "moon.fill", title: "Nap Timer", color: Theme.cyan)

            VStack(alignment: .leading, spacing: 2) {
                DurationText(seconds: vm.napLength)
                Text("Recommended nap. Best between \(clockTime(vm.napEarliest)) and \(clockTime(vm.napLatest)).")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .healthCard()
    }
}

// MARK: - Results

/// What last night did to the debt, as a pinned card.
struct LastNightCard: View {
    let result: SleepViewModel.LastNightResult
    var time: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: icon, title: "Last Night", color: tint, trailing: time, showsChevron: false)

            VStack(alignment: .leading, spacing: 2) {
                switch result {
                case .paidBack(let amount):
                    DurationText(seconds: amount)
                    caption("Paid back")
                case .added(let amount):
                    DurationText(seconds: amount)
                    caption("Added to your debt")
                case .steady:
                    Text("Level")
                        .font(Theme.number(24))
                        .foregroundStyle(Theme.text)
                    caption("Your debt didn't move")
                }
            }
        }
        .healthCard()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.secondary)
    }

    private var icon: String {
        switch result {
        case .paidBack: return "arrow.down.circle.fill"
        case .added:    return "arrow.up.circle.fill"
        case .steady:   return "equal.circle.fill"
        }
    }

    /// Good news uses the accent colour, not a separate green.
    private var tint: Color {
        switch result {
        case .paidBack: return Theme.cyan
        case .added:    return Theme.debtPink
        case .steady:   return Theme.accentBlue
        }
    }
}

/// Shown on the Nap screen once a finished nap has been logged.
struct NapPaybackCard: View {
    let payback: SleepViewModel.NapPayback

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if payback.paidBack >= 60 {
                CardHeader(icon: "arrow.down.circle.fill", title: "Nap Complete", color: Theme.cyan, showsChevron: false)
                DurationText(seconds: payback.paidBack)
                Text("Paid back. Sleep debt: \(SleepViewModel.duration(payback.before)) → \(SleepViewModel.duration(payback.after))")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
            } else {
                CardHeader(icon: "checkmark.circle.fill", title: "Nap Complete", color: Theme.cyan, showsChevron: false)
                Text("Your debt didn't move this time. Naps count for up to 30 minutes a day.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .healthCard()
    }
}
