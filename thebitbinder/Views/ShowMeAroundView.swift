//
//  ShowMeAroundView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 4/17/26.
//
//  Interactive guided tour. Each step has:
//    • An animated hero icon (pulses on appear, optional fire halo in roast mode)
//    • A visual preview "mock" of the feature being described
//    • A numbered "How to use it" 1→2→3 mini-flow
//    • Feature bullets and a pro tip
//  Roast Mode swaps the palette to the fire palette and wraps the hero icon
//  in a radial flame glow.
//

import SwiftUI
import UIKit

// MARK: - Root View

/// Interactive guided tour that walks the user through every screen in the app,
/// explaining what each feature does, how to use it, and showing a miniature
/// preview of what it looks like.
struct ShowMeAroundView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode: Bool = false
    @State private var currentStep = 0

    /// Full tour for the current mode. Roast Mode has its own, shorter tour
    /// focused on roast-specific features.
    private var steps: [TourStep] {
        roastMode ? TourStep.roastTour : TourStep.standardTour
    }

    /// Accent color for a given step. In roast mode all steps pull from the
    /// fire palette so the tour reads as a single heat-map; in standard mode
    /// each step keeps its topical color for variety.
    private func accent(for step: TourStep) -> Color {
        roastMode ? FirePalette.core : step.color
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress pills — a tappable breadcrumb that shows every step.
            StepProgressPills(
                count: steps.count,
                current: currentStep,
                tint: roastMode ? FirePalette.core : .accentColor,
                onTap: { index in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = index
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            )
            .padding(.horizontal)
            .padding(.top, 10)

            Text("\(currentStep + 1) of \(steps.count)")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.top, 6)

            TabView(selection: $currentStep) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    TourStepView(
                        step: step,
                        accent: accent(for: step),
                        roastMode: roastMode
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .onChange(of: currentStep) { _, _ in
                // Light haptic on page change so every swipe feels responsive.
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }

            // Navigation buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button {
                        withAnimation { currentStep -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                } else {
                    Spacer().frame(width: 80)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button {
                        withAnimation { currentStep += 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(
                            Group {
                                if roastMode {
                                    FirePalette.flameHorizontal
                                } else {
                                    Color.accentColor
                                }
                            }
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: (roastMode ? FirePalette.core : .accentColor).opacity(0.35),
                                radius: 8, x: 0, y: 3)
                    }
                } else {
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text(roastMode ? "Let's Roast!" : "Get Started!")
                            Image(systemName: "checkmark")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(
                            Group {
                                if roastMode {
                                    FirePalette.flameHorizontal
                                } else {
                                    Color.accentColor
                                }
                            }
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: (roastMode ? FirePalette.core : .accentColor).opacity(0.35),
                                radius: 8, x: 0, y: 3)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle(roastMode ? "Welcome to the Burn Book" : "Show Me Around")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Progress Pills

/// Horizontal row of small pills, one per step. The current step's pill is
/// wider and filled; completed steps are filled but small; upcoming steps are
/// dim. Tapping a pill jumps to that step.
private struct StepProgressPills: View {
    let count: Int
    let current: Int
    let tint: Color
    let onTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                let isCurrent = i == current
                let isDone = i < current
                Capsule()
                    .fill(isCurrent || isDone ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.22)))
                    .frame(width: isCurrent ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: current)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(i) }
                    .accessibilityLabel("Step \(i + 1) of \(count)")
            }
        }
    }
}

// MARK: - Single Step View

/// Renders one tour step: animated hero → mini preview → feature bullets →
/// "how to" numbered flow → pro tip. Scrollable so tall content still fits on
/// small devices.
private struct TourStepView: View {
    let step: TourStep
    let accent: Color
    let roastMode: Bool

    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0.0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                heroIcon

                // Title
                Text(step.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // Subtitle
                Text(step.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Visual preview mock — a styled miniature of the feature.
                if let mock = step.preview {
                    PreviewMockView(kind: mock, accent: accent, roastMode: roastMode)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }

                // Feature bullets
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(step.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(accent)
                                .font(.body)
                            Text(feature)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)

                // How to use it — numbered 1→2→3 mini-flow.
                if !step.howTo.isEmpty {
                    HowToFlow(howTo: step.howTo, accent: accent)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                // Pro tip
                if let tip = step.proTip {
                    ProTipCard(text: tip, roastMode: roastMode)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }

                Spacer(minLength: 80)
            }
        }
        .onAppear(perform: animateIn)
    }

    /// Animated hero icon. In roast mode the icon sits on a radial flame glow
    /// so the first thing the user sees feels like fire. In standard mode the
    /// icon sits on a soft tint-colored disc.
    private var heroIcon: some View {
        ZStack {
            if roastMode {
                // Fire glow backdrop
                Circle()
                    .fill(FirePalette.glowRadial)
                    .frame(width: 180, height: 180)
                    .blur(radius: 4)
                    .opacity(0.9)
            }

            Circle()
                .fill(accent.opacity(roastMode ? 0.18 : 0.12))
                .frame(width: 110, height: 110)

            Image(systemName: step.icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(
                    roastMode
                    ? AnyShapeStyle(FirePalette.flame)
                    : AnyShapeStyle(accent)
                )
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
        }
        .frame(height: 180)
    }

    private func animateIn() {
        iconScale = 0.6
        iconOpacity = 0.0
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
    }
}

// MARK: - Pro Tip Card

private struct ProTipCard: View {
    let text: String
    let roastMode: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: roastMode ? "flame.fill" : "lightbulb.fill")
                .foregroundColor(roastMode ? FirePalette.core : .accentColor)
                .font(.body)
            Text(.init("**\(roastMode ? "Hot Tip:" : "Pro Tip:")** \(text)"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((roastMode ? FirePalette.core : Color.accentColor).opacity(DS.Opacity.subtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder((roastMode ? FirePalette.core : Color.accentColor).opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - How-To Numbered Flow

/// Numbered 1 → 2 → 3 mini-flow with arrow connectors. Designed to read as a
/// concrete "do this, then this, then this" recipe under the feature bullets.
private struct HowToFlow: View {
    let howTo: [String]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundColor(accent)
                Text("How to use it")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(howTo.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 12) {
                        // Numbered badge
                        ZStack {
                            Circle()
                                .fill(accent)
                                .frame(width: 24, height: 24)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }

                        Text(line)
                            .font(.footnote)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)

                    if index < howTo.count - 1 {
                        HStack {
                            // Vertical connector line so the 1→2→3 reads visually.
                            Rectangle()
                                .fill(accent.opacity(0.25))
                                .frame(width: 2, height: 10)
                                .padding(.leading, 11)
                            Spacer()
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Preview Mocks

/// Small in-tour preview cards that give the user a concrete sense of what the
/// feature looks like, without dragging in any real data.
private struct PreviewMockView: View {
    let kind: TourStep.PreviewKind
    let accent: Color
    let roastMode: Bool

    var body: some View {
        Group {
            switch kind {
            case .jokeCard:        jokeCardMock
            case .setListRow:      setListMock
            case .photoPage:       photoPageMock
            case .brainstormCard:  brainstormMock
            case .waveform:        waveformMock
            case .chatBubble:      chatBubbleMock
            case .homeGrid:        homeGridMock
            case .flameTarget:     flameTargetMock
            case .confetti:        confettiMock
            case .settingsRow:     settingsRowMock
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Individual mocks

    private var jokeCardMock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.8))
                    .frame(width: 64, height: 18)
                Spacer()
                Image(systemName: "star")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            Text("Airline seats are so small now")
                .font(.subheadline.weight(.semibold))
            Text("...I had to fold like an origami crane. My knees are in 14B, my dignity is in checked luggage.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                TagPill(text: "travel", accent: accent)
                TagPill(text: "observational", accent: accent)
            }
        }
    }

    private var setListMock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SATURDAY · THE COMEDY CELLAR")
                .font(.caption2.weight(.bold))
                .foregroundColor(accent)
            VStack(spacing: 4) {
                setListRow(index: 1, title: "Airline seats bit", time: "1:20")
                setListRow(index: 2, title: "Dating apps tangent", time: "2:05")
                setListRow(index: 3, title: "Closer — family story", time: "3:10")
            }
            HStack {
                Spacer()
                Text("Est. 6:35")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func setListRow(index: Int, title: String, time: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundColor(accent)
                .frame(width: 18, alignment: .leading)
            Text(title)
                .font(.footnote)
                .lineLimit(1)
            Spacer()
            Text(time)
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var photoPageMock: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 70, height: 90)
                .overlay(
                    Image(systemName: "doc.text.image")
                        .font(.title2)
                        .foregroundColor(.secondary)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text("Notebook · Page 14")
                    .font(.subheadline.weight(.semibold))
                Text("Scratched joke about airport Starbucks lines — revisit for next set.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    TagPill(text: "handwritten", accent: accent)
                }
            }
            Spacer()
        }
    }

    private var brainstormMock: some View {
        HStack(spacing: 8) {
            brainstormCard(color: Color(red: 1.0, green: 0.97, blue: 0.77),
                           text: "What if grocery stores had therapy aisles?")
            brainstormCard(color: Color(red: 0.82, green: 0.92, blue: 1.0),
                           text: "Gym people vs. library people — same rules?")
        }
    }

    private func brainstormCard(color: Color, text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundColor(.black.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color)
            )
    }

    private var waveformMock: some View {
        HStack(spacing: 3) {
            ForEach(0..<28, id: \.self) { i in
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: waveHeight(for: i))
                    .opacity(0.85)
            }
        }
        .frame(height: 44)
        .padding(.vertical, 4)
    }

    /// Deterministic pseudo-random heights so the bar graph reads like a real
    /// waveform without any time-based redraws.
    private func waveHeight(for index: Int) -> CGFloat {
        let base = sin(Double(index) * 0.6) + cos(Double(index) * 0.33)
        let normalized = (base + 2.0) / 4.0 // 0...1-ish
        return CGFloat(8 + normalized * 30)
    }

    private var chatBubbleMock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: roastMode ? "flame.fill" : "sparkles")
                                .foregroundColor(accent).font(.caption))
                VStack(alignment: .leading, spacing: 4) {
                    Text("BitBuddy")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(roastMode
                         ? "Give me three burns on guys who say they're \"pretty chill\" in their bio..."
                         : "Want me to sharpen your closer? I can tighten the setup in two beats.")
                        .font(.footnote)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.tertiarySystemBackground))
                        )
                }
            }
        }
    }

    private var homeGridMock: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 8) {
            homeGridTile(icon: "text.quote", label: "Jokes", count: "42", color: accent)
            homeGridTile(icon: "list.bullet.rectangle.portrait.fill",
                         label: "Sets", count: "3", color: .purple)
            homeGridTile(icon: "waveform", label: "Recordings", count: "11", color: .red)
            homeGridTile(icon: "lightbulb.fill", label: "Ideas", count: "27", color: .yellow)
        }
    }

    private func homeGridTile(icon: String, label: String, count: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(count)
                    .font(.title3.bold())
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var flameTargetMock: some View {
        HStack(spacing: 12) {
            // Target silhouette
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.fill.questionmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
                // Fire overlay corner
                Image(systemName: "flame.fill")
                    .font(.body)
                    .foregroundStyle(FirePalette.flame)
                    .offset(x: 22, y: -22)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Target: My Best Friend")
                    .font(.subheadline.weight(.semibold))
                Text("7 burns · 3 A-material")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TagPill(text: "tall", accent: FirePalette.core)
                    TagPill(text: "engaged", accent: FirePalette.core)
                }
            }
            Spacer()
        }
    }

    private var confettiMock: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "star.fill")
                    .foregroundColor(confettiColor(for: i))
                    .font(.caption)
                    .offset(x: CGFloat((i * 37) % 200) - 100,
                            y: CGFloat((i * 53) % 70) - 35)
                    .rotationEffect(.degrees(Double((i * 73) % 360)))
            }
            Text("🎤")
                .font(.largeTitle)
        }
        .frame(height: 70)
    }

    private func confettiColor(for i: Int) -> Color {
        if roastMode {
            return [FirePalette.core, FirePalette.bright, FirePalette.ember, FirePalette.glow][i % 4]
        } else {
            return [.pink, .purple, .blue, .green, .orange, .yellow][i % 6]
        }
    }

    private var settingsRowMock: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "person.crop.circle", title: "Display Name", value: "Taylor")
            Divider().padding(.leading, 40)
            settingsRow(icon: "flame.fill", title: "Roast Mode",
                        value: roastMode ? "On" : "Off",
                        tint: roastMode ? FirePalette.core : .secondary)
            Divider().padding(.leading, 40)
            settingsRow(icon: "icloud.fill", title: "iCloud Sync", value: "On")
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func settingsRow(icon: String, title: String, value: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(accent)
                .frame(width: 22)
            Text(title)
                .font(.footnote)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

// MARK: - Tag Pill

private struct TagPill: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(accent.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.5)
            )
    }
}

// MARK: - Tour Step Model

struct TourStep {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let features: [String]
    /// Numbered 1→2→3 recipe. When empty, the "How to use it" section is hidden.
    let howTo: [String]
    /// Optional inline preview mock. Nil means the step only shows icon + text.
    let preview: PreviewKind?
    let proTip: String?

    enum PreviewKind {
        case jokeCard
        case setListRow
        case photoPage
        case brainstormCard
        case waveform
        case chatBubble
        case homeGrid
        case flameTarget
        case confetti
        case settingsRow
    }

    // MARK: - Standard Tour

    static let standardTour: [TourStep] = [
        TourStep(
            title: "Welcome to BitBinder!",
            subtitle: "Your all-in-one comedy writing toolkit. Let's walk through every corner.",
            icon: "sparkles",
            color: Color.accentColor,
            features: [
                "Write, organize, and refine jokes",
                "Build set lists for every venue",
                "Record yourself practicing material",
                "Brainstorm premises in a freeform space",
                "Back up your paper notebooks in the Photo Notebook",
                "Chat with BitBuddy, your on-device comedy sidekick"
            ],
            howTo: [
                "Swipe left or tap Next to move through the tour",
                "Tap any pill at the top to jump to a section",
                "When you're done, tap Get Started to begin writing"
            ],
            preview: .confetti,
            proTip: "Tap the BitBuddy avatar to slide open the chat pane from any screen."
        ),
        TourStep(
            title: "Home",
            subtitle: "Your dashboard — everything you've written, at a glance.",
            icon: "house.fill",
            color: Color.accentColor,
            features: [
                "Live counts for jokes, sets, recordings, and ideas",
                "One-tap shortcuts to every major section",
                "Recent activity feed so you can pick up where you left off",
                "BitBuddy suggestions tuned to what you were working on"
            ],
            howTo: [
                "Open the app — Home is the first tab",
                "Tap any tile to jump straight into that section",
                "Scroll down to see recent jokes, sets, and recordings"
            ],
            preview: .homeGrid,
            proTip: "Home adapts to show you what matters most based on your recent activity."
        ),
        TourStep(
            title: "Jokes",
            subtitle: "Every punchline you've ever written, organized and searchable.",
            icon: "text.quote",
            color: .indigo,
            features: [
                "Create jokes with titles, setups, punchlines, and tags",
                "Organize into folders and sub-folders",
                "Full-text search across your entire library",
                "Swipe any joke to edit, move, favorite, or delete",
                "Tap to see full detail with rating and performance history",
                "Import bulk material with GagGrabber (top-right icon)"
            ],
            howTo: [
                "Tap the + button in the top-right of the Jokes tab",
                "Type a title and the joke body — tags are optional",
                "Tap Save — it appears instantly in your library"
            ],
            preview: .jokeCard,
            proTip: "Long-press a joke to quickly move it to a folder or add it to a set list."
        ),
        TourStep(
            title: "Set Lists",
            subtitle: "Your lineup for every gig, with timing baked in.",
            icon: "list.bullet.rectangle.portrait.fill",
            color: .purple,
            features: [
                "Create named sets for different venues or show types",
                "Drag jokes in from your library",
                "Reorder with a long-press drag",
                "Per-joke time estimates total up automatically",
                "Use Live Performance mode to present on stage"
            ],
            howTo: [
                "In the Sets tab, tap + to create a new set",
                "Tap Add Jokes and pick from your library",
                "Long-press a row and drag to reorder — done!"
            ],
            preview: .setListRow,
            proTip: "Duplicate a set list to experiment with different orders without losing the original."
        ),
        TourStep(
            title: "Photo Notebook",
            subtitle: "Your paper notebooks, digitized and always in your pocket.",
            icon: "book.closed.fill",
            color: .brown,
            features: [
                "Snap photos of physical notebook pages",
                "Import PDFs of handwritten sets",
                "Organize pages into themed folders",
                "Attach typed notes to any page",
                "Reference any napkin joke or notebook page anywhere"
            ],
            howTo: [
                "Open the Photo Notebook tab, tap +",
                "Choose Scan, Camera, or import a PDF",
                "Tag the page — it's now fully searchable"
            ],
            preview: .photoPage,
            proTip: "Photograph your napkin jokes and notebook pages so you always have a digital backup."
        ),
        TourStep(
            title: "Brainstorm",
            subtitle: "A freeform space for half-baked ideas — no pressure to be funny yet.",
            icon: "lightbulb.fill",
            color: .yellow,
            features: [
                "Jot raw ideas as colorful sticky-note cards",
                "Cards are color-coded so scanning feels visual",
                "Promote any idea to a full joke when it's ready",
                "Trash keeps deleted ideas recoverable for 30 days"
            ],
            howTo: [
                "Tap the Brainstorm tab, then the + button",
                "Type a premise — a sentence or two is enough",
                "When it's ready, tap Promote to turn it into a joke"
            ],
            preview: .brainstormCard,
            proTip: "Ask BitBuddy to brainstorm premises for you — just describe a topic."
        ),
        TourStep(
            title: "Recordings",
            subtitle: "Capture sets as audio, then let GagGrabber turn them into searchable jokes.",
            icon: "waveform",
            color: .red,
            features: [
                "One-tap audio recording from any screen",
                "Auto-transcription runs on-device",
                "GagGrabber pulls individual jokes out of transcribed audio",
                "Tag recordings by venue and date",
                "Clip, trim, and share highlight audio"
            ],
            howTo: [
                "Open the Recordings tab, tap the red record button",
                "Do your set — tap Stop when you're done",
                "Run GagGrabber Extract to pull jokes directly from the transcript"
            ],
            preview: .waveform,
            proTip: "Record your open mic sets and let GagGrabber pull the jokes out of the transcript."
        ),
        TourStep(
            title: "BitBuddy — Your Comedy Sidekick",
            subtitle: "A comedy collaborator that actually knows your app.",
            icon: "sparkles",
            color: Color.accentColor,
            features: [
                "Analyze any joke — structure, timing, and punchline feedback",
                "Generate fresh premises and punchlines on demand",
                "Create sets, folders, and brainstorm cards from chat",
                "Navigate to any screen by asking",
                "Adapts tone to match your voice over time"
            ],
            howTo: [
                "Tap the BitBuddy avatar to slide open the chat pane",
                "Type naturally — \"analyze this joke\" or \"write a set opener\"",
                "Tap any suggested joke to save it to your library"
            ],
            preview: .chatBubble,
            proTip: "Try \"Analyze this joke:\" followed by your material for instant feedback."
        ),
        TourStep(
            title: "Settings & Data",
            subtitle: "Customize the app, protect your work, and manage sync.",
            icon: "gearshape.fill",
            color: .gray,
            features: [
                "Set your display name and daily writing reminder",
                "Toggle Roast Mode for roast-battle material",
                "Enable iCloud Sync to back everything up across devices",
                "Review Data Protection, Trash, and Import History",
                "Revisit this tour anytime from Settings → Show Me Around"
            ],
            howTo: [
                "Open the Settings tab",
                "Tap any row — iCloud Sync is recommended first",
                "Pull down from any settings sub-screen to dismiss"
            ],
            preview: .settingsRow,
            proTip: "Turn on iCloud Sync in Settings → iCloud Sync to never lose a joke."
        ),
        TourStep(
            title: "You're All Set! 🎤",
            subtitle: "You now know every feature in BitBinder. Time to write.",
            icon: "checkmark.seal.fill",
            color: .green,
            features: [
                "Start in the Jokes tab to write your first bit",
                "Build a set list for your next open mic",
                "Chat with BitBuddy whenever inspiration stalls",
                "Revisit this tour anytime from Settings"
            ],
            howTo: [],
            preview: .confetti,
            proTip: nil
        )
    ]

    // MARK: - Roast Mode Tour

    static let roastTour: [TourStep] = [
        TourStep(
            title: "Welcome to the Burn Book 🔥",
            subtitle: "BitBinder is now tuned for roast battles, targeted burns, and lethal closers.",
            icon: "flame.fill",
            color: FirePalette.core,
            features: [
                "Write and organize roast jokes by target",
                "Build roast set lists for battle night",
                "Record and dissect your roast sets",
                "BitBuddy swaps into roast-partner mode for savage material"
            ],
            howTo: [
                "Swipe left or tap Next to keep going",
                "Tap any pill at the top to jump around",
                "When you're ready, Let's Roast closes the tour"
            ],
            preview: .confetti,
            proTip: "You can switch back to standard mode anytime in Settings → Roast Mode."
        ),
        TourStep(
            title: "Roast Targets",
            subtitle: "Every target you're working on, with all the ammo in one place.",
            icon: "flame.fill",
            color: FirePalette.core,
            features: [
                "Create a target for every person, topic, or stereotype",
                "Attach roast jokes directly to the target",
                "Tag each target with traits (tall, vegan, always-late, etc.)",
                "See target-level counts and A-material flags at a glance"
            ],
            howTo: [
                "Open the Roasts tab, tap + → New Target",
                "Name the target and add trait tags",
                "Tap Add Joke and start stacking burns"
            ],
            preview: .flameTarget,
            proTip: "Ask BitBuddy to generate roast lines — just name the target and the traits."
        ),
        TourStep(
            title: "Roast Sets",
            subtitle: "Your battle lineup, sequenced for maximum damage.",
            icon: "list.bullet.rectangle.portrait.fill",
            color: FirePalette.bright,
            features: [
                "Build sets specifically for roast battles",
                "Drag burns in from any target",
                "Per-line timing totals so you fit the format",
                "Live Performance mode for on-stage delivery"
            ],
            howTo: [
                "In Roast Sets, tap + to create a set",
                "Pick a target, then add jokes from its list",
                "Long-press to reorder — save the hardest hit for last"
            ],
            preview: .setListRow,
            proTip: "Prepare multiple sets for different opponents and switch on the fly."
        ),
        TourStep(
            title: "Roast Recordings",
            subtitle: "Audio is the roast's best coach — hear every beat back.",
            icon: "waveform",
            color: FirePalette.ember,
            features: [
                "Record a full roast set with one tap",
                "Auto-transcription pulls every line out",
                "GagGrabber extracts individual burns into the Roasts tab",
                "Tag by opponent and event"
            ],
            howTo: [
                "Open the Recordings tab, tap record",
                "Do the set — the waveform shows you're live",
                "Stop, then run GagGrabber Extract to turn it into searchable burns"
            ],
            preview: .waveform,
            proTip: "Listen back for audience silence — that's where the next rewrite lives."
        ),
        TourStep(
            title: "BitBuddy — Roast Partner",
            subtitle: "BitBuddy's in roast mode too, tuned for sharper, meaner, funnier.",
            icon: "flame.fill",
            color: FirePalette.core,
            features: [
                "Fresh roast lines for any target on demand",
                "Sharpens existing burns — tightens the setup, punches up the turn",
                "Creates roast targets and jokes from chat",
                "Auto-tunes tone: light ribbing vs. take-no-prisoners"
            ],
            howTo: [
                "Tap the BitBuddy avatar to slide open the chat pane",
                "Say \"Give me roast lines for a finance bro\"",
                "Tap any reply to save it as a new burn"
            ],
            preview: .chatBubble,
            proTip: "Start with the traits — \"tall, vegan, CrossFit\" — and the burns write themselves."
        ),
        TourStep(
            title: "Ready to Roast 🔥",
            subtitle: "You know the drill. Go burn some bridges.",
            icon: "checkmark.seal.fill",
            color: FirePalette.bright,
            features: [
                "Start with Roasts to write your first burn",
                "Build a battle set for your next showdown",
                "Use BitBuddy for rapid-fire inspiration",
                "Revisit this tour anytime from Settings"
            ],
            howTo: [],
            preview: .confetti,
            proTip: nil
        )
    ]
}

// MARK: - Preview

#Preview("Standard") {
    NavigationStack {
        ShowMeAroundView()
    }
}

#Preview("Roast Mode") {
    NavigationStack {
        ShowMeAroundView()
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "roastModeEnabled")
    }
}
