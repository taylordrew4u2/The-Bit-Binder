//
//  ShowMeAroundView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 4/17/26.
//

import SwiftUI

/// Interactive guided tour that walks the user through every screen in the app,
/// explaining what each feature does and how to use it.
struct ShowMeAroundView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode: Bool = false
    @State private var currentStep = 0

    private var steps: [TourStep] {
        if roastMode {
            return TourStep.roastTour
        }
        return TourStep.standardTour
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: Double(currentStep + 1), total: Double(steps.count))
                .tint(roastMode ? .orange : Color.accentColor)
                .padding(.horizontal)
                .padding(.top, 8)

            Text("\(currentStep + 1) of \(steps.count)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            TabView(selection: $currentStep) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer(minLength: 12)

                            // Icon
                            ZStack {
                                Circle()
                                    .fill(step.color.opacity(0.12))
                                    .frame(width: 100, height: 100)
                                Image(systemName: step.icon)
                                    .font(.system(size: 40))
                                    .foregroundColor(step.color)
                            }

                            // Title
                            Text(step.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)

                            // Subtitle
                            Text(step.subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            // Feature bullets
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(step.features, id: \.self) { feature in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(step.color)
                                            .font(.body)
                                        Text(feature)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.horizontal, 32)

                            // Pro tip
                            if let tip = step.proTip {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                    Text("**Pro Tip:** \(tip)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.yellow.opacity(0.08))
                                )
                                .padding(.horizontal, 24)
                            }

                            Spacer(minLength: 80)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            // Navigation buttons
            HStack {
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(roastMode ? Color.orange : Color.bitbinderAccent)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Get Started!")
                            Image(systemName: "checkmark")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationTitle("Show Me Around")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tour Step Model

struct TourStep {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let features: [String]
    let proTip: String?

    // MARK: - Standard Tour

    static let standardTour: [TourStep] = [
        TourStep(
            title: "Welcome to BitBinder!",
            subtitle: "Your all-in-one comedy writing toolkit. Let's walk through everything.",
            icon: "sparkles",
            color: Color.accentColor,
            features: [
                "Write, organize, and refine jokes",
                "Build set lists for your performances",
                "Record yourself practicing material",
                "Brainstorm new ideas and premises",
                "Save notes and photos in your Notebook",
                "Chat with BitBuddy, your AI comedy partner"
            ],
            proTip: "Tap the floating BitBuddy bubble on any screen to open the AI chat."
        ),
        TourStep(
            title: "Home",
            subtitle: "Your dashboard — see everything at a glance.",
            icon: "house.fill",
            color: Color.accentColor,
            features: [
                "Quick stats on your jokes, sets, and recordings",
                "Jump to any section with one tap",
                "See recent activity and suggestions",
                "Your starting point every time you open the app"
            ],
            proTip: "Home adapts to show you what matters most based on your recent activity."
        ),
        TourStep(
            title: "Jokes",
            subtitle: "Where all your material lives.",
            icon: "text.quote",
            color: .indigo,
            features: [
                "Create jokes with titles, punchlines, and tags",
                "Organize jokes into folders",
                "Search and filter your entire library",
                "Swipe to edit, move, or delete jokes",
                "Import jokes from text files using GagGrabber (top-right icon)",
                "Tap any joke to see full details and edit"
            ],
            proTip: "Long-press a joke to quickly move it to a folder or add it to a set list."
        ),
        TourStep(
            title: "Set Lists",
            subtitle: "Build your lineup for any show.",
            icon: "list.bullet.rectangle.portrait.fill",
            color: .purple,
            features: [
                "Create named set lists for different gigs",
                "Add jokes from your library to any set",
                "Drag to reorder your lineup",
                "Track estimated set length",
                "Use Live Performance mode to present on stage"
            ],
            proTip: "Duplicate a set list to experiment with different orders without losing the original."
        ),
        TourStep(
            title: "Notebook",
            subtitle: "Save text notes and scan photos of scribbled ideas.",
            icon: "book.closed.fill",
            color: .brown,
            features: [
                "Quick-save text notes from anywhere",
                "Scan handwritten notes with your camera",
                "All entries are saved to your library automatically",
                "Great for capturing ideas on the go"
            ],
            proTip: "Use the document scanner to photograph napkin jokes — they'll be saved with the image."
        ),
        TourStep(
            title: "Brainstorm",
            subtitle: "A freeform space for premises and half-baked ideas.",
            icon: "lightbulb.fill",
            color: .yellow,
            features: [
                "Jot down raw ideas as colorful cards",
                "No pressure to be funny yet — just capture thoughts",
                "Promote ideas to full jokes when they're ready",
                "Cards are color-coded for easy scanning"
            ],
            proTip: "Ask BitBuddy to brainstorm premises for you — just describe a topic."
        ),
        TourStep(
            title: "Recordings",
            subtitle: "Record yourself practicing or performing.",
            icon: "waveform",
            color: .red,
            features: [
                "One-tap audio recording",
                "Auto-transcription of your recordings",
                "AI can extract jokes from your transcribed audio",
                "Review and refine material from your recordings"
            ],
            proTip: "Record your open mic sets and use AI extraction to pull jokes from the transcript."
        ),
        TourStep(
            title: "BitBuddy — Your AI Partner",
            subtitle: "Tap the floating bubble to chat anytime.",
            icon: "sparkles",
            color: Color.accentColor,
            features: [
                "Analyze any joke — get feedback on structure and punchlines",
                "Generate new premises and punchlines on demand",
                "Create set lists, folders, and brainstorm ideas via chat",
                "Ask about any feature — BitBuddy knows the app",
                "Navigate to any screen by asking BitBuddy"
            ],
            proTip: "Try saying \"Analyze this joke:\" followed by your material for instant feedback."
        ),
        TourStep(
            title: "Settings & Data",
            subtitle: "Customize the app and protect your work.",
            icon: "gearshape.fill",
            color: .gray,
            features: [
                "Set your display name",
                "Toggle Roast Mode for roast battle material",
                "Enable iCloud Sync to back up across devices",
                "View Data Protection options",
                "Access Trash to recover deleted items",
                "Set daily writing reminders"
            ],
            proTip: "Turn on iCloud Sync in Settings → iCloud Sync to never lose a joke."
        ),
        TourStep(
            title: "You're All Set! 🎤",
            subtitle: "You now know every feature in BitBinder.",
            icon: "checkmark.seal.fill",
            color: .green,
            features: [
                "Start writing jokes in the Jokes tab",
                "Build a set list for your next show",
                "Chat with BitBuddy for creative help",
                "Explore at your own pace — you can revisit this tour anytime in Settings"
            ],
            proTip: nil
        )
    ]

    // MARK: - Roast Mode Tour

    static let roastTour: [TourStep] = [
        TourStep(
            title: "Welcome to Roast Mode! 🔥",
            subtitle: "BitBinder is now tuned for roast battles and targeted burns.",
            icon: "flame.fill",
            color: .orange,
            features: [
                "Write and organize roast jokes by target",
                "Build roast set lists for battle night",
                "Record roast sets and practice sessions",
                "Chat with BitBuddy in Roast Mode for savage material"
            ],
            proTip: "You can switch back to standard mode anytime in Settings."
        ),
        TourStep(
            title: "Roasts",
            subtitle: "Your roast material, organized by target.",
            icon: "flame.fill",
            color: .orange,
            features: [
                "Create roast targets (people, topics, stereotypes)",
                "Write jokes attached to specific targets",
                "Browse all your burns in one place",
                "Import roast material from text files"
            ],
            proTip: "Ask BitBuddy to generate roast lines — just name the target."
        ),
        TourStep(
            title: "Roast Sets",
            subtitle: "Build your battle lineup.",
            icon: "list.bullet.rectangle.portrait.fill",
            color: .purple,
            features: [
                "Create set lists specifically for roast battles",
                "Add roast jokes and reorder your lineup",
                "Estimate timing for each round",
                "Use Live Performance mode on stage"
            ],
            proTip: "Prepare multiple sets for different opponents and switch on the fly."
        ),
        TourStep(
            title: "BitBuddy — Roast Partner",
            subtitle: "Your AI is in roast mode too.",
            icon: "flame.fill",
            color: .orange,
            features: [
                "Get roast lines for any target on demand",
                "Analyze and sharpen existing burns",
                "Create roast targets and jokes via chat",
                "BitBuddy adapts tone to match roast style"
            ],
            proTip: "Try \"Give me roast lines for a finance bro\" to see roast mode in action."
        ),
        TourStep(
            title: "Ready to Roast! 🔥",
            subtitle: "You know the drill. Go burn some bridges.",
            icon: "checkmark.seal.fill",
            color: .green,
            features: [
                "Start with the Roasts tab to write material",
                "Build a set for your next battle",
                "Use BitBuddy for rapid-fire inspiration",
                "Revisit this tour anytime in Settings"
            ],
            proTip: nil
        )
    ]
}

#Preview {
    NavigationStack {
        ShowMeAroundView()
    }
}
