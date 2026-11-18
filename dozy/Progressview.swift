//
//  Progressview.swift
//  dozy
//
//  The Progress tab: how the debt has moved, and the measures behind it.
//

import SwiftUI
import Charts

struct ProgressScreen: View {
    @EnvironmentObject var vm: SleepViewModel
    @State private var range: Span = .twoWeeks
    @State private var selectedDay: Date? = nil

    enum Span: String, CaseIterable, Identifiable {
        case week = "W", twoWeeks = "2W", month = "M", sixMonths = "6M"
        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: return 7
            case .twoWeeks: return 14
            case .month: return 30
            case .sixMonths: return 180
            }
        }

        var caption: String {
            switch self {
            case .week: return "Last 7 days"
            case .twoWeeks: return "Last 14 days"
            case .month: return "Last 30 days"
            case .sixMonths: return "Last 6 months"
            }
        }
    }

    /// One bar: a day, or a week's average on the six-month view.
    private struct Bar: Identifiable {
        var id: Date { start }
        let start: Date
        let end: Date
        let balance: TimeInterval
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(title: "Progress", date: range.caption)

                Picker("Range", selection: $range) {
                    ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: range) { _, _ in selectedDay = nil }

                if points.isEmpty {
                    HighlightRow(icon: "moon.zzz",
                                 tint: Theme.secondary,
                                 title: "No sleep data yet",
                                 detail: "Wear your watch or tracker to bed and your nights will appear here.")
                } else {
                    chartCard
                }

                Text("Highlights")
                    .font(Theme.serif(22))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)

                NavigationLink {
                    SleepDebtView()
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(icon: "flame.fill", title: "Sleep Debt", color: Theme.debtRed)
                        Text(weekSummary)
                            .font(Theme.body(17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .healthCard()
                }
                .buttonStyle(.plain)

                Text("Behind the Number")
                    .font(Theme.serif(22))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)

                wakeCard
                stageCards
                signalsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        // 1pt keeps scrolled content from sliding under the status bar.
        .padding(.top, 1)
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Data for the chosen range

    private var points: [SleepViewModel.DebtPoint] {
        Array(vm.debtHistory.suffix(range.days))
    }

    private var bars: [Bar] {
        guard range == .sixMonths else {
            return points.map { Bar(start: $0.day, end: $0.day, balance: $0.balance) }
        }
        // 180 daily bars are unreadable on a phone: average each week instead.
        var result: [Bar] = []
        var index = points.endIndex
        while index > points.startIndex {
            let lower = max(points.startIndex, index - 7)
            let week = points[lower..<index]
            let average = week.map(\.balance).reduce(0, +) / Double(week.count)
            result.insert(Bar(start: week.first!.day, end: week.last!.day, balance: average), at: 0)
            index = lower
        }
        return result
    }

    private var averageDebt: TimeInterval {
        guard !points.isEmpty else { return 0 }
        return points.map(\.balance).reduce(0, +) / Double(points.count)
    }

    /// The top of the chart, in minutes.
    private var scaleTop: Double {
        let peak = (bars.map(\.balance).max() ?? 0) / 60
        return max(60, (peak / 30).rounded(.up) * 30)
    }

    private var selectedBar: Bar? {
        guard let selectedDay else { return nil }
        return bars.first { $0.start <= selectedDay && selectedDay <= $0.end }
    }

    // MARK: - Chart

    private var chartCard: some View {
        let shown = bars
        let selected = selectedBar
        return VStack(alignment: .leading, spacing: 6) {
            Text(selected == nil ? "AVERAGE DEBT" : "DEBT")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.secondary)

            if let selected, selected.balance < 60 {
                Text("None")
                    .font(Theme.number(28))
                    .foregroundStyle(Theme.text)
            } else {
                DurationText(seconds: selected?.balance ?? averageDebt)
            }

            Text(selected.map { dateRange($0.start, $0.end) }
                 ?? dateRange(points.first?.day ?? .now, points.last?.day ?? .now))
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.secondary)

            Chart(shown) { bar in
                BarMark(
                    x: .value("Day", bar.start, unit: range == .sixMonths ? .weekOfYear : .day),
                    // A sliver for a debt-free day, so the day still reads as recorded.
                    y: .value("Debt (min)", max(bar.balance / 60, scaleTop * 0.015))
                )
                .foregroundStyle(barColor(bar, selected: selected, last: shown.last))
                .cornerRadius(3)
            }
            // Never less than an hour tall, so small debts don't fill the chart.
            .chartYScale(domain: 0...scaleTop)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(axisLabel(minutes)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: range == .sixMonths
                                   ? .dateTime.month(.abbreviated)
                                   : .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Theme.secondary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let plotX = value.location.x - geo[plotFrame].origin.x
                                    if let day: Date = proxy.value(atX: plotX) {
                                        selectedDay = Calendar.current.startOfDay(for: day)
                                    }
                                }
                                .onEnded { _ in selectedDay = nil }
                        )
                }
            }
            .frame(height: 200)
            .padding(.top, 8)
        }
        .healthCard()
    }

    private func barColor(_ bar: Bar, selected: Bar?, last: Bar?) -> Color {
        if let selected {
            return bar.id == selected.id ? Theme.debtRed : Theme.debtRed.opacity(0.3)
        }
        // The newest bar is the one that matters today; the rest are history.
        return bar.id == last?.id ? Theme.debtRed : Theme.debtRed.opacity(0.45)
    }

    private func axisLabel(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }

    private func dateRange(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let year = DateFormatter(); year.dateFormat = "MMM d, yyyy"
        if Calendar.current.isDate(start, inSameDayAs: end) { return year.string(from: end) }
        return "\(f.string(from: start)) – \(year.string(from: end))"
    }

    // MARK: - This week, in a sentence

    private var weekSummary: String {
        let history = vm.debtHistory
        guard let today = history.last, vm.nightsInWindow > 0 else {
            return "Track a few nights and Dozy will tell you how your week went."
        }
        let outlook = vm.payoffText ?? "You’re all caught up."
        guard history.count >= 8 else {
            return today.balance < 60 ? outlook : "You owe \(SleepViewModel.duration(today.balance)). \(outlook)"
        }
        let weekAgo = history[history.count - 8].balance
        let change = today.balance - weekAgo
        if change <= -5 * 60 {
            return "You paid back \(SleepViewModel.duration(-change)) this week. \(outlook)"
        } else if change >= 5 * 60 {
            return "Your debt grew by \(SleepViewModel.duration(change)) this week. \(outlook)"
        }
        return today.balance < 60
            ? "No debt this week. \(outlook)"
            : "Your debt held steady this week. \(outlook)"
    }

    // MARK: - Behind the number

    private var wakeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: "alarm.fill", title: "Wake-Up Consistency",
                       color: Theme.accentBlue, showsChevron: false)
            if let spread = vm.wakeSpreadMinutes {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("±\(spread)").font(Theme.number(28)).foregroundStyle(Theme.text)
                    Text("min").font(Theme.body(15, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
            } else {
                Text("–").font(Theme.number(28)).foregroundStyle(Theme.text)
            }
            Text(wakeNote)
                .font(Theme.body(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }

    private var wakeNote: String {
        guard let spread = vm.wakeSpreadMinutes, let usual = vm.usualWakeText else {
            return "Dozy needs a few more nights to learn your usual wake-up."
        }
        if spread <= 30 { return "Steady around \(usual)" }
        if spread <= 60 { return "Drifting a little. Try to wake within 30 minutes of \(usual)." }
        return "Your wake-up moves around a lot. Waking near \(usual) every day helps most."
    }

    @ViewBuilder
    private var stageCards: some View {
        if let night = vm.latestNight, night.deep + night.rem > 0 {
            NavigationLink { RestorativeView() } label: {
                stageCard(icon: "bed.double.fill", title: "Deep Sleep", color: Theme.accentBlue,
                          value: night.deep, usual: vm.usualDeep,
                          history: vm.stageHistory.map(\.deep))
            }
            .buttonStyle(.plain)

            NavigationLink { RestorativeView() } label: {
                stageCard(icon: "sparkles", title: "REM Sleep", color: Theme.violet,
                          value: night.rem, usual: vm.usualREM,
                          history: vm.stageHistory.map(\.rem))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(icon: "sparkles", title: "Deep and REM Sleep",
                           color: Theme.violet, showsChevron: false)
                Text("No sleep stages were recorded last night. They come from a watch or tracker worn overnight.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .healthCard()
        }
    }

    private func stageCard(icon: String, title: String, color: Color,
                           value: TimeInterval, usual: TimeInterval?,
                           history: [TimeInterval]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: icon, title: title, color: color)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    DurationText(seconds: value)
                    Text(stageNote(value, usual: usual))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                MiniBars(values: history, color: color)
            }
        }
        .healthCard()
    }

    // MARK: - Overnight signals

    @ViewBuilder
    private var signalsCard: some View {
        if let signals = vm.signals {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(icon: "heart.fill", title: "Overnight Signals",
                           color: Theme.debtRed, showsChevron: false)
                if let heartRate = signals.heartRate {
                    signalRow("Sleeping heart rate", heartRate, unit: "bpm", decimals: 0)
                }
                if let hrv = signals.hrv {
                    signalRow("Heart rate variability", hrv, unit: "ms", decimals: 0)
                }
                if let breathing = signals.breathing {
                    signalRow("Breathing rate", breathing, unit: "br/min", decimals: 1)
                }
                Text("Measured by your watch while you slept. A lower heart rate and higher variability than your usual tend to go with a more restful night.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .healthCard()
        }
    }

    private func signalRow(_ title: String, _ signal: SleepViewModel.Signal, unit: String,
                           decimals: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.text)
                Text(signalNote(signal, unit: unit, decimals: decimals))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.\(decimals)f", signal.lastNight))
                    .font(Theme.number(22))
                    .foregroundStyle(Theme.text)
                Text(unit)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func signalNote(_ signal: SleepViewModel.Signal, unit: String, decimals: Int) -> String {
        guard let usual = signal.usual else { return "Learning your usual" }
        let difference = signal.lastNight - usual
        let threshold = decimals == 0 ? 1.0 : 0.3
        if abs(difference) < threshold { return "About your usual" }
        let amount = String(format: "%.\(decimals)f", abs(difference))
        return "\(amount) \(unit) \(difference > 0 ? "above" : "below") your usual"
    }

    /// Compares last night with the person's own average, not a universal target.
    private func stageNote(_ value: TimeInterval, usual: TimeInterval?) -> String {
        guard let usual else { return "Dozy needs a few more nights to learn your usual." }
        let difference = value - usual
        if abs(difference) < 5 * 60 { return "About your usual" }
        let direction = difference > 0 ? "more" : "less"
        return "\(SleepViewModel.duration(abs(difference))) \(direction) than your usual"
    }
}

/// A row of small bars for the last few nights; the newest is in colour.
private struct MiniBars: View {
    let values: [TimeInterval]
    let color: Color

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == values.count - 1 ? color : Theme.track)
                    .frame(width: 10, height: max(4, 30 * CGFloat(value / peak)))
            }
        }
        .frame(height: 30, alignment: .bottom)
    }
}
