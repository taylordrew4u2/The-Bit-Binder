//
//  GagGrabberFace.swift
//  thebitbinder
//
//  GagGrabber's face — a friendly cartoon character drawn with SwiftUI
//  shapes. Used as the hero avatar in `HybridGagGrabberSheet` and anywhere
//  else GagGrabber needs a visual identity.
//
//  The face reacts to GagGrabber's current state via the `Mood` enum:
//    • idle      — eyes half-open, content smile, idle blink
//    • working   — magnifying glass sweeping, eyes scanning
//    • happy     — eyes squinted, wide grin (successful extraction)
//    • confused  — eyes askew, wavy mouth (error state)
//

import SwiftUI

struct GagGrabberFace: View {

    enum Mood {
        case idle, working, happy, confused
    }

    var mood: Mood = .idle
    var size: CGFloat = 96

    // Animated sub-states
    @State private var blink: Bool = false
    @State private var lensAngle: Double = -20
    @State private var eyeScan: CGFloat = 0

    var body: some View {
        ZStack {
            // Soft halo behind the head
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: size * 1.25, height: size * 1.25)

            // Head
            head

            // Hair tuft
            hairTuft
                .offset(x: -size * 0.18, y: -size * 0.42)

            // Eyes
            HStack(spacing: size * 0.18) {
                eye(left: true)
                eye(left: false)
            }
            .offset(y: -size * 0.08)

            // Mouth
            mouth
                .offset(y: size * 0.18)

            // Magnifying glass — the signature GagGrabber accessory
            magnifyingGlass
                .frame(width: size * 0.45, height: size * 0.45)
                .rotationEffect(.degrees(lensAngle))
                .offset(x: size * 0.32, y: size * 0.28)
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .onAppear { startAnimations() }
        .onChange(of: mood) { _, _ in startAnimations() }
        .accessibilityLabel("GagGrabber")
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Head

    private var head: some View {
        RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.86, blue: 0.70),
                        Color(red: 0.98, green: 0.78, blue: 0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size * 1.05)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private var hairTuft: some View {
        Path { path in
            let w = size * 0.34
            let h = size * 0.22
            path.move(to: CGPoint(x: 0, y: h))
            path.addQuadCurve(
                to: CGPoint(x: w, y: h),
                control: CGPoint(x: w * 0.5, y: -h * 0.6)
            )
            path.addLine(to: CGPoint(x: w * 0.75, y: h))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.35, y: h),
                control: CGPoint(x: w * 0.55, y: -h * 0.1)
            )
            path.closeSubpath()
        }
        .fill(Color(red: 0.35, green: 0.24, blue: 0.18))
        .frame(width: size * 0.34, height: size * 0.22)
    }

    // MARK: - Eyes

    @ViewBuilder
    private func eye(left: Bool) -> some View {
        switch mood {
        case .idle:
            openEye(squint: blink ? 0.1 : 1.0)
        case .working:
            openEye(squint: 1.0)
                .offset(x: eyeScan * (left ? -1 : 1))
        case .happy:
            happyEye()
        case .confused:
            confusedEye(tilt: left ? -12 : 10)
        }
    }

    private func openEye(squint: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.18, height: size * 0.18 * squint)
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.7), lineWidth: 1)
                )
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.08, height: size * 0.08 * squint)
            // Glint
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.025, height: size * 0.025)
                .offset(x: -size * 0.02, y: -size * 0.02)
        }
    }

    private func happyEye() -> some View {
        Path { path in
            let w = size * 0.18
            let h = size * 0.1
            path.move(to: CGPoint(x: 0, y: h))
            path.addQuadCurve(
                to: CGPoint(x: w, y: h),
                control: CGPoint(x: w * 0.5, y: -h * 0.4)
            )
        }
        .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .frame(width: size * 0.18, height: size * 0.1)
    }

    private func confusedEye(tilt: Double) -> some View {
        ZStack {
            Path { path in
                let w = size * 0.18
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: w, y: w * 0.3))
            }
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: size * 0.18, height: size * 0.1)

            Path { path in
                let w = size * 0.18
                path.move(to: CGPoint(x: 0, y: w * 0.3))
                path.addLine(to: CGPoint(x: w, y: 0))
            }
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            .frame(width: size * 0.18, height: size * 0.1)
        }
        .rotationEffect(.degrees(tilt))
    }

    // MARK: - Mouth

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .idle:
            smile(width: size * 0.35, depth: size * 0.06)
        case .working:
            smile(width: size * 0.28, depth: size * 0.04)
        case .happy:
            grin
        case .confused:
            wavyMouth
        }
    }

    private func smile(width: CGFloat, depth: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: width, y: 0),
                control: CGPoint(x: width * 0.5, y: depth * 1.6)
            )
        }
        .stroke(Color.black.opacity(0.85),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .frame(width: width, height: depth)
    }

    private var grin: some View {
        ZStack {
            // Outer grin
            Path { path in
                let w = size * 0.42
                let h = size * 0.16
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: w, y: 0),
                    control: CGPoint(x: w * 0.5, y: h * 1.3)
                )
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.closeSubpath()
            }
            .fill(Color(red: 0.6, green: 0.2, blue: 0.25))
            .frame(width: size * 0.42, height: size * 0.16)

            // Teeth highlight
            RoundedRectangle(cornerRadius: size * 0.02)
                .fill(Color.white)
                .frame(width: size * 0.36, height: size * 0.04)
                .offset(y: -size * 0.03)
        }
    }

    private var wavyMouth: some View {
        Path { path in
            let w = size * 0.34
            let h = size * 0.05
            let step = w / 4
            path.move(to: CGPoint(x: 0, y: h))
            path.addQuadCurve(to: CGPoint(x: step, y: 0), control: CGPoint(x: step * 0.5, y: 0))
            path.addQuadCurve(to: CGPoint(x: step * 2, y: h), control: CGPoint(x: step * 1.5, y: h * 2))
            path.addQuadCurve(to: CGPoint(x: step * 3, y: 0), control: CGPoint(x: step * 2.5, y: 0))
            path.addQuadCurve(to: CGPoint(x: step * 4, y: h), control: CGPoint(x: step * 3.5, y: h * 2))
        }
        .stroke(Color.black.opacity(0.85),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .frame(width: size * 0.34, height: size * 0.08)
    }

    // MARK: - Magnifying glass

    private var magnifyingGlass: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.22, green: 0.22, blue: 0.26), lineWidth: size * 0.06)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.35))
                )
                .clipShape(Circle())

            // Lens highlight
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: -size * 0.07, y: -size * 0.07)

            // Handle
            Capsule()
                .fill(Color(red: 0.22, green: 0.22, blue: 0.26))
                .frame(width: size * 0.07, height: size * 0.22)
                .offset(x: size * 0.18, y: size * 0.18)
                .rotationEffect(.degrees(45), anchor: .center)
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        // Cancel prior animation state
        blink = false
        lensAngle = -20
        eyeScan = 0

        switch mood {
        case .idle:
            // Slow blink loop
            withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true).delay(3)) {
                blink.toggle()
            }
        case .working:
            // Magnifying-glass sweep + eye scan
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                lensAngle = 20
                eyeScan = size * 0.03
            }
        case .happy, .confused:
            break
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
