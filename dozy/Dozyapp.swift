//
//  Dozyapp.swift
//  dozy
//
//  Created by Charvi Bansal on 6/6/26.
//
import SwiftUI

@main
struct DozyApp: App {
    @StateObject private var vm = SleepViewModel()
    @StateObject private var subscriptions = SubscriptionManager()
    // App-wide, so a running nap survives leaving the Nap screen.
    @StateObject private var napTimer = NapTimer()
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    init() {
        // Wire the watch responder to the view model.
        PhoneConnector.shared.activate()
        // Tab bar sits on the app's own background instead of a grey slab.
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Theme.background)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
        // Must be registered at every launch, including HealthKit's background ones.
        MorningBrief.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasOnboarded {
                    OnboardingFlow()
                } else if subscriptions.isLoading {
                    ZStack {
                        DozyBackground()
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                    .preferredColorScheme(.dark)
                } else if !subscriptions.isEntitled {
                    PaywallView()
                        .environmentObject(subscriptions)
                } else {
                    NavigationStack {
                        TabView {
                            SummaryView()
                                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                            SleepDebtView(title: "Progress", showsDetailRows: true)
                                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                            ProfileView()
                                .tabItem { Label("You", systemImage: "person.fill") }
                        }
                    }
                    .environmentObject(vm)
                    .environmentObject(napTimer)
                    .environmentObject(subscriptions)
                }
            }
            .preferredColorScheme(.dark)
            // Cyan, not system blue, for the selected tab, Back and links.
            .tint(Theme.cyan)
            .task {
                await subscriptions.start()
                MorningBrief.isEntitled = subscriptions.isEntitled
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in
                MorningBrief.cancelPending()
            }
            .onChange(of: subscriptions.isEntitled) { _, entitled in
                MorningBrief.isEntitled = entitled
                guard entitled else { return }
                PhoneConnector.shared.viewModel = vm
                Task {
                    await vm.load()
                    let napMin = Int((vm.napLength / 60).rounded())
                    let debtMin = Int((vm.totalDebt / 60).rounded())
                    PhoneConnector.shared.push(napMinutes: napMin, debtMinutes: debtMin)
                    // Health access exists now, so the sleep observer can start.
                    MorningBrief.startObserving()
                }
            }
        }
    }
}
