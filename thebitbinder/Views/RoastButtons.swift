//
//  RoastButtons.swift
//  thebitbinder
//
//  Shared Roast Mode CTA button styles. Dedupes the ember-gradient pill
//  used in cold state, target detail empty state, and other roast-mode CTAs.
//

import SwiftUI

/// Primary roast CTA — ember gradient, capsule, white text, glow shadow.
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
                        .font(.system(size: 14))
                }
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(FirePalette.emberCTA)
            .clipShape(Capsule())
            .shadow(color: FirePalette.core.opacity(0.3), radius: 14, y: 6)
        }
        .accessibilityAddTraits(.isButton)
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
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(FirePalette.core)
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
