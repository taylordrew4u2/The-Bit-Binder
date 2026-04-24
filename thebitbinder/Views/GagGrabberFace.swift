//
//  GagGrabberFace.swift
//  thebitbinder
//
//  GagGrabber's visual identity. Backed by the `GagGrabberIcon` asset
//  (G1 Classic Claw). The `Mood` enum drives a lightweight overlay so
//  call sites keep the same API.
//

import SwiftUI

struct GagGrabberFace: View {

    enum Mood {
        case idle, working, happy, confused
    }

    var mood: Mood = .idle
    var size: CGFloat = 96

    @State private var bounce: CGFloat = 1.0

    var body: some View {
        ZStack {
            Image("GagGrabberIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .scaleEffect(bounce)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            overlay
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .onAppear { animate(for: mood) }
        .onChange(of: mood) { _, newMood in animate(for: newMood) }
        .accessibilityLabel("GagGrabber")
        .accessibilityHint(accessibilityHint)
    }

    @ViewBuilder
    private var overlay: some View {
        switch mood {
        case .idle, .happy:
            EmptyView()
        case .working:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.accentColor)
                .offset(x: size * 0.32, y: size * 0.32)
        case .confused:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size * 0.26, weight: .bold))
                .foregroundStyle(.white, Color.recording)
                .offset(x: size * 0.32, y: size * 0.32)
        }
    }

    private func animate(for mood: Mood) {
        switch mood {
        case .happy:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                bounce = 1.08
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.2)) {
                bounce = 1.0
            }
        default:
            withAnimation(.easeOut(duration: 0.2)) { bounce = 1.0 }
        }
    }

    private var accessibilityHint: String {
        switch mood {
        case .idle:     return "waiting for a document"
        case .working:  return "reading the document"
        case .happy:    return "finished extracting jokes"
        case .confused: return "had trouble reading the document"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            GagGrabberFace(mood: .idle)
            GagGrabberFace(mood: .working)
        }
        HStack(spacing: 24) {
            GagGrabberFace(mood: .happy)
            GagGrabberFace(mood: .confused)
        }
    }
    .padding()
}
