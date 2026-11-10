//
//  Summarydebtview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI
import Charts

struct SleepDebtView: View {
    @EnvironmentObject var vm: SleepViewModel
    @State private var selectedDay: Date? = nil

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep Debt")
                        .font(Theme.serif(40))
                        .foregroundStyle(.white)
                    Text(dateString)
                        .font(Theme.body(14))
                        .foregroundStyle(.white.opacity(0.6))
                }

                chart

                Text("Highlights")
                    .font(Theme.serif(20))
                    .foregroundStyle(.white)

                if highlights.isEmpty {
                    HighlightRow(icon: "moon.zzz",
                                 tint: .white.opacity(0.5),
                                 title: "Not enough sleep yet",
                                 detail: "Track a few nights and your highlights will appear here.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(highlights) { h in
                            HighlightRow(icon: h.icon, tint: h.tint,
                                         title: h.title, detail: h.detail)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea())
    }

    // MARK: - Chart with tap-to-read

    private var debtColor: Color { Color(red: 0.95, green: 0.2, blue: 0.2) }

    private var selectedEntry: (day: Date, debt: TimeInterval)? {
        guard let selectedDay else { return nil }
        return vm.dailyDebt.first {
            Calendar.current.isDate($0.day, inSameDayAs: selectedDay)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Readout above the chart — shows the touched bar, or a hint.
            if let sel = selectedEntry {
                HStack(spacing: 6) {
                    Text(fullDate(sel.day))
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(sel.debt < 60 ? "no debt" : "\(short(sel.debt)) behind")
                        .foregroundStyle(debtColor)
                }
                .font(Theme.body(14))
            } else {
                Text("Touch a bar to see that day")
                    .font(Theme.body(13))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Chart(vm.dailyDebt, id: \.day) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Debt (min)", item.debt / 60)
                )
                .foregroundStyle(
                    selectedDay.map { Calendar.current.isDate($0, inSameDayAs: item.day) } == true
                        ? debtColor
                        : debtColor.opacity(selectedDay == nil ? 1.0 : 0.4)
                )
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
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
                                .onEnded { _ in
                                    // Keep the selection visible after lifting the finger.
                                }
                        )
                }
            }
            .frame(height: 280)
        }
    }

    // MARK: - Computed highlights

    private struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let detail: String
    }

    private var highlights: [Highlight] {
        let days = vm.dailyDebt
        guard !days.isEmpty else { return [] }

        var result: [Highlight] = []
        let green = Color(red: 0.3, green: 0.8, blue: 0.55)
        let red = Color(red: 0.95, green: 0.3, blue: 0.3)
        let blue = Color(red: 0.3, green: 0.65, blue: 1.0)

        if let best = days.min(by: { $0.debt < $1.debt }) {
            result.append(Highlight(
                icon: "star.fill", tint: green,
                title: "Best night",
                detail: best.debt < 60
                    ? "\(fullDate(best.day)) — you woke up fully rested."
                    : "\(fullDate(best.day)) — your smallest shortfall, about \(short(best.debt)) behind."
            ))
        }

        if let worst = days.max(by: { $0.debt < $1.debt }), worst.debt >= 60 {
            result.append(Highlight(
                icon: "exclamationmark.triangle.fill", tint: red,
                title: "Toughest night",
                detail: "\(fullDate(worst.day)) — about \(short(worst.debt)) short of what you needed."
            ))
        }

        if days.count >= 4 {
            let mid = days.count / 2
            let firstHalf = days.prefix(mid).map(\.debt).reduce(0, +) / Double(mid)
            let secondHalf = days.suffix(days.count - mid).map(\.debt).reduce(0, +) / Double(days.count - mid)
            let delta = secondHalf - firstHalf

            let (icon, tint, title, detail): (String, Color, String, String)
            if abs(delta) < 15 * 60 {
                (icon, tint, title, detail) = (
                    "equal.circle.fill", blue, "Holding steady",
                    "Your sleep debt has stayed fairly level these two weeks."
                )
            } else if delta < 0 {
                (icon, tint, title, detail) = (
                    "arrow.down.right.circle.fill", green, "Catching up",
                    "You've been recovering — debt is trending down."
                )
            } else {
                (icon, tint, title, detail) = (
                    "arrow.up.right.circle.fill", red, "Falling behind",
                    "Debt has been creeping up. An earlier night could help."
                )
            }
            result.append(Highlight(icon: icon, tint: tint, title: title, detail: detail))
        }

        return result
    }

    // MARK: - Formatting

    /// Weekday + date so there's no ambiguity over a two-week window.
    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    private func short(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m) min"
    }
}

/// One highlight callout row: icon, title, supporting line.
struct HighlightRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(Theme.serif(18))
                .foregroundStyle(tint)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.serif(16))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
