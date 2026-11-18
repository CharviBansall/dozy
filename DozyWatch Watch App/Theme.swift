//
//  Theme.swift
//  DozyWatch
//
//  The watch follows the phone: system type, rounded numbers, Dozy's palette.
//

import SwiftUI

enum Theme {

    /// Titles and labels.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Large titles. Kept under its old name for existing call sites.
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Figures: times and durations.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    // MARK: - Palette (the phone's dark-mode values)
    static let background = Color.black
    static let card       = Color(red: 0.125, green: 0.125, blue: 0.15)
    static let text       = Color(red: 0.96, green: 0.96, blue: 0.98)
    static let secondary  = Color(red: 0.60, green: 0.60, blue: 0.65)
    static let cyan       = Color(red: 0.30, green: 0.80, blue: 0.85)
    static let accentBlue = Color(red: 0.25, green: 0.58, blue: 1.00)
    static let violet     = Color(red: 0.62, green: 0.53, blue: 0.98)
    static let debtRed    = Color(red: 1.00, green: 0.27, blue: 0.23)
}
