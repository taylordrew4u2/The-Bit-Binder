//
//  NativeDesignSystem.swift
//  thebitbinder
//
//  Native iOS Design System
//  Following Apple Human Interface Guidelines for a polished, system-native feel.
//  Uses semantic system colors, standard typography, and iOS conventions.
//

import SwiftUI

// MARK: - Native Design System

/// Centralized design tokens following Apple HIG.
/// Uses system colors and semantic values for automatic light/dark mode support.
enum NativeTheme {
    
    // MARK: - Colors (Semantic System Colors)
    
    enum Colors {
        // Primary brand - use sparingly, tint color only
        static let tint = Color.accentColor
        
        // Text hierarchy - auto-adapts to light/dark mode
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(UIColor.tertiaryLabel)
        static let textPlaceholder = Color(UIColor.placeholderText)
        
        // Backgrounds - semantic, auto-adapting
        static let backgroundPrimary = Color(UIColor.systemBackground)
        static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
        static let backgroundGrouped = Color(UIColor.systemGroupedBackground)
        static let backgroundGroupedSecondary = Color(UIColor.secondarySystemGroupedBackground)
        
        // Separators
        static let separator = Color(UIColor.separator)
        static let separatorOpaque = Color(UIColor.opaqueSeparator)
        
        // Fills - for controls and surfaces
        static let fillPrimary = Color(UIColor.systemFill)
        static let fillSecondary = Color(UIColor.secondarySystemFill)
        static let fillTertiary = Color(UIColor.tertiarySystemFill)
        static let fillQuaternary = Color(UIColor.quaternarySystemFill)
        
        // Semantic states
        static let success = Color.green
        static let warning = Color.orange
        static let destructive = Color.red
        static let info = Color.blue
        
        // Special - "The Hits" gold (restrained)
        static let gold = Color.yellow.opacity(0.85)
    }
    
    // MARK: - Typography (System Text Styles)
    
    enum Typography {
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let title2 = Font.title2
        static let title3 = Font.title3
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
    }
    
    // MARK: - Spacing (iOS 8pt Grid)
    
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        
        // Standard iOS insets
        static let listRowInset: CGFloat = 16
        static let cardPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
    }
    
    // MARK: - Corner Radius (iOS Standard)
    
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 12
        static let card: CGFloat = 10
        static let button: CGFloat = 10
        static let sheet: CGFloat = 10
    }
}

// MARK: - Native List Row

/// A standard iOS-style list row with consistent styling.
struct NativeListRow<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.vertical, NativeTheme.Spacing.sm)
    }
}

// MARK: - Native Section Header

/// Standard iOS section header for grouped lists.
struct NativeSectionHeader: View {
    let title: String
    var trailing: String? = nil
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.footnote)
                .foregroundColor(NativeTheme.Colors.textSecondary)
            
            Spacer()
            
            if let trailing = trailing {
                Text(trailing)
                    .font(.footnote)
                    .foregroundColor(NativeTheme.Colors.textTertiary)
            }
        }
    }
}

// MARK: - Native Empty State

/// Apple-style empty state view.
struct NativeEmptyState: View {
    let symbol: String
    let title: String
    let description: String
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil
    
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        } actions: {
            if let buttonTitle = buttonTitle, let action = buttonAction {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Native Card

/// A simple elevated card matching iOS styling.
struct NativeCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(NativeTheme.Spacing.cardPadding)
            .background(NativeTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NativeTheme.Radius.card, style: .continuous))
    }
}

// MARK: - Native Badge

/// Small inline badge for status indicators.
struct NativeBadge: View {
    let text: String
    var variant: Variant = .neutral
    
    enum Variant {
        case neutral, success, warning, destructive, accent
        
        var color: Color {
            switch self {
            case .neutral: return NativeTheme.Colors.fillSecondary
            case .success: return Color.green.opacity(0.15)
            case .warning: return Color.orange.opacity(0.15)
            case .destructive: return Color.red.opacity(0.15)
            case .accent: return Color.accentColor.opacity(0.15)
            }
        }
        
        var textColor: Color {
            switch self {
            case .neutral: return NativeTheme.Colors.textSecondary
            case .success: return .green
            case .warning: return .orange
            case .destructive: return .red
            case .accent: return .accentColor
            }
        }
    }
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(variant.textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(variant.color, in: Capsule())
    }
}

// MARK: - Native Chip/Filter Button

/// Filter chip for horizontal scrolling selections.
struct NativeFilterChip: View {
    let title: String
    let isSelected: Bool
    var icon: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : NativeTheme.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(NativeTheme.Colors.fillSecondary)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Modifiers

extension View {
    /// Standard grouped list background
    func nativeGroupedBackground() -> some View {
        self.background(NativeTheme.Colors.backgroundGrouped)
    }
    
    /// Standard iOS card styling
    func nativeCardStyle() -> some View {
        self
            .background(NativeTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NativeTheme.Radius.card, style: .continuous))
    }
    
    /// Subtle shadow for elevated elements
    func nativeShadow() -> some View {
        self.shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

// MARK: - Standard iOS Tab Bar View

/// Standard iOS TabView wrapper with proper styling
struct NativeTabView<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .tint(.accentColor)
    }
}

// MARK: - Haptic Feedback (Simplified)

enum HapticType {
    case light, medium, heavy, success, warning, error, selection
}

func haptic(_ type: HapticType) {
    switch type {
    case .light:
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .medium:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .heavy:
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .success:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .warning:
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .error:
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .selection:
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Preview

#Preview("Native Components") {
    NavigationStack {
        List {
            Section {
                NativeListRow {
                    HStack {
                        Text("Standard Row")
                        Spacer()
                        NativeBadge(text: "New", variant: .accent)
                    }
                }
                
                NativeListRow {
                    HStack {
                        Text("With Chevron")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(NativeTheme.Colors.textTertiary)
                    }
                }
            } header: {
                NativeSectionHeader(title: "Examples")
            }
            
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        NativeFilterChip(title: "All", isSelected: true, action: {})
                        NativeFilterChip(title: "Recent", isSelected: false, action: {})
                        NativeFilterChip(title: "Favorites", isSelected: false, icon: "star.fill", action: {})
                    }
                    .padding(.horizontal)
                }
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Native Design")
    }
}
