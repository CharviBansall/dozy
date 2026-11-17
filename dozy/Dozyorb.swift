//
//  Dozyorb.swift
//  dozy
//
//  Dozy's character: a dark glass orb with ribbons of light turning inside it.
//  How bright, fast and full it is follows sleep debt. Rested, the ribbons glow
//  and cross quickly; deep in debt, they fade, slow down and the orb shrinks.
//

import SwiftUI

struct DozyOrb: View {
    /// Current sleep debt in seconds. Zero is fully rested; 5 hours or more is depleted.
    var debt: TimeInterval
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 1 = rested, 0 = depleted.
    private var energy: Double {
        1 - min(max(debt / (5 * 3600), 0), 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            orb(time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Composition

    private func orb(time: TimeInterval) -> some View {
        let e = energy
        // The ribbons turn faster the more rested you are.
        let phase = time * (0.3 + 0.9 * e)
        // Breath: every ~5s rested, a slow ~7s sigh when depleted.
        let breath = sin(time * 2 * .pi / (7 - 2 * e))
        let scale = (0.84 + 0.16 * e) * (1 + (0.012 + 0.03 * e) * breath)
        let shimmer = sin(time * 2.3) * 0.5 + sin(time * 3.7 + 1.2) * 0.5

        return ZStack {
            glass
            ribbon(0, phase: phase, e: e)
            ribbon(1, phase: phase, e: e)
            ribbon(2, phase: phase, e: e)
            ribbon(3, phase: phase, e: e)
            core(e: e, shimmer: shimmer)
            gloss
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(rim(e: e))
        .scaleEffect(scale)
        .shadow(color: Color(red: 0.15, green: 0.55, blue: 1.0)
                    .opacity(0.12 + 0.5 * e + 0.08 * e * shimmer),
                radius: size * (0.08 + 0.26 * e))
    }

    /// The dark sphere the light moves inside.
    private var glass: some View {
        Circle().fill(
            RadialGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.26),
                                    Color(red: 0.02, green: 0.03, blue: 0.08)],
                           center: .center, startRadius: 0, endRadius: size * 0.55)
        )
    }

    /// One band of light. Four of them turn at different speeds and directions;
    /// where they cross, the additive blend makes the centre flare.
    private func ribbon(_ index: Int, phase: Double, e: Double) -> some View {
        let speeds: [Double] = [1.0, -0.75, 0.55, -1.3]
        let starts: [Double] = [0.0, 1.1, 2.4, 3.9]
        let colors: [Color] = [
            Color(red: 0.30, green: 0.90, blue: 0.95),   // cyan
            Color(red: 0.10, green: 0.45, blue: 1.00),   // blue
            Color(red: 0.55, green: 0.45, blue: 1.00),   // violet
            Color(red: 0.85, green: 0.95, blue: 1.00),   // near white
        ]
        let widths: [CGFloat] = [0.34, 0.30, 0.26, 0.12]

        let angle = phase * speeds[index] + starts[index]
        // Each band swells and thins as it turns, so it reads as a wave, not a spoke.
        let swell = 1 + 0.35 * sin(phase * 1.7 + starts[index] * 2)
        let strength = 0.2 + 0.7 * e
        let color = colors[index]

        return Ellipse()
            .fill(LinearGradient(colors: [.clear, color.opacity(strength), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: size * 1.05, height: size * widths[index] * swell)
            .rotationEffect(.radians(angle))
            .offset(x: cos(angle * 0.6) * size * 0.05, y: sin(angle * 0.8) * size * 0.05)
            .blur(radius: size * 0.06)
            .blendMode(.plusLighter)
    }

    /// The bright point where the ribbons meet.
    private func core(e: Double, shimmer: Double) -> some View {
        Circle()
            .fill(Color.white.opacity(0.08 + 0.45 * e + 0.08 * e * shimmer))
            .frame(width: size * 0.3, height: size * 0.3)
            .blur(radius: size * 0.11)
            .blendMode(.plusLighter)
    }

    /// A soft reflection near the top, so it reads as glass.
    private var gloss: some View {
        Ellipse()
            .fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size * 0.62, height: size * 0.36)
            .offset(y: -size * 0.27)
            .blur(radius: size * 0.04)
    }

    private func rim(e: Double) -> some View {
        Circle().strokeBorder(
            LinearGradient(colors: [Color.white.opacity(0.18 + 0.2 * e), Color.white.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: max(1, size * 0.012)
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        DozyOrb(debt: 0, size: 140)
        DozyOrb(debt: 2.5 * 3600, size: 140)
        DozyOrb(debt: 6 * 3600, size: 140)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.07, green: 0.07, blue: 0.09))
}
