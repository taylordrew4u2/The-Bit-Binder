//
//  BitBuddyCompactWindow.swift
//  thebitbinder
//
//  A compact floating chat window for BitBuddy — a middle state between
//  the 56pt draggable puck and the full right-edge drawer.
//
//  Flow:
//    puck tap          → open compact window (~280×360) pinned to the
//                        closest corner of the screen
//    compact: header   → drag to reposition; snaps to nearest corner on
//                        release.
//    compact: expand   → goes to full BitBuddyDrawerOverlay
//    compact: close    → collapses back to the puck
//
//  Integrates with the existing BitBuddyDrawerController by reading the
//  new `presentation` mode. Fall back to .full if you need the old
//  drawer-only behavior (e.g. for long tool-use threads from Jokes).
//

import SwiftUI

// MARK: - Presentation mode

enum BitBuddyPresentation {
    case closed    // puck visible, no chat
    case compact   // small floating window
    case full      // full-height right-edge drawer
}

/// Attach this onto the controller as an extension so we can ship the
/// compact window without changing `BitBuddyDrawerController`'s published
/// API. The controller still exposes `isOpen` for the existing drawer
/// code paths; new code reads `presentation`.
@MainActor
final class BitBuddyPresentationController: ObservableObject {
    @Published var mode: BitBuddyPresentation = .closed

    /// The corner the compact window last snapped to. Persists across
    /// app launches so users don't have to redrag it every session.
    @AppStorage("bitBuddyCompactCorner") private var storedCorner: String = "bottomTrailing"

    var corner: Corner {
        get { Corner(rawValue: storedCorner) ?? .bottomTrailing }
        set {
            guard newValue != corner else { return }
            objectWillChange.send()
            storedCorner = newValue.rawValue
        }
    }

    typealias Corner = BitBuddyCompactLayout.Corner

    func openCompact() {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
            mode = .compact
        }
    }

    func expandToFull() {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.28)) {
            mode = .full
        }
    }

    func collapseToCompact() {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
            mode = .compact
        }
    }

    func close() {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.22)) {
            mode = .closed
        }
    }
}

// MARK: - Compact window

struct BitBuddyCompactWindow: View {
    @ObservedObject var presenter: BitBuddyPresentationController
    let roastMode: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var dragCoordinateSpace
    @State private var dragOffset: CGSize = .zero

    private var accent: Color {
        roastMode ? FirePalette.core : .accentColor
    }

    private var isRightToLeft: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        GeometryReader { geo in
            let layout = BitBuddyCompactLayout(
                containerSize: geo.size,
                needsExpandedLayout: dynamicTypeSize.isAccessibilitySize
            )
            let origin = layout.origin(for: presenter.corner, isRightToLeft: isRightToLeft)
            let offset = layout.constrainedOffset(dragOffset, from: origin)

            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if presenter.mode == .compact {
                    windowPanel(layout: layout)
                        .position(
                            x: origin.x + layout.panelSize.width / 2 + offset.width,
                            y: origin.y + layout.panelSize.height / 2 + offset.height
                        )
                        .transition(panelTransition)
                        .onDisappear { dragOffset = .zero }
                }
            }
            .coordinateSpace(name: dragCoordinateSpace)
            .onChange(of: geo.size) { dragOffset = .zero }
            .onChange(of: dynamicTypeSize) { dragOffset = .zero }
        }
        // Leave keyboard safe-area handling enabled. The same chat instance
        // expands into the usable bounds instead of being remounted in a drawer.
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }

    private var panelTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.6, anchor: anchorPoint).combined(with: .opacity)
    }

    private var anchorPoint: UnitPoint {
        switch presenter.corner {
        case .topLeading:     return .topLeading
        case .topTrailing:    return .topTrailing
        case .bottomLeading:  return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    // MARK: - Panel

    private func windowPanel(layout: BitBuddyCompactLayout) -> some View {
        let cornerRadius: CGFloat = layout.isExpanded ? 0 : 22
        return VStack(spacing: 0) {
            header(layout: layout)
            Divider().opacity(0.4)
            NavigationStack {
                BitBuddyChatView(onClose: { presenter.close() })
                    .toolbarVisibility(.hidden, for: .navigationBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .background(roastMode ? Color(FirePalette.bg) : Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(roastMode ? FirePalette.core.opacity(0.27) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: layout.isExpanded ? 0 : 12, x: 0, y: 6)
    }

    // MARK: - Header

    private func header(layout: BitBuddyCompactLayout) -> some View {
        HStack(spacing: 0) {
            // Only this visible header region moves the panel. Conversation
            // scrolling, text selection, and the neighboring buttons stay free
            // of the window's drag gesture.
            HStack(spacing: 8) {
                BitBuddyAvatar(roastMode: roastMode, size: 24, symbolSize: 14)
                    .accessibilityHidden(true)
                Text(roastMode ? "Roast Buddy" : "BitBuddy")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(roastMode ? FirePalette.text : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !layout.isExpanded {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .gesture(dragGesture(layout: layout), including: layout.isExpanded ? .none : .all)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Button {
                presenter.expandToFull()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand BitBuddy")

            Button {
                presenter.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close BitBuddy")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accent.opacity(0.06))
    }

    // MARK: - Drag

    private func dragGesture(layout: BitBuddyCompactLayout) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(dragCoordinateSpace))
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let origin = layout.origin(for: presenter.corner, isRightToLeft: isRightToLeft)
                let predictedCenter = CGPoint(
                    x: origin.x + layout.panelSize.width / 2 + value.predictedEndTranslation.width,
                    y: origin.y + layout.panelSize.height / 2 + value.predictedEndTranslation.height
                )
                let nearest = layout.nearestCorner(to: predictedCenter, isRightToLeft: isRightToLeft)
                withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.4, dampingFraction: 0.82)) {
                    presenter.corner = nearest
                    dragOffset = .zero
                }
            }
    }
}

// MARK: - Attach helper

extension View {
    /// Layer the compact window on top of the view. Call alongside
    /// `.bitBuddyDrawer(controller:roastMode:)` — they don't conflict
    /// because they read different modes on the presenter.
    func bitBuddyCompactWindow(presenter: BitBuddyPresentationController, roastMode: Bool) -> some View {
        self.overlay(alignment: .topLeading) {
            BitBuddyCompactWindow(presenter: presenter, roastMode: roastMode)
        }
    }
}
