//
//  Summaryview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var vm: SleepViewModel
    @State private var showRingsInfo = false

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
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
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Summary")
                            .font(Theme.serif(40))
                            .foregroundStyle(.white)
                        Text(dateString)
                            .font(Theme.body(14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.8, blue: 0.85),
                                                      Color(red: 0.05, green: 0.4, blue: 0.95)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                }

                ZStack(alignment: .topTrailing) {
                    ProgressRings(
                        restorative: vm.restorativeFraction / 0.40,    // 40% night = full ring
                        debt: min(vm.totalDebt / (8 * 3600), 1.0),     // 8h debt = full ring
                        nap: vm.napLength / (90 * 60)                  // 90 min = full ring
                    )
                    .frame(maxWidth: .infinity)

                    Button { showRingsInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(Theme.serif(20))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 240)

                MetricCard(title: "Sleep Debt", value: vm.debtDisplay, unit: "min",
                           accent: Color(red: 0.95, green: 0.2, blue: 0.2),
                           destination: AnyView(SleepDebtView()), time: updatedString)

                MetricCard(title: "Nap Window", value: vm.napDisplay, unit: "min",
                           accent: Color(red: 0.3, green: 0.8, blue: 0.85),
                           destination: AnyView(NapWindowView()), time: updatedString)

                MetricCard(title: "Restorative", value: vm.restorativeDisplay, unit: "%",
                           accent: Color(red: 0.95, green: 0.6, blue: 0.1),
                           destination: AnyView(RestorativeView()), time: updatedString)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
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

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let accent: Color
    let destination: AnyView
    var time: String = ""

    var body: some View {
        NavigationLink { destination } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(Theme.serif(17))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(time)
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.4))
                    Image(systemName: "chevron.right")
                        .font(Theme.body(12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(Theme.serif(34))
                        .foregroundStyle(accent)
                    Text(unit)
                        .font(Theme.body(15))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
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
    private let restColor = Color(red: 0.95, green: 0.60, blue: 0.10)

    var body: some View {
        ZStack {
            ring(progress: debt,        color: debtColor, size: 220)
            ring(progress: nap,         color: napColor,  size: 160)
            ring(progress: restorative, color: restColor, size: 100)
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
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
            // Filled progress.
            Circle()
                .trim(from: 0, to: animate ? CGFloat(min(max(progress, 0), 1)) : 0)
                .stroke(color,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
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
                    color: Color(red: 0.95, green: 0.60, blue: 0.10),
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
