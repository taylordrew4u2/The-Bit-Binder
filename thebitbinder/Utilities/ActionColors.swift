import SwiftUI

/// Opaque fills reserved for controls with white labels. Brand accents remain
/// separate so links, decoration, and system-tinted controls keep their identity.
/// Explicit sRGB values keep the label contrast in light, dark, and increased
/// contrast appearances (blue 7.40:1; ember 5.75:1 against white).
enum ActionColors {
    static let blue = Color(.sRGB, red: 0 / 255, green: 80 / 255, blue: 184 / 255, opacity: 1)
    static let ember = Color(.sRGB, red: 184 / 255, green: 58 / 255, blue: 18 / 255, opacity: 1)
    static let foreground = Color.white
}
