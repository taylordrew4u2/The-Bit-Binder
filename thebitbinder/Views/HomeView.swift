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
        case .quickActions: return "New joke, capture idea, and record set"
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

    // Cached stats — rebuilt via .task(id:) when allJokes changes
    @State private var cachedHitsCount: Int = 0
    @State private var cachedThisWeekCount: Int = 0
    
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
    
    // Stats — use cached values; rebuilt by .task(id:) below
    private var hitsCount: Int { cachedHitsCount }
    private var thisWeekCount: Int { cachedThisWeekCount }

    /// Invalidation key for stats — changes when joke count changes.
    private var statsKey: Int { allJokes.count }
    
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
                    subtitle: allJokes.isEmpty ? "Let's get your first joke on paper" : motivationalSubtitle,
                    jokeCount: allJokes.count,
                    hitCount: hitsCount,
                    thisWeekCount: thisWeekCount
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
            }

            if selectedHomeSections.contains(.quickActions) {
                // MARK: - Quick Actions
                Section {
                    HStack(spacing: 10) {
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
                            title: "Capture",
                            subtitle: "Idea",
                            icon: "mic.fill",
                            prominence: .secondary
                        ) {
                            haptic(.light)
                            activeSheet = .talkToText
                        }

                        QuickActionTile(
                            title: "Record",
                            subtitle: "Set",
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

            if selectedHomeSections.contains(.stats) {
                // MARK: - At a Glance Stats
                Section("At a Glance") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(
                            label: "Jokes",
                            value: allJokes.count,
                            icon: "text.quote",
                            tint: .accentColor
                        )
                        StatCard(
                            label: "Hits",
                            value: hitsCount,
                            icon: "star.fill",
                            tint: Color.accentColor
                        )
                        StatCard(
                            label: "Sets",
                            value: allSets.count,
                            icon: "list.bullet.rectangle.portrait",
                            tint: Color.accentColor
                        )
                        StatCard(
                            label: "This Week",
                            value: thisWeekCount,
                            icon: "flame.fill",
                            tint: Color.accentColor
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            // MARK: - Recent Activity
            if selectedHomeSections.contains(.recent) && !recentJokes.isEmpty {
                Section("Recent") {
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
                                        .lineLimit(1)

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
            
            // MARK: - Ideas & Recordings Summary
            if selectedHomeSections.contains(.more) && (allIdeas.count > 0 || allRecordings.count > 0) {
                Section("More") {
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
        .readableWidth()
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
        .task(id: statsKey) {
            cachedHitsCount = allJokes.filter { $0.isHit }.count
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            cachedThisWeekCount = allJokes.filter { $0.dateCreated >= weekAgo }.count
        }
    }
    
    private var motivationalSubtitle: String {
        if thisWeekCount > 0 {
            return "\(thisWeekCount) new joke\(thisWeekCount == 1 ? "" : "s") this week — keep it going"
        } else if hitsCount > 0 {
            return "You've got \(hitsCount) hit\(hitsCount == 1 ? "" : "s") in your set"
        } else {
            return "\(allJokes.count) joke\(allJokes.count == 1 ? "" : "s") and counting"
        }
    }

}

// MARK: - Home Header

private struct HomeHeader: View {
    let title: String
    let subtitle: String
    let jokeCount: Int
    let hitCount: Int
    let thisWeekCount: Int

    private var progressLabel: String {
        if thisWeekCount > 0 {
            return "\(thisWeekCount) this week"
        }
        if hitCount > 0 {
            return "\(hitCount) hit\(hitCount == 1 ? "" : "s")"
        }
        return "\(jokeCount) saved"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "text.quote")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.bitbinderAccent)
                    .frame(width: 42, height: 42)
                    .background(Color.bitbinderAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                HomeMetricPill(text: progressLabel, icon: thisWeekCount > 0 ? "flame.fill" : "star.fill")

                if jokeCount == 0 {
                    HomeMetricPill(text: "Start fresh", icon: "sparkles")
                } else {
                    HomeMetricPill(text: "\(jokeCount) joke\(jokeCount == 1 ? "" : "s")", icon: "rectangle.stack.fill")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.bitbinderAccent.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct HomeMetricPill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundColor(Color.bitbinderAccent)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.bitbinderAccent.opacity(0.10), in: Capsule())
    }
}

// MARK: - Quick Action Tile

private struct QuickActionTile: View {
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
        prominence == .primary ? .white : Color.bitbinderAccent
    }

    private var backgroundStyle: AnyShapeStyle {
        switch prominence {
        case .primary:
            return AnyShapeStyle(Color.bitbinderAccent)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .opacity(prominence == .primary ? 0.86 : 0.72)
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

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: Int
    let icon: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
                Spacer()
            }

            Text("\(value)")
                .font(.title2.weight(.bold))
                .foregroundColor(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
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
