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

enum HomeSection: String, CaseIterable, Hashable {
    case quickActions = "Quick Actions"
    case stats = "At a Glance"
    case recent = "Recent"
    case more = "More"

    // Keep raw values stable for existing saved Home preferences.
    var title: String {
        switch self {
        case .quickActions: return "Quick Actions"
        case .stats: return "Activity"
        case .recent: return "Continue Writing"
        case .more: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .quickActions: return "bolt.fill"
        case .stats: return "chart.bar.fill"
        case .recent: return "clock.fill"
        case .more: return "ellipsis.circle"
        }
    }

    var detail: String {
        switch self {
        case .quickActions: return "Write a joke, dictate an idea, or record audio"
        case .stats: return "Counts for jokes, hits, sets, and weekly work"
        case .recent: return "Recently edited jokes"
        case .more: return "Brainstorm and recording summaries"
        }
    }
}

struct HomeView: View {
    @Query(filter: #Predicate<Joke> { !$0.isTrashed }, sort: \Joke.dateModified, order: .reverse) private var allJokes: [Joke]
    @Query(filter: #Predicate<SetList> { !$0.isTrashed }) private var allSets: [SetList]
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isTrashed }) private var allIdeas: [BrainstormIdea]
    @Query(filter: #Predicate<Recording> { !$0.isTrashed }) private var allRecordings: [Recording]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Unified sheet state — only one sheet can present at a time in SwiftUI,
    /// so an optional enum prevents conflicting `isPresented` booleans.
    private enum ActiveSheet: Identifiable {
        case addJoke, talkToText, quickRecord
        var id: Int { hashValue }
    }
    @State private var activeSheet: ActiveSheet?

    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("homeSelectedSections") private var selectedSectionsRaw = ""

    
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
    
    private var hitsCount: Int { allJokes.filter { $0.isHit }.count }
    private var thisWeekCount: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allJokes.filter { $0.dateCreated >= weekAgo }.count
    }

    private var recentJokes: [Joke] {
        var seen = Set<UUID>()
        var result: [Joke] = []
        for joke in allJokes where seen.insert(joke.id).inserted {
            result.append(joke)
            if result.count == 3 { break }
        }
        return result
    }

    private var selectedHomeSections: Set<HomeSection> {
        guard !selectedSectionsRaw.isEmpty else {
            return Set(HomeSection.allCases)
        }
        let sections = Set(selectedSectionsRaw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) })
        return sections.isEmpty ? Set(HomeSection.allCases) : sections
    }

    var body: some View {
        List {
            // MARK: - Greeting Header
            Section {
                HomeHeader(
                    title: greetingName,
                    subtitle: allJokes.isEmpty ? "Start with a line. Make it yours." : "Pick up a draft or try a new idea."
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
            }

            if selectedHomeSections.contains(.quickActions) || allJokes.isEmpty {
                // MARK: - Quick Actions
                Section {
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
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            // MARK: - Recent Activity
            if selectedHomeSections.contains(.recent) && !recentJokes.isEmpty {
                Section("Continue Writing") {
                    ForEach(recentJokes) { joke in
                        NavigationLink(value: joke) {
                            HStack(spacing: 12) {
                                // Hit indicator
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(joke.isHit ? Color.bitbinderAccent : Color(UIColor.separator))
                                    .frame(width: 4, height: 36)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(joke.title.isEmpty ? String(joke.content.prefix(50)) : joke.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                                    HStack(spacing: 8) {
                                        Text(joke.dateModified.relativeHomeLabel)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if joke.isHit {
                                            Label("Hit", systemImage: "star.fill")
                                                .font(.caption2.weight(.medium))
                                                .foregroundColor(Color.bitbinderAccent)
                                        }
                                    }
                                }

                                Spacer(minLength: 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            
            // Activity supports the work above and is hidden for a new library.
            if selectedHomeSections.contains(.stats) && !allJokes.isEmpty {
                Section("Activity") {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 16))
                    layout {
                        ActivityMetric(label: "Jokes", value: allJokes.count)
                        ActivityMetric(label: "Hits", value: hitsCount)
                        ActivityMetric(label: "Sets", value: allSets.count)
                        ActivityMetric(label: "This Week", value: thisWeekCount)
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: - Ideas & Recordings Summary
            if selectedHomeSections.contains(.more) && (allIdeas.count > 0 || allRecordings.count > 0) {
                Section("Library") {
                    if allIdeas.count > 0 {
                        NavigationLink {
                            BrainstormView()
                                .navigationTitle("Brainstorm")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            LabeledContent {
                                Text("\(allIdeas.count)")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text("Brainstorm Ideas")
                                } icon: {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(Color.bitbinderAccent)
                                }
                            }
                        }
                    }
                    
                    if allRecordings.count > 0 {
                        NavigationLink {
                            RecordingsView()
                                .navigationTitle("Recordings")
                                .navigationBarTitleDisplayMode(.large)
                        } label: {
                            LabeledContent {
                                Text("\(allRecordings.count)")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text("Recordings")
                                } icon: {
                                    Image(systemName: "waveform")
                                        .foregroundColor(Color.bitbinderAccent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationDestination(for: Joke.self) { joke in
            JokeDetailView(joke: joke)
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

// MARK: - Activity Metric

private struct ActivityMetric: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Date Helper

extension Date {
    var relativeHomeLabel: String {
        let cal = Calendar.current
        let now = Date()
        let diff = cal.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let d = diff.day, d >= 2 {
            return "\(d)d ago"
        } else if let d = diff.day, d == 1 {
            return "Yesterday"
        } else if let h = diff.hour, h >= 1 {
            return "\(h)h ago"
        } else if let m = diff.minute, m >= 1 {
            return "\(m)m ago"
        } else {
            return "Just now"
        }
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
