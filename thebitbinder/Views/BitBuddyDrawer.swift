//
//  BitBuddyDrawer.swift
//  thebitbinder
//
//  A right-edge slide-in panel that hosts BitBuddyChatView so users can chat
//  alongside whatever they're working on (editing a joke, scribbling in
//  Brainstorm, reviewing a set list). Replaces the previous .sheet
//  presentations so BitBuddy feels like a messaging pane that rides along
//  with the active screen instead of taking over the whole view.
//

import SwiftUI

// MARK: - Controller

/// Shared state for the BitBuddy drawer. Inject via `.environmentObject`
/// at the app root so any view can request the drawer to open.
final class BitBuddyDrawerController: ObservableObject {
    @Published var isOpen: Bool = false

    func open() {
        guard !isOpen else { return }
        isOpen = true
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
    }

    func toggle() {
        isOpen.toggle()
    }
}

// MARK: - Drawer overlay

struct BitBuddyDrawerOverlay: View {
    @ObservedObject var controller: BitBuddyDrawerController
    let roastMode: Bool

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(max(geo.size.width * 0.88, 320), 440)

            ZStack(alignment: .trailing) {
                // Scrim — catches taps outside the drawer to close it.
                if controller.isOpen {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86)) {
                                controller.close()
                            }
                        }
                }

                // Drawer panel
                if controller.isOpen {
                    drawerPanel(width: drawerWidth)
                        .frame(width: drawerWidth)
                        .frame(maxHeight: .infinity)
                        .background(
                            Color(UIColor.systemBackground)
                                .ignoresSafeArea(edges: .vertical)
                        )
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.08))
                                .frame(width: 0.5)
                                .ignoresSafeArea(edges: .vertical)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 24, x: -6, y: 0)
                        .offset(x: max(0, dragOffset))
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in
                                    if value.translation.width > 0 {
                                        dragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    if value.translation.width > drawerWidth * 0.28
                                        || value.predictedEndTranslation.width > drawerWidth * 0.5 {
                                        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86)) {
                                            controller.close()
                                            dragOffset = 0
                                        }
                                    } else {
                                        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )
                        .transition(.move(edge: .trailing))
                        .onDisappear { dragOffset = 0 }
                }
            }
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.88), value: controller.isOpen)
        }
    }

    private func drawerPanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drag handle + close row
            HStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.leading, 8)

                Spacer()

                Button {
                    haptic(.light)
                    withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86)) {
                        controller.close()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            NavigationStack {
                BitBuddyChatView()
            }
        }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Attach this to the topmost view that should host the drawer (typically
    /// MainTabView / the app's root). It layers the drawer overlay on top of
    /// the view and injects the controller into the environment so any child
    /// can call `bitBuddyDrawer.open()`.
    func bitBuddyDrawer(controller: BitBuddyDrawerController, roastMode: Bool) -> some View {
        self
            .environmentObject(controller)
            .overlay {
                BitBuddyDrawerOverlay(controller: controller, roastMode: roastMode)
                    .ignoresSafeArea()
            }
    }
}
