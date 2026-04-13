//
//  ColorExtensions.swift
//  thebitbinder
//
//  Lightweight Color utilities for native iOS design.
//  App palette: System Blue (accentColor) + White only.
//  Roast mode uses orange as its accent.
//

import SwiftUI

// MARK: - Color Hex Initializer

extension Color {
    /// Creates a Color from a hex string (e.g. "FF9500" or "#FF9500").
    /// Returns nil if the hex string is invalid.
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}