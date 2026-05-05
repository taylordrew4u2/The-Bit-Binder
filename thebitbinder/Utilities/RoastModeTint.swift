//
//  RoastModeTint.swift
//  thebitbinder
//
//  App-wide helper for switching "blue" colors to red when Roast Mode is on.
//  Use `.bitbinderAccent` anywhere you would previously hard-code `Color.blue`
//  so the UI follows the Roast Mode toggle consistently.
//

import SwiftUI

extension Color {
    /// The app's main accent color. Returns the fire-palette core
    /// (OrangeRed) when Roast Mode is enabled, otherwise the system blue
    /// tint so the rest of the app stays on native iOS conventions.
    /// Reads the same `@AppStorage` key as the global tint in
    /// `thebitbinderApp`, so it stays in sync automatically.
    static var bitbinderAccent: Color {
        UserDefaults.standard.bool(forKey: "roastModeEnabled") ? FirePalette.core : .accentColor
    }
}

/// A view modifier that applies the Roast-Mode-aware tint. Useful when you
/// want a subtree to get the accent color explicitly (e.g. overlays that
/// don't inherit the environment tint).
struct RoastModeTint: ViewModifier {
    @AppStorage("roastModeEnabled") private var roastMode: Bool = false

    func body(content: Content) -> some View {
        content.tint(roastMode ? FirePalette.core : .accentColor)
    }
}

extension View {
    /// Apply the Roast-Mode-aware tint to any view subtree.
    func roastModeTint() -> some View {
        modifier(RoastModeTint())
    }

    /// Themes a SwiftUI Form/List into the Roast Mode v2 fire palette: dark
    /// bg, ember accent tint, fire text. Apply on the outermost container of
    /// any sheet that should match the roast list surface.
    func roastFormTheme() -> some View {
        modifier(RoastFormTheme())
    }
}

/// Pulls a Form/List into the fire palette so add/edit sheets feel like
/// they belong to Roast Mode rather than dropping back to native Form chrome.
struct RoastFormTheme: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(FirePalette.bg.ignoresSafeArea())
            .tint(FirePalette.core)
            .foregroundColor(FirePalette.text)
            .preferredColorScheme(.dark)
    }
}

/// Convenience for individual rows: paints the row bg with the fire card.
struct RoastRowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.listRowBackground(FirePalette.card)
    }
}

extension View {
    /// Apply Roast Mode card row background to a Form section row.
    func roastRowBackground() -> some View {
        modifier(RoastRowBackground())
    }
}
