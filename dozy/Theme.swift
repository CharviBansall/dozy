//
//  Theme.swift
//  dozy
//
//  Created by Charvi Bansal on 6/12/26.
//
import SwiftUI

/// Centralized typography + color for Dozy's full editorial look.
/// Instrument Serif is used throughout; its italic carries accent words.
///
/// NOTE: the names below must match the PostScript names printed by the
/// font-dump snippet. Adjust `serifRegular` / `serifItalic` if your console
/// shows different strings.
enum Theme {

    private enum FontName {
        static let serifRegular = "InstrumentSerif-Regular"
        static let serifItalic  = "InstrumentSerif-Italic"
    }

    /// The one type style for everything: Instrument Serif.
    /// `italic: true` uses the italic cut (for accent words).
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? FontName.serifItalic : FontName.serifRegular
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        // Fallback before the font is bundled, so the app still renders.
        return .system(size: size, weight: .regular, design: .serif).italic(italic)
    }

    /// Alias kept so existing call sites that say `display` still work.
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        serif(size, italic: italic)
    }

    /// Body / small text — uses the system font for readability at small sizes.
    /// Instrument Serif is a display face and gets hard to read below ~16px,
    /// so captions, labels, and detail lines use the clean system font.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Palette
    //
    // Mostly neutral: the dark background and the grey cards carry the screen.
    // Colour is kept to one family (cyan, blue, violet, all neighbours on the
    // colour wheel) plus a single warm colour, pink, which always means debt or
    // something going wrong. Icons stay neutral unless they show a state.
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    /// The accent: actions, good news, the current selection.
    static let cyan       = Color(red: 0.30, green: 0.80, blue: 0.85)
    /// Buttons and the second data colour.
    static let accentBlue = Color(red: 0.10, green: 0.50, blue: 1.0)
    /// The third data colour: deep + REM.
    static let violet     = Color(red: 0.55, green: 0.45, blue: 0.95)
    /// Debt, shortfalls and errors. The only warm colour in the app.
    static let debtPink   = Color(red: 0.90, green: 0.25, blue: 0.45)
    /// Icons that are only labels, not states.
    static let iconNeutral = Color.white.opacity(0.7)
}

private extension Font {
    func italic(_ on: Bool) -> Font { on ? self.italic() : self }
}
