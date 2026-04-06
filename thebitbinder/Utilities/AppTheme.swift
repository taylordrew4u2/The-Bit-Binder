//
//  AppTheme.swift
//  thebitbinder
//
//  Legacy design system - maintained for backward compatibility.
//  New code should prefer NativeTheme for iOS-native styling.
//

import SwiftUI

// MARK: - App Theme (Legacy Compatibility)

struct AppTheme {

    // MARK: - Colors
    struct Colors {
        // Primary action - uses system accent for native feel
        static let primaryAction = Color.accentColor
        static let primaryActionDeep = Color.accentColor.opacity(0.8)
        static let primaryActionLight = Color.accentColor.opacity(0.6)
        
        // Legacy brand aliases
        static let brand = primaryAction
        static let brandDeep = primaryActionDeep
        static let brandLight = primaryActionLight

        // Ink colors - using semantic colors
        static let inkBlack = Color.primary
        static let inkBlue = Color.accentColor
        static let inkRed = Color.red

        // Paper colors - mapped to system backgrounds
        static let paperCream = Color(UIColor.systemBackground)
        static let paperAged = Color(UIColor.secondarySystemBackground)
        static let paperDeep = Color(UIColor.tertiarySystemBackground)
        static let paperLine = Color(UIColor.separator)
        static let marginRed = Color.red.opacity(0.15)
        static let coffeeStain = Color.brown.opacity(0.04)

        // Surfaces
        static let surface = Color(UIColor.systemBackground)
        static let surfaceElevated = Color(UIColor.secondarySystemBackground)
        static let surfaceTertiary = Color(UIColor.tertiarySystemBackground)
        static let divider = Color(UIColor.separator)

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(UIColor.tertiaryLabel)

        // Semantic
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue
        
        // The Hits (gold/star)
        static let hitsGold = Color.yellow
        static let hitsGoldLight = Color.yellow.opacity(0.7)

        // Section accents - simplified
        static let notepadAccent = Color.accentColor
        static let brainstormAccent = Color.yellow
        static let jokesAccent = Color.accentColor
        static let setsAccent = Color.accentColor
        static let recordingsAccent = Color.red
        static let notebookAccent = Color.brown
        static let settingsAccent = Color.gray
        static let aiAccent = Color.accentColor
        static let roastAccent = Color.orange

        // Roast mode surfaces
        static let roastBackground = Color(UIColor.systemBackground)
        static let roastSurface = Color(UIColor.secondarySystemBackground)
        static let roastCard = Color(UIColor.tertiarySystemBackground)
        static let roastLine = Color.orange.opacity(0.15)

        static let roastHeaderGradient = LinearGradient(
            colors: [Color.orange.opacity(0.2), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
        static let roastEmberGradient = LinearGradient(
            colors: [Color.orange.opacity(0.9), Color.orange],
            startPoint: .top, endPoint: .bottom
        )

        // Gradients - simplified
        static let brandGradient = LinearGradient(colors: [.accentColor, .accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom)
        static let surfaceGradient = LinearGradient(colors: [Color(UIColor.systemBackground), Color(UIColor.secondarySystemBackground)], startPoint: .top, endPoint: .bottom)
        static let heroGradient = surfaceGradient
        static let leatherGradient = LinearGradient(
            colors: [Color.brown.opacity(0.3), Color.brown.opacity(0.2)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Typography (Use system text styles)
    struct Typography {
        static let display = Font.largeTitle
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let title3 = Font.title3
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let scrawl = Font.title.weight(.heavy)
    }

    // MARK: - Spacing (8-pt grid)
    struct Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radius (iOS standard)
    struct Radius {
        static let xs: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let xl: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: - Shadows (Restrained)
    struct Shadows {
        static let sm = (color: Color.black.opacity(0.04), radius: CGFloat(2), x: CGFloat(0), y: CGFloat(1))
        static let md = (color: Color.black.opacity(0.08), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let lg = (color: Color.black.opacity(0.12), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let inner = (color: Color.black.opacity(0.04), radius: CGFloat(2), x: CGFloat(1), y: CGFloat(0))
    }
}

// MARK: - Extensions

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        
        guard scanner.scanHexInt64(&rgb) else { return nil }
        
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Legacy Button Styles (for backward compatibility)

extension View {
    func touchReactive(scale: CGFloat = 0.98, haptic: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        self.buttonStyle(.plain)
    }

    func cardPress() -> some View {
        self.buttonStyle(.plain)
    }

    func heavyPress() -> some View {
        self.buttonStyle(.plain)
    }
}

struct TouchReactiveStyle: ButtonStyle {
    let pressedScale: CGFloat
    let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct MenuItemStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct ChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Cross-platform helpers

func dismissKeyboard() {
#if !targetEnvironment(macCatalyst)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
}

func openURL(_ url: URL) {
    UIApplication.shared.open(url)
}