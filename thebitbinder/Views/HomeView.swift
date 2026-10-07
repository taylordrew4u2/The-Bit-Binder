//
//  HomeView.swift
//  thebitbinder
//
//  Home screen - fresh, engaging dashboard.
//  Native iOS design: glanceable, motivating, action-oriented.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - HomeView

/// Home is deliberately small: a greeting, the three quick actions, and the
/// Notepad. Browsing and stats live in their own tabs.
struct HomeView: View {
    @Query(filter: #Predicate<Joke> { !$0.isTrashed }, sort: \Joke.dateModified, order: .reverse) private var allJokes: [Joke]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Unified sheet state — only one sheet can present at a time in SwiftUI,
    /// so an optional enum prevents conflicting `isPresented` booleans.
    private enum ActiveSheet: Identifiable {
        case addJoke, talkToText, quickRecord
        var id: Int { hashValue }
    }
    @State private var activeSheet: ActiveSheet?

    // The Notepad lives on Home, under Quick Actions. Same iCloud-synced key
    // as the full-page NotepadView, so both show the same text.
    @AppStorage("notepadText") private var notepadText = ""
    @FocusState private var isNotepadFocused: Bool

    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("userName") private var userName = ""

    // Time-aware greeting
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5:   return "Late night session"
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Night owl mode"
        }
    }
    
    private var greetingName: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return greeting }
        return "\(greeting), \(name)"
    }
    
    var body: some View {
        // The page itself does not scroll: greeting and quick actions stay put,
        // and the Notepad takes every remaining point, scrolling internally when
        // the note outgrows it.
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Greeting Header
            HomeHeader(
                title: greetingName,
                subtitle: allJokes.isEmpty ? "Start with a line. Make it yours." : "Pick up a draft or try a new idea."
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // MARK: - Quick Actions
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                QuickActionTile(
                    title: "New Joke",
                    subtitle: "Write",
                    icon: "square.and.pencil",
                    prominence: .primary
                ) {
                    haptic(.medium)
                    activeSheet = .addJoke
                }

                QuickActionTile(
                    title: "Dictate",
                    subtitle: "Save text",
                    icon: "mic.fill",
                    prominence: .secondary
                ) {
                    haptic(.light)
                    activeSheet = .talkToText
                }

                QuickActionTile(
                    title: "Record",
                    subtitle: "Save audio",
                    icon: "record.circle",
                    prominence: .secondary
                ) {
                    haptic(.light)
                    activeSheet = .quickRecord
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            // MARK: - Notepad
            HStack(alignment: .firstTextBaseline) {
                Text("Notepad")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    NotepadView()
                } label: {
                    Text("Open")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityLabel("Open full-page Notepad")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            LinedNotepadEditor(text: $notepadText, isFocused: $isNotepadFocused)
                .overlay(alignment: .topLeading) {
                    if notepadText.isEmpty {
                        Text("Jot down premises, bits, tags, and to-dos…")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(LinedNotepadEditor.lineSpacing)
                            .padding(.horizontal, LinedNotepadEditor.horizontalInset)
                            .padding(.top, LinedNotepadEditor.topInset)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color(UIColor.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            if isNotepadFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isNotepadFocused = false }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addJoke:
                AddJokeView()
            case .talkToText:
                TalkToTextView(selectedFolder: nil as JokeFolder?, saveToBrainstorm: true)
            case .quickRecord:
                StandaloneRecordingView()
            }
        }

    }
    
}

// MARK: - Home Header

private struct HomeHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quick Action Tile

private struct QuickActionTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    enum Prominence {
        case primary
        case secondary
    }

    let title: String
    let subtitle: String
    let icon: String
    let prominence: Prominence
    let action: () -> Void

    private var foregroundColor: Color {
        prominence == .primary ? ActionColors.foreground : Color.primary
    }

    private var backgroundStyle: AnyShapeStyle {
        switch prominence {
        case .primary:
            return AnyShapeStyle(ActionColors.blue)
        case .secondary:
            return AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(foregroundColor)
                    .background(
                        (prominence == .primary ? Color.white.opacity(0.18) : Color.bitbinderAccent.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)

                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(12)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.bitbinderAccent.opacity(prominence == .primary ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(subtitle)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HomeView()
            .navigationTitle("Home")
    }
    .modelContainer(for: [
        Joke.self, SetList.self, BrainstormIdea.self,
        Recording.self, ImportBatch.self
    ], inMemory: true)
}
