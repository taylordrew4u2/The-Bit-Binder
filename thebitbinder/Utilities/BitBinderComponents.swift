//
//  BitBinderComponents.swift
//  thebitbinder
//
//  Shared UI components following native iOS design patterns.
//

import SwiftUI

// MARK: - Empty State Component (using ContentUnavailableView pattern)

struct BitBinderEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var roastMode: Bool = false
    var iconGradient: LinearGradient? = nil
    
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(subtitle)
        } actions: {
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(roastMode ? .orange : .accentColor)
            }
        }
    }
}

// MARK: - Chip Component

struct BitBinderChip: View {
    let text: String
    var icon: String? = nil
    var isSelected: Bool = false
    var style: ChipVariant = .filter
    var roastMode: Bool = false
    var action: (() -> Void)? = nil
    
    enum ChipVariant {
        case filter, tag, status
    }
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    chipContent
                }
                .buttonStyle(.plain)
            } else {
                chipContent
            }
        }
    }
    
    private var chipContent: some View {
        HStack(spacing: 4) {
            if let icon = icon, isSelected || style != .filter {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }
            Text(text)
                .font(style == .tag ? .caption : .subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, style == .tag ? 8 : 14)
        .padding(.vertical, style == .tag ? 4 : 8)
        .background(backgroundColor, in: Capsule())
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return roastMode ? .orange : .accentColor
        }
        switch style {
        case .filter: return NativeTheme.Colors.fillSecondary
        case .tag: return Color.accentColor.opacity(0.12)
        case .status: return Color.green.opacity(0.12)
        }
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        }
        switch style {
        case .filter: return .primary
        case .tag: return .accentColor
        case .status: return .green
        }
    }
}

// MARK: - Badge Component

struct BitBinderBadge: View {
    let text: String
    var icon: String? = nil
    var variant: BadgeVariant = .neutral
    var size: BadgeSize = .small
    var roastMode: Bool = false
    
    enum BadgeVariant {
        case neutral, success, warning, error, gold, info
        
        var backgroundColor: Color {
            switch self {
            case .neutral: return NativeTheme.Colors.fillSecondary
            case .success: return Color.green.opacity(0.12)
            case .warning: return Color.orange.opacity(0.12)
            case .error: return Color.red.opacity(0.12)
            case .gold: return Color.yellow.opacity(0.15)
            case .info: return Color.blue.opacity(0.12)
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .neutral: return .secondary
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .gold: return .yellow
            case .info: return .blue
            }
        }
    }
    
    enum BadgeSize {
        case small, medium
        
        var font: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(size.font.weight(.semibold))
            }
            Text(text)
                .font(size.font.weight(.medium))
        }
        .foregroundColor(variant.foregroundColor)
        .padding(.horizontal, size == .small ? 6 : 8)
        .padding(.vertical, size == .small ? 3 : 4)
        .background(variant.backgroundColor, in: Capsule())
    }
}

// MARK: - Card Container

struct BitBinderCard<Content: View>: View {
    var roastMode: Bool = false
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .background(NativeTheme.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Section Header

struct BitBinderSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    var roastMode: Bool = false
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(NativeTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            if let trailing = trailing {
                trailing
            }
        }
    }
}

// MARK: - Hit Star Badge

struct HitStarBadge: View {
    var size: CGFloat = 16
    var showBackground: Bool = true
    var roastMode: Bool = false
    
    var body: some View {
        Image(systemName: roastMode ? "flame.fill" : "star.fill")
            .font(.system(size: size * 0.7))
            .foregroundColor(roastMode ? .orange : .yellow)
            .padding(showBackground ? 2 : 0)
            .background(
                showBackground
                    ? AnyShapeStyle(Color.yellow.opacity(0.15))
                    : AnyShapeStyle(Color.clear)
            )
            .clipShape(Circle())
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let level: ConfidenceLevel
    var roastMode: Bool = false
    
    enum ConfidenceLevel: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case review = "Review"
        
        var variant: BitBinderBadge.BadgeVariant {
            switch self {
            case .high: return .success
            case .medium: return .info
            case .low: return .warning
            case .review: return .neutral
            }
        }
        
        var icon: String {
            switch self {
            case .high: return "checkmark.circle.fill"
            case .medium: return "circle.fill"
            case .low: return "exclamationmark.circle.fill"
            case .review: return "eye.fill"
            }
        }
    }
    
    var body: some View {
        BitBinderBadge(
            text: level.rawValue,
            icon: level.icon,
            variant: level.variant,
            size: .small,
            roastMode: roastMode
        )
    }
}

// MARK: - Toolbar Background Modifier (simplified)

struct BitBinderToolbar: ViewModifier {
    var roastMode: Bool = false
    
    func body(content: Content) -> some View {
        content
            .toolbarColorScheme(roastMode ? .dark : .light, for: .navigationBar)
    }
}

extension View {
    func bitBinderToolbar(roastMode: Bool) -> some View {
        modifier(BitBinderToolbar(roastMode: roastMode))
    }
}

// MARK: - Previews

#Preview("Empty State") {
    BitBinderEmptyState(
        icon: "text.quote",
        title: "No jokes yet",
        subtitle: "Add your first joke using the + button",
        actionTitle: "Add Joke",
        action: { }
    )
}

#Preview("Chips") {
    VStack(spacing: 16) {
        HStack {
            BitBinderChip(text: "All", isSelected: true, style: .filter, action: {})
            BitBinderChip(text: "Recent", isSelected: false, style: .filter, action: {})
            BitBinderChip(text: "Work", isSelected: false, style: .filter, action: {})
        }
        
        HStack {
            BitBinderChip(text: "dating", icon: "tag.fill", style: .tag)
            BitBinderChip(text: "work", icon: "tag.fill", style: .tag)
        }
    }
    .padding()
}

#Preview("Badges") {
    VStack(spacing: 12) {
        HStack {
            BitBinderBadge(text: "Synced", icon: "checkmark.circle.fill", variant: .success)
            BitBinderBadge(text: "Review", icon: "eye.fill", variant: .warning)
            BitBinderBadge(text: "Error", icon: "xmark.circle.fill", variant: .error)
        }
        HStack {
            HitStarBadge()
            ConfidenceBadge(level: .high)
            ConfidenceBadge(level: .medium)
            ConfidenceBadge(level: .low)
        }
    }
    .padding()
}