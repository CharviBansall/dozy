//
//  Theme.swift
//  dozy
//
//  Created by Charvi Bansal on 6/12/26.
//
import SwiftUI
import UIKit

/// Dozy's look: the layout language of Apple's Health app (grouped background,
/// cards, bold system titles, rounded numbers) in Dozy's own palette.
/// Every colour here adapts to light and dark.
enum Theme {

    // MARK: - Type

    /// Titles and headings. Named `serif` for history: Dozy used Instrument Serif
    /// before moving to the system font. Large sizes are bold, smaller ones semibold.
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .system(size: size, weight: size >= 26 ? .bold : .semibold)
    }

    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        serif(size, italic: italic)
    }

    /// Dozy's original display face, Instrument Serif. Used for the big lines in
    /// onboarding and on the paywall; the app itself uses the system font.
    static func brand(_ size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        // Fallback when the font files aren't bundled.
        let fallback = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? fallback.italic() : fallback
    }

    /// Body, captions and labels.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Figures: durations, percentages, clock times.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Palette
    //
    // Mostly neutral: the background and the cards carry the screen. Colour is
    // kept to one family (cyan, blue, violet) plus a single warm colour, pink,
    // which always means debt or something going wrong. In light mode each
    // colour is a little deeper so it stays readable on white.

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> UIColor {
        UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    static let backgroundUI = dynamic(light: (0.949, 0.949, 0.969), dark: (0.07, 0.07, 0.09))
    static let cardUI       = dynamic(light: (1, 1, 1),             dark: (0.125, 0.125, 0.15))

    /// The page behind the cards.
    static let background = Color(backgroundUI)
    /// Cards and grouped rows.
    static let card       = Color(cardUI)
    /// Primary text.
    static let text       = Color(dynamic(light: (0.11, 0.11, 0.12), dark: (0.96, 0.96, 0.98)))
    /// Secondary text, captions, neutral icons.
    static let secondary  = Color(dynamic(light: (0.43, 0.43, 0.45), dark: (0.60, 0.60, 0.65)))
    /// Hairlines and chart grid.
    static let line       = Color(dynamic(light: (0.90, 0.90, 0.92), dark: (0.20, 0.20, 0.24)))
    /// Empty tracks, unselected bars, pressed and inset surfaces.
    static let track      = Color(dynamic(light: (0.90, 0.90, 0.92), dark: (0.20, 0.20, 0.24)))

    /// The accent: actions, good news, the current selection.
    static let cyan       = Color(dynamic(light: (0.04, 0.55, 0.63), dark: (0.30, 0.80, 0.85)))
    /// Buttons and the second data colour.
    static let accentBlue = Color(dynamic(light: (0.05, 0.42, 0.95), dark: (0.25, 0.58, 1.00)))
    /// The third data colour: deep + REM.
    static let violet     = Color(dynamic(light: (0.45, 0.35, 0.90), dark: (0.62, 0.53, 0.98)))
    /// Debt, shortfalls and errors: the red of the heart in Apple Health.
    static let debtRed    = Color(dynamic(light: (1.00, 0.23, 0.19), dark: (1.00, 0.27, 0.23)))
    /// Icons that are only labels, not states.
    static let iconNeutral = secondary
}

extension View {
    /// The standard Dozy card: padded, full width, rounded.
    func healthCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// The top row of a card: coloured icon and label, optional time, optional chevron.
struct CardHeader: View {
    let icon: String
    let title: String
    let color: Color
    var trailing: String = ""
    var showsChevron = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(Theme.body(15, weight: .semibold))
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .foregroundStyle(color)
    }
}

/// A duration the way Health writes it: big rounded figures, small units ("1 hr 10 min").
struct DurationText: View {
    let seconds: TimeInterval
    var size: CGFloat = 28
    var color: Color = Theme.text

    var body: some View {
        let minutes = Int((seconds / 60).rounded())
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if minutes >= 60 {
                figure("\(minutes / 60)")
                unit("hr")
                if minutes % 60 != 0 {
                    figure("\(minutes % 60)")
                    unit("min")
                }
            } else {
                figure("\(minutes)")
                unit("min")
            }
        }
    }

    private func figure(_ text: String) -> some View {
        Text(text).font(Theme.number(size)).foregroundStyle(color)
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(Theme.body(size * 0.54, weight: .semibold)).foregroundStyle(Theme.secondary)
    }
}
