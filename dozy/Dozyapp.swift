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
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    init() {
        // Wire the watch responder to the view model.
        PhoneConnector.shared.activate()
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
                                .tabItem { Label("Home", systemImage: "house.fill") }
                            NapWindowView()
                                .tabItem { Label("Nap", systemImage: "moon.fill") }
                            ProfileView()
                                .tabItem { Label("Profile", systemImage: "person.fill") }
                        }
                    }
                    .environmentObject(vm)
                    .environmentObject(subscriptions)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await subscriptions.start()
            }
            .onChange(of: subscriptions.isEntitled) { _, entitled in
                guard entitled else { return }
                PhoneConnector.shared.viewModel = vm
                Task {
                    await vm.load()
                    let napMin = Int((vm.napLength / 60).rounded())
                    let debtMin = Int((vm.totalDebt / 60).rounded())
                    PhoneConnector.shared.push(napMinutes: napMin, debtMinutes: debtMin)
                }
            }
        }
    }
}
