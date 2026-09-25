//
//  AppTextSize.swift
//  thebitbinder
//

import SwiftUI

enum AppTextSize: String, CaseIterable, Identifiable {
    case system
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Explicit app sizes apply only to standard text sizes. Accessibility
    /// sizes always follow the system so this preference cannot cap them.
    func resolvedDynamicTypeSize(systemSize: DynamicTypeSize) -> DynamicTypeSize {
        guard !systemSize.isAccessibilitySize else { return systemSize }
        switch self {
        case .system: return systemSize
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .extraLarge: return .xxLarge
        }
    }
}
