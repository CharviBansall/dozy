//
//  Howdozyworks.swift
//  dozy
//
//  A plain account of the maths behind the plan, so the numbers can be trusted.
//

import SwiftUI

struct HowDozyWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(title: "How Dozy Works", date: "About")

                step(icon: "moon.stars.fill", color: Theme.accentBlue,
                     title: "Your sleep need",
                     text: "Dozy looks at how long you slept on your longer nights over the last 30 days, because your average is already dragged down by short nights. Your need is never set below 7 hours or above 10. Until Dozy has five nights, it uses 8 hours.")

                step(icon: "flame.fill", color: Theme.debtRed,
                     title: "Your sleep debt",
                     text: "Dozy keeps a running balance over the last 14 days. A night shorter than your need adds the difference. A day with no recorded sleep is left out, not counted against you.")

                step(icon: "arrow.uturn.backward.circle.fill", color: Theme.cyan,
                     title: "Paying it back",
                     text: "Sleeping past your need pays back up to 60 minutes a night, and naps pay back up to 30 minutes a day. Sleep can’t be banked ahead of time, so the balance never goes below zero.")

                step(icon: "sun.max.fill", color: Theme.violet,
                     title: "Today’s one thing",
                     text: "If you owe 20 minutes or more and the afternoon is still open, Dozy asks for a nap between 1:00 and 3:30 PM. Otherwise it gives you tonight’s bedtime. It never asks for both.")

                step(icon: "bed.double.fill", color: Theme.accentBlue,
                     title: "Tonight’s bedtime",
                     text: "Dozy counts back from your wake time: your sleep need, plus up to an hour of payback, plus 15 minutes to fall asleep.")

                step(icon: "heart.fill", color: Theme.debtRed,
                     title: "Deep, REM and your heart",
                     text: "Deep and REM sleep are worked out by your watch or tracker, from your heart rate, movement and breathing. Dozy reads them as they are and compares them with your own usual. It also shows your sleeping heart rate, heart rate variability and breathing rate, so you can see the signals behind a good or a rough night.")

                Text("Dozy is a planning tool, not medical advice. If you are often exhausted despite sleeping enough, talk to a doctor.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func step(icon: String, color: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(icon: icon, title: title, color: color, showsChevron: false)
            Text(text)
                .font(Theme.body(15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .healthCard()
    }
}
