//
//  RoastButtons.swift
//  thebitbinder
//
//  Shared Roast Mode CTA button styles. Dedupes the ember-filled pill
//  used in cold state, target detail empty state, and other roast-mode CTAs.
//

import SwiftUI

/// Primary roast CTA with a contrast-safe fill and Dynamic Type label.
struct EmberCTAButton: View {
    let icon: String?
    let title: String
    let action: () -> Void

    init(icon: String? = "flame", title: String, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.headline)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(ActionColors.foreground)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(FirePalette.emberCTA)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Secondary outline CTA — used for "Add subject" inline append rows.
struct EmberOutlineButton: View {
    let icon: String?
    let title: String
    let action: () -> Void

    init(icon: String? = "plus", title: String, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(FirePalette.core)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(FirePalette.core.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(FirePalette.edge, lineWidth: 0.5)
            )
        }
    }
}
