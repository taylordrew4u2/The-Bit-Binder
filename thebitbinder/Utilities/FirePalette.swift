//
//  FirePalette.swift
//  thebitbinder
//
//  Cohesive "fire" palette used when Roast Mode is on, aligned to the
//  Roast Mode v2 design spec. Standard mode stays on the system accent.
//

import SwiftUI

// MARK: - Fire Palette (active roast state)

enum FirePalette {
    // MARK: - Core accent colors

    static let core    = Color(red: 1.00, green: 0.416, blue: 0.208)  // #FF6A35  ember
    static let bright  = Color(red: 1.00, green: 0.698, blue: 0.247)  // #FFB23F  ember2
    static let ember   = Color(red: 1.00, green: 0.698, blue: 0.247)  // #FFB23F  (alias → bright)
    static let glow    = Color(red: 1.00, green: 0.86, blue: 0.48)    // #FFDB7A
    static let spark   = Color(red: 1.00, green: 0.92, blue: 0.64)    // #FFEBA3

    // MARK: - Surfaces

    static let bg      = Color(red: 0.043, green: 0.024, blue: 0.016) // #0B0604  near-black warm
    static let bg2     = Color(red: 0.078, green: 0.039, blue: 0.024) // #140A06
    static let card    = Color(red: 0.102, green: 0.059, blue: 0.039) // #1A0F0A
    static let ash     = Color(red: 0.043, green: 0.024, blue: 0.016) // #0B0604  (alias → bg)
    static let ashElev = Color(red: 0.102, green: 0.059, blue: 0.039) // #1A0F0A  (alias → card)

    // MARK: - Text & borders

    static let text    = Color(red: 0.961, green: 0.933, blue: 0.906) // #F5EEE7
    static let sub     = Color(red: 0.961, green: 0.933, blue: 0.906).opacity(0.55)
    static let edge    = Color(red: 1.0, green: 0.47, blue: 0.196).opacity(DS.Opacity.light)

    // MARK: - Gradients

    static let flame = LinearGradient(
        colors: [glow, ember, bright, core],
        startPoint: .top,
        endPoint: .bottom
    )

    static let flameHorizontal = LinearGradient(
        colors: [ember, bright, core],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let glowRadial = RadialGradient(
        colors: [core, bright, ember.opacity(0.35), .clear],
        center: .center,
        startRadius: 8,
        endRadius: 120
    )

    static let ambient = LinearGradient(
        colors: [card, bg, Color.black],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Ember CTA gradient (buttons, pills)

    static let emberCTA = LinearGradient(
        colors: [core, Color(red: 0.91, green: 0.27, blue: 0.12)],  // #E8451E
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Heat scale

    static func heat(_ value: Double) -> Color {
        let t = min(max(value, 0), 1)
        switch t {
        case 0..<0.30:   return Color(red: 0.35, green: 0.29, blue: 0.25) // ashy grey
        case 0.30..<0.60: return bright   // amber
        case 0.60..<0.85: return core     // orange-ember
        default:          return Color(red: 1.0, green: 0.18, blue: 0.0)  // #FF2E00
        }
    }

    static func heatGlow(_ value: Double) -> Color {
        if value < 0.60 { return .clear }
        if value < 0.85 { return core.opacity(0.33) }
        return core.opacity(DS.Opacity.heavy)
    }
}

// MARK: - Cold Palette (zero-subject / empty roast state)

enum ColdPalette {
    static let bg   = Color(red: 0.086, green: 0.071, blue: 0.063) // #161210
    static let card = Color(red: 0.122, green: 0.102, blue: 0.094) // #1F1A18
    static let edge = Color.white.opacity(DS.Opacity.subtle)
    static let text = Color(red: 0.788, green: 0.765, blue: 0.749) // #C9C3BF
    static let sub  = Color(red: 0.788, green: 0.765, blue: 0.749).opacity(0.5)
    static let grey = Color(red: 0.416, green: 0.392, blue: 0.376) // #6A6460
}

// MARK: - Convenience extensions

extension Color {
    static let fireCore = FirePalette.core
    static let fireEmber = FirePalette.ember
    static let fireGlow = FirePalette.glow
    static let fireAsh = FirePalette.ash
}

extension ShapeStyle where Self == LinearGradient {
    static var fireFlame:           LinearGradient { FirePalette.flame }
    static var fireFlameHorizontal: LinearGradient { FirePalette.flameHorizontal }
    static var fireAmbient:         LinearGradient { FirePalette.ambient }
}
