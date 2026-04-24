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
//                        release. Double-tap expands to full drawer.
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
final class BitBuddyPresentationController: ObservableObject {
    @Published var mode: BitBuddyPresentation = .closed

    /// The corner the compact window last snapped to. Persists across
    /// app launches so users don't have to redrag it every session.
    @AppStorage("bitBuddyCompactCorner") private var storedCorner: String = "bottomTrailing"

    var corner: Corner {
        get { Corner(rawValue: storedCorner) ?? .bottomTrailing }
        set { storedCorner = newValue.rawValue }
    }

    enum Corner: String, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading:     return .topLeading
            case .topTrailing:    return .topTrailing
            case .bottomLeading:  return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    func openCompact() {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
            mode = .compact
        }
    }

    func expandToFull() {
        withAnimation(.easeInOut(duration: 0.28)) {
            mode = .full
        }
    }

    func collapseToCompact() {
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.82)) {
            mode = .compact
        }
    }

    func close() {
        withAnimation(.easeInOut(duration: 0.22)) {
            mode = .closed
        }
    }
}

// MARK: - Compact window

struct BitBuddyCompactWindow: View {
    @ObservedObject var presenter: BitBuddyPresentationController
    let roastMode: Bool

    /// Window dimensions. Wide enough for three lines of typical message
    /// text without wrapping, tall enough for ~6 turns before scrolling.
    private let windowWidth: CGFloat = 300
    private let windowHeight: CGFloat = 380
    private let margin: CGFloat = 14

    @State private var dragOffset: CGSize = .zero

    private var accent: Color {
        roastMode ? FirePalette.core : .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            if presenter.mode == .compact {
                ZStack(alignment: presenter.corner.alignment) {
                    Color.clear
                    windowPanel(geo: geo)
                        .padding(margin)
                        .offset(dragOffset)
                        .gesture(dragGesture(geo: geo))
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.6, anchor: anchorPoint)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.6, anchor: anchorPoint)
                                .combined(with: .opacity)
                        ))
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
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

    @ViewBuilder
    private func windowPanel(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            // Host the real chat view inside a constrained frame. The
            // chat view already knows how to compose a small-mode layout
            // because its messages list is a ScrollView that adapts to
            // any height.
            NavigationStack {
                BitBuddyChatView()
                    .navigationBarHidden(true)
            }
            .frame(height: windowHeight - 44) // 44 = header
        }
        .frame(width: windowWidth, height: windowHeight)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(roastMode ? Color(FirePalette.bg) : Color(UIColor.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(roastMode ? FirePalette.core.opacity(0.27) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: roastMode ? FirePalette.core.opacity(0.2) : .black.opacity(0.22), radius: 22, x: 0, y: 12)
        .environment(\.dismissBitBuddyDrawer) {
            presenter.close()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BitBuddyAvatar(roastMode: roastMode, size: 24, symbolSize: 14)
            Text(roastMode ? "Roast Buddy" : "BitBuddy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(roastMode ? FirePalette.text : .primary)
            Spacer(minLength: 4)

            // Expand → full drawer
            Button {
                presenter.expandToFull()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand BitBuddy")

            // Close → collapse back to puck
            Button {
                presenter.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close BitBuddy")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            // Subtle accent tint on the header so the window feels tied to
            // the puck it came from.
            LinearGradient(
                colors: [accent.opacity(0.10), accent.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Drag

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let predicted = CGPoint(
                    x: value.predictedEndLocation.x,
                    y: value.predictedEndLocation.y
                )
                let nearest = nearestCorner(to: predicted, in: geo.size)
                withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.82)) {
                    presenter.corner = nearest
                    dragOffset = .zero
                }
            }
    }

    private func nearestCorner(to point: CGPoint, in size: CGSize) -> BitBuddyPresentationController.Corner {
        let isTop = point.y < size.height / 2
        let isLeading = point.x < size.width / 2
        switch (isTop, isLeading) {
        case (true,  true):  return .topLeading
        case (true,  false): return .topTrailing
        case (false, true):  return .bottomLeading
        case (false, false): return .bottomTrailing
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
