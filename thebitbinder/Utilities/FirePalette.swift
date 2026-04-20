//
//  FirePalette.swift
//  thebitbinder
//
//  Cohesive "fire" color palette used when Roast Mode is enabled.
//  Standard mode stays on the system accent (native iOS). Everything
//  in Roast Mode should pull its accent, tint, gradient, and glow from
//  here so the UI feels like a single heat-map instead of a mix of red,
//  orange, and yellow.
//

import SwiftUI

/// Warm "fire" palette for Roast Mode. Ordered from coolest (core red-orange)
/// through the bright flame to the pale ember glow, plus a deep ash tone for
/// surfaces that need a dark roast-mode background.
enum FirePalette {
    /// OrangeRed — the primary accent. This replaces `.red` / `.blue` as the
    /// app-wide tint whenever Roast Mode is on. Bright enough for buttons,
    /// deep enough to read as "fire" instead of "warning".
    static let core    = Color(red: 1.00, green: 0.27, blue: 0.00)   // #FF4500

    /// Bright flame — mid-gradient accent. Use for hover/selected states,
    /// highlighted chips, or when `core` needs to be pushed one step toward
    /// the light end.
    static let bright  = Color(red: 1.00, green: 0.42, blue: 0.10)   // #FF6B1A

    /// Amber ember — warm midtone. Use for secondary chips, inline
    /// highlights, and the middle stop of a fire gradient.
    static let ember   = Color(red: 1.00, green: 0.72, blue: 0.00)   // #FFB800

    /// Pale ember glow — the lightest flame tone. Use for the top of a
    /// vertical flame gradient, soft glow halos, and quiet highlights on
    /// dark surfaces.
    static let glow    = Color(red: 1.00, green: 0.85, blue: 0.40)   // #FFD966

    /// Deep charred ash — near-black with a red undertone. Use sparingly
    /// for surfaces that need to feel like they've been sitting next to a
    /// fire (e.g. roast-mode section headers in dark appearance).
    static let ash     = Color(red: 0.10, green: 0.04, blue: 0.02)   // #1A0A04

    // MARK: - Gradients

    /// Vertical flame gradient — pale ember glow at top burning down into
    /// the core red-orange. The signature Roast Mode surface fill.
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

    /// Radial glow — a hot core fading to a soft amber halo. Use behind
    /// animated icons or as a backdrop for hero art.
    static let glowRadial = RadialGradient(
        colors: [core, bright, ember.opacity(0.35), .clear],
        center: .center,
        startRadius: 8,
        endRadius: 120
    )
}

// MARK: - Convenience extensions

extension Color {
    /// The primary roast-mode accent (core red-orange). Prefer this over
    /// hard-coded `.red` or `.orange` anywhere roast-mode UI lives.
    static let fireCore = FirePalette.core

    /// Ember midtone — equivalent to a warm amber. Good for inline chip
    /// backgrounds in Roast Mode.
    static let fireEmber = FirePalette.ember

    /// Pale glow — top of the flame.
    static let fireGlow = FirePalette.glow
}

extension ShapeStyle where Self == LinearGradient {
    /// Vertical flame gradient (glow → ember → bright → core).
    static var fireFlame: LinearGradient { FirePalette.flame }

    /// Horizontal flame gradient (ember → bright → core).
    static var fireFlameHorizontal: LinearGradient { FirePalette.flameHorizontal }
}
