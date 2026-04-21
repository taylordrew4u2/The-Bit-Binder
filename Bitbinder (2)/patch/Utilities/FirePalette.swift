//
//  FirePalette.swift
//  thebitbinder
//
//  Cohesive "fire" palette used when Roast Mode is on. Standard mode
//  stays on the system accent (native iOS). Everything in Roast Mode
//  should pull its accent, tint, gradient, and glow from here so the
//  UI feels like a single heat-map rather than a mix of reds, oranges,
//  and yellows.
//
//  v2 — refined for the "Roast Mode as its own product" direction:
//  warmer base surface (ember-tinted near-black), amber-gold accents,
//  and stops tuned so gradients feel like a real flame instead of a
//  blood/warning red.
//

import SwiftUI

enum FirePalette {
    // MARK: - Core palette

    /// Core ember accent — deep burnt orange. Primary tint for Roast Mode.
    /// Reads as "hot coal" rather than "warning" — less saturated than the
    /// previous #FF4500 so it sits comfortably in navigation bars and
    /// primary buttons without shouting.
    static let core    = Color(red: 0.98, green: 0.42, blue: 0.20)   // #FA6B33

    /// Bright flame — mid-gradient accent. Use for selected states, chips,
    /// and the brighter stop when pushing `core` one notch toward light.
    static let bright  = Color(red: 1.00, green: 0.58, blue: 0.24)   // #FF933D

    /// Amber ember — the warm midtone. Use for secondary chips, inline
    /// badges, and the middle stop of a vertical flame gradient.
    static let ember   = Color(red: 1.00, green: 0.73, blue: 0.25)   // #FFBB40

    /// Pale ember glow — the lightest flame tone. Top of flame gradients,
    /// soft halos behind icons, quiet highlights on dark surfaces.
    static let glow    = Color(red: 1.00, green: 0.86, blue: 0.48)   // #FFDB7A

    /// Charred ash — the canonical deep roast-mode surface. Near-black
    /// with a red undertone so it pairs with the flame gradient without
    /// the jarring contrast of pure black.
    static let ash     = Color(red: 0.094, green: 0.055, blue: 0.043)  // #181009

    /// Ember-glow mid background — one stop lighter than `ash`. Use for
    /// cards and sheets in Roast Mode so surfaces have gentle depth.
    static let ashElev = Color(red: 0.14, green: 0.085, blue: 0.07)   // #241612

    /// Hot spark highlight — nearly pure yellow. Save for the hottest
    /// heat-meter tick, the unread badge, or the animated play button.
    static let spark   = Color(red: 1.00, green: 0.92, blue: 0.64)    // #FFEBA3

    // MARK: - Gradients

    /// Vertical flame gradient — pale ember glow at top, burning down
    /// into the core. The signature Roast Mode surface fill.
    static let flame = LinearGradient(
        colors: [glow, ember, bright, core],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Horizontal flame gradient — useful for progress bars and pill
    /// backgrounds where vertical drama would look wrong.
    static let flameHorizontal = LinearGradient(
        colors: [ember, bright, core],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Radial glow — hot core fading to a soft amber halo. Use behind
    /// animated icons or hero art.
    static let glowRadial = RadialGradient(
        colors: [core, bright, ember.opacity(0.35), .clear],
        center: .center,
        startRadius: 8,
        endRadius: 120
    )

    /// Ember-lit background — for full-screen Roast Mode canvases. A
    /// radial warm ambient light at the top + ash deepens to black at
    /// the bottom. Much better than a flat dark-mode gray.
    static let ambient = LinearGradient(
        colors: [ashElev, ash, Color.black],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Heat scale
    //
    // Map a 0…1 heat value to a palette stop. Used by HeatMeter and the
    // per-target roast frequency badge.
    static func heat(_ value: Double) -> Color {
        let t = min(max(value, 0), 1)
        switch t {
        case 0..<0.25:   return ember.opacity(0.55 + t * 0.8)
        case 0.25..<0.6: return bright
        case 0.6..<0.85: return core
        default:         return spark
        }
    }
}

// MARK: - Convenience extensions

extension Color {
    /// The primary roast-mode accent (core ember). Prefer this over
    /// hard-coded `.red` or `.orange`.
    static let fireCore = FirePalette.core

    /// Ember midtone — equivalent to a warm amber. Good for inline chip
    /// backgrounds in Roast Mode.
    static let fireEmber = FirePalette.ember

    /// Pale glow — top of the flame.
    static let fireGlow = FirePalette.glow

    /// The deep charred-ash surface tone for Roast Mode canvases.
    static let fireAsh = FirePalette.ash
}

extension ShapeStyle where Self == LinearGradient {
    static var fireFlame:           LinearGradient { FirePalette.flame }
    static var fireFlameHorizontal: LinearGradient { FirePalette.flameHorizontal }
    static var fireAmbient:         LinearGradient { FirePalette.ambient }
}
