//
//  Watchnapview.swift
//  DozyWatch
//
//  Two pages, turned with the Digital Crown: today's one thing, then the nap timer.
//
import SwiftUI

struct WatchNapView: View {
    @StateObject private var connector = WatchConnector.shared
    @StateObject private var timer = WatchNapTimer()

    @State private var settled = false          // false = loading, true = content
    @State private var page = Page.today

    private enum Page { case today, nap }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if settled {
                TabView(selection: $page) {
                    todayPage.tag(Page.today)
                    napPage.tag(Page.nap)
                }
                .tabViewStyle(.verticalPage)
                .transition(.opacity)
            } else {
                LoadingBlob()
            }
        }
        .onAppear {
            timer.requestNotificationPermission()
            connector.refresh()
        }
        .onChange(of: connector.hasLoaded) { _, loaded in
            if loaded { settle() }
        }
    }

    private func settle() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
            settled = true
        }
    }

    // MARK: - Today

    private var todayPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: connector.action == "nap" ? "moon.zzz.fill" : "bed.double.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Today’s One Thing")
                    .font(Theme.body(13, weight: .semibold))
            }
            .foregroundStyle(Theme.cyan)

            if connector.hasPlan {
                Text(connector.headline)
                    .font(Theme.body(20, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Text(connector.detail)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)

                Spacer(minLength: 4)

                debtLine

                if connector.action == "nap" {
                    Button {
                        withAnimation { page = .nap }
                    } label: {
                        Text("Start Nap")
                            .font(Theme.body(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Theme.cyan)
                }
            } else {
                Text("Open Dozy on your iPhone")
                    .font(Theme.body(18, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Your plan appears here once Dozy has a night of sleep to work from.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var debtLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            let minutes = connector.debtMinutes
            if minutes < 1 {
                Text("No sleep debt")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            } else {
                if minutes >= 60 {
                    figure("\(minutes / 60)"); unit("hr")
                }
                if minutes % 60 != 0 || minutes < 60 {
                    figure("\(minutes % 60)"); unit("min")
                }
                Text("owed")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .padding(.leading, 2)
            }
        }
    }

    private func figure(_ text: String) -> some View {
        Text(text).font(Theme.number(22)).foregroundStyle(Theme.debtRed)
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(Theme.body(12, weight: .semibold)).foregroundStyle(Theme.secondary)
    }

    // MARK: - Nap timer

    private var napPage: some View {
        VStack(spacing: 6) {
            Text(timer.isRunning ? "Napping" : "Nap")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.text)

            Button {
                timer.toggle(minutes: connector.napMinutes)
            } label: {
                ZStack {
                    if timer.isRunning {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: timer.progress)
                            .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Circle()
                        .fill(LinearGradient(colors: [Theme.cyan, Theme.accentBlue],
                                             startPoint: .top, endPoint: .bottom))
                        .padding(10)

                    VStack(spacing: 1) {
                        if timer.isRunning {
                            Text(timer.remainingDisplay)
                                .font(Theme.number(22))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(connector.napMinutes)")
                                .font(Theme.number(28, weight: .bold))
                                .foregroundStyle(.white)
                            Text("min nap")
                                .font(Theme.body(11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 104, height: 104)

            Text(timer.isRunning ? "Tap to cancel" : "Tap to start")
                .font(Theme.body(12))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The breathing blue blob shown while the watch waits for the phone.
struct LoadingBlob: View {
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Theme.cyan, Theme.accentBlue],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 150, height: 150)
            .scaleEffect(breathing ? 1.06 : 0.9)
            .shadow(color: Theme.cyan.opacity(breathing ? 0.8 : 0.4),
                    radius: breathing ? 30 : 12)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

#Preview {
    WatchNapView()
}
