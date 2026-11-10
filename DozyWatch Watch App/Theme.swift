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

    /// Body alias — same serif, since we're going full editorial.
    static func body(_ size: CGFloat) -> Font {
        serif(size)
    }

    // MARK: - Palette
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let accentBlue = Color(red: 0.10, green: 0.50, blue: 1.0)
    static let cyan       = Color(red: 0.30, green: 0.80, blue: 0.85)
    static let orange     = Color(red: 0.95, green: 0.60, blue: 0.10)
    static let debtPink   = Color(red: 0.90, green: 0.25, blue: 0.45)
}

private extension Font {
    func italic(_ on: Bool) -> Font { on ? self.italic() : self }
}
