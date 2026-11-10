//
//  Watchnapview.swift
//  dozy
//
//  Created by Charvi Bansal on 6/10/26.
//
import SwiftUI

struct WatchNapView: View {
    @StateObject private var connector = WatchConnector.shared
    @StateObject private var timer = WatchNapTimer()

    @State private var settled = false          // false = loading, true = nap view
    @Namespace private var blobSpace
    private let accent = Color(red: 0.30, green: 0.80, blue: 0.85)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if settled {
                napContent
                    .transition(.opacity)
            } else {
                LoadingBlob(namespace: blobSpace)
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
        // Blob rises + shrinks into place, then the UI fades in.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
            settled = true
        }
    }

    // MARK: - The settled nap view

    private var napContent: some View {
        VStack(spacing: 8) {
            if timer.isRunning {
                Text("Napping")
                    .font(Theme.body(15))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Text("Dozy")
                    .font(Theme.serif(22))
                    .foregroundStyle(.white)
            }

            Button {
                timer.toggle(minutes: connector.napMinutes)
            } label: {
                ZStack {
                    if timer.isRunning {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: timer.progress)
                            .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    // Same blob, matched from the loading screen so it travels here.
                    Circle()
                        .fill(LinearGradient(
                            colors: [accent, Color(red: 0.04, green: 0.36, blue: 0.98)],
                            startPoint: .top, endPoint: .bottom))
                        .matchedGeometryEffect(id: "blob", in: blobSpace)
                        .padding(10)

                    VStack(spacing: 1) {
                        if timer.isRunning {
                            Text(timer.remainingDisplay)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(connector.napMinutes)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("min nap")
                                .font(Theme.body(11))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 110, height: 110)

            Text(timer.isRunning ? "Tap to cancel" : "Tap to start")
                .font(Theme.body(12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding()
    }
}

/// Large pulsating blob shown while loading. Uses the matched "blob" id so it
/// animates up into the nap view's smaller orb when loading completes.
struct LoadingBlob: View {
    let namespace: Namespace.ID
    @State private var breathing = false
    private let accent = Color(red: 0.30, green: 0.80, blue: 0.85)

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [accent, Color(red: 0.04, green: 0.36, blue: 0.98)],
                startPoint: .top, endPoint: .bottom))
            .matchedGeometryEffect(id: "blob", in: namespace)
            .frame(width: 150, height: 150)
            .scaleEffect(breathing ? 1.06 : 0.9)
            .shadow(color: accent.opacity(breathing ? 0.8 : 0.4),
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
