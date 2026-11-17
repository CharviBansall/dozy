//
//  Todayviews.swift
//  dozy
//
//  Home's "one thing to do today" card, and the feedback that shows it worked.
//

import SwiftUI

/// Good news uses the accent colour, not a separate green.
private let paidBackTint = Theme.cyan

private func clockTime(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: date)
}

/// Last night's result on top, today's action under it.
struct TodayPlanSection: View {
    @EnvironmentObject var vm: SleepViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = vm.lastNightResult {
                LastNightRow(result: result)
            }
            if let action = vm.todayAction {
                TodayActionCard(action: action)
            }
        }
    }
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

                Button { vm.skipNapToday() } label: {
                    Text("Can't nap today?")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.leading, 4)
            }

        case .bedtime(let plan):
            VStack(alignment: .leading, spacing: 10) {
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

                NavigationLink { NapWindowView() } label: {
                    Text("Nap timer")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.leading, 4)
            }
        }
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Theme.body(11))
                Text("TODAY'S ONE THING")
                    .font(Theme.body(11, weight: .semibold))
                    .tracking(1.2)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(Theme.body(12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .foregroundStyle(Theme.cyan)

            Text(title)
                .font(Theme.serif(28))
                .foregroundStyle(.white)

            Text(detail)
                .font(Theme.body(14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.cyan.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Results

/// What last night did to the debt.
struct LastNightRow: View {
    let result: SleepViewModel.LastNightResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.body(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var icon: String {
        switch result {
        case .paidBack: return "arrow.down.circle.fill"
        case .added:    return "arrow.up.circle.fill"
        case .steady:   return "equal.circle.fill"
        }
    }

    private var tint: Color {
        switch result {
        case .paidBack: return paidBackTint
        case .added:    return Theme.debtPink
        case .steady:   return Theme.accentBlue
        }
    }

    private var text: String {
        switch result {
        case .paidBack(let amount):
            return "Last night paid back \(SleepViewModel.duration(amount))"
        case .added(let amount):
            return "Last night added \(SleepViewModel.duration(amount)) to your debt"
        case .steady:
            return "Last night kept your debt level"
        }
    }
}

/// Shown on the Nap screen once a finished nap has been logged.
struct NapPaybackCard: View {
    let payback: SleepViewModel.NapPayback

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if payback.paidBack >= 60 {
                Label {
                    Text("That nap paid back \(SleepViewModel.duration(payback.paidBack))")
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(paidBackTint)
                }
                .font(Theme.serif(18))

                Text("Sleep debt: \(SleepViewModel.duration(payback.before)) → \(SleepViewModel.duration(payback.after))")
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Label {
                    Text("Nap done")
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.cyan)
                }
                .font(Theme.serif(18))

                Text("Your debt didn't move this time. Naps count for up to 30 minutes a day.")
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
