//
//  DesignSystem.swift
//  thebitbinder
//
//  Canonical design tokens for spacing, corner radii, opacities, shadows,
//  and semantic colors. Views should reference these instead of hardcoding
//  magic numbers so the app looks consistent everywhere.
//

import SwiftUI

// MARK: - Spacing

enum AppTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        }
    }
}

enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    enum Corner {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    enum Opacity {
        static let subtle: Double = 0.06
        static let light: Double = 0.12
        static let medium: Double = 0.2
        static let scrim: Double = 0.4
        static let heavy: Double = 0.65
    }
}

// MARK: - Semantic Colors

extension Color {
    static var recording: Color { .red }

    static var destructive: Color { .red }

    static var success: Color { .green }

    static var warning: Color { .orange }

    static var scrim: Color { Color.black.opacity(DS.Opacity.scrim) }
}

// MARK: - Shadow

struct DSShadow: ViewModifier {
    enum Level { case light, medium, heavy }
    let level: Level

    func body(content: Content) -> some View {
        switch level {
        case .light:
            content.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        case .medium:
            content.shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        case .heavy:
            content.shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 6)
        }
    }
}

extension View {
    func dsShadow(_ level: DSShadow.Level = .medium) -> some View {
        modifier(DSShadow(level: level))
    }
}

// MARK: - Card Background

struct DSCard: ViewModifier {
    var cornerRadius: CGFloat = DS.Corner.md

    func body(content: Content) -> some View {
        content
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func dsCard(cornerRadius: CGFloat = DS.Corner.md) -> some View {
        modifier(DSCard(cornerRadius: cornerRadius))
    }
}
