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
    /// The app's main accent color. Returns red when Roast Mode is enabled,
    /// otherwise the system blue tint. Reads the same `@AppStorage` key as
    /// the global tint in `thebitbinderApp`, so it stays in sync automatically.
    static var bitbinderAccent: Color {
        UserDefaults.standard.bool(forKey: "roastModeEnabled") ? .red : .blue
    }
}

/// A view modifier that applies the Roast-Mode-aware tint. Useful when you
/// want a subtree to get the accent color explicitly (e.g. overlays that
/// don't inherit the environment tint).
struct RoastModeTint: ViewModifier {
    @AppStorage("roastModeEnabled") private var roastMode: Bool = false

    func body(content: Content) -> some View {
        content.tint(roastMode ? .red : .blue)
    }
}

extension View {
    /// Apply the Roast-Mode-aware tint to any view subtree.
    func roastModeTint() -> some View {
        modifier(RoastModeTint())
    }
}
