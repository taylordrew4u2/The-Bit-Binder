//
//  HomeView.swift
//  thebitbinder
//
//  Home screen - clean dashboard with quick actions and recent work.
//  Native iOS design using system patterns.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - HomeView

struct HomeView: View {
    // Data - filter out soft-deleted items
    @Query(filter: #Predicate<Joke> { !$0.isDeleted }, sort: \Joke.dateModified, order: .reverse) private var allJokes: [Joke]
    @Query(filter: #Predicate<SetList> { !$0.isDeleted }, sort: \SetList.dateModified, order: .reverse) private var allSets: [SetList]
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isDeleted }, sort: \BrainstormIdea.dateCreated, order: .reverse) private var allIdeas: [BrainstormIdea]
    @Query(filter: #Predicate<Recording> { !$0.isDeleted }, sort: \Recording.dateCreated, order: .reverse) private var allRecordings: [Recording]
    @Query(sort: \ImportBatch.importTimestamp, order: .reverse) private var allImports: [ImportBatch]

    // State
    @State private var showAddJoke = false
    @State private var showTalkToText = false
    @State private var showQuickRecord = false
    @AppStorage("roastModeEnabled") private var roastMode = false

    // Cached derived data
    @State private var cachedRecentItems: [RecentItem] = []
    @State private var cachedTodoItems: [TodoItem] = []

    // MARK: - Computed

    private var jokeCount: Int { allJokes.count }
    private var setCount: Int { allSets.count }
    private var ideaCount: Int { allIdeas.count }

    private var importsNeedingReview: [ImportBatch] {
        allImports.filter { $0.reviewQueueCount > 0 }
    }

    // MARK: - Rebuild cached data

    private func rebuildCachedData() {
        // Recent items
        var items: [RecentItem] = []
        
        for joke in allJokes.prefix(3) {
            items.append(RecentItem(
                id: joke.id.uuidString,
                title: joke.title.isEmpty ? String(joke.content.prefix(40)) : joke.title,
                type: .joke,
                date: joke.dateModified,
                joke: joke
            ))
        }
        
        if let set = allSets.first {
            items.append(RecentItem(
                id: set.id.uuidString,
                title: set.name,
                type: .setList,
                date: set.dateModified,
                setList: set
            ))
        }
        
        if let idea = allIdeas.first {
            items.append(RecentItem(
                id: idea.id.uuidString,
                title: String(idea.content.prefix(50)),
                type: .idea,
                date: idea.dateCreated,
                idea: idea
            ))
        }
        
        cachedRecentItems = Array(items.prefix(4))

        // Todo items
        var todos: [TodoItem] = []
        let reviewCount = importsNeedingReview.reduce(0) { $0 + $1.reviewQueueCount }
        
        if reviewCount > 0 {
            todos.append(TodoItem(
                icon: "doc.text.magnifyingglass",
                text: "\(reviewCount) imports need review",
                screen: .jokes
            ))
        }
        
        let unprocessedRecordings = allRecordings.filter { !$0.isProcessed }.count
        if unprocessedRecordings > 0 {
            todos.append(TodoItem(
                icon: "waveform.badge.exclamationmark",
                text: "\(unprocessedRecordings) recordings need cleanup",
                screen: .recordings
            ))
        }
        
        let untaggedJokes = allJokes.filter { $0.tags.isEmpty && $0.category == nil }.count
        if untaggedJokes > 0 {
            todos.append(TodoItem(
                icon: "tag.slash",
                text: "\(untaggedJokes) jokes untagged",
                screen: .jokes
            ))
        }
        
        cachedTodoItems = todos
    }

    // MARK: - Body

    var body: some View {
        List {
            // Quick Actions Section
            Section {
                quickActionsRow
            }
            
            // Stats Section
            Section {
                statsRow
            }
            
            // Recent Section
            if !cachedRecentItems.isEmpty {
                Section {
                    ForEach(cachedRecentItems) { item in
                        recentItemRow(item)
                    }
                } header: {
                    Text("Recent")
                }
            }
            
            // Set Lists Section
            if !allSets.isEmpty {
                Section {
                    ForEach(allSets.prefix(2)) { set in
                        NavigationLink(value: set) {
                            setListRow(set)
                        }
                    }
                    
                    if allSets.count > 2 {
                        NavigationLink {
                            SetListsView()
                        } label: {
                            Text("See All Set Lists")
                                .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    Text("Set Lists")
                }
            }
            
            // Recordings Section
            if !allRecordings.isEmpty {
                Section {
                    ForEach(allRecordings.prefix(3)) { recording in
                        NavigationLink {
                            RecordingDetailView(recording: recording)
                        } label: {
                            recordingRow(recording)
                        }
                    }
                    
                    if allRecordings.count > 3 {
                        NavigationLink {
                            RecordingsView()
                        } label: {
                            Text("See All Recordings")
                                .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    HStack {
                        Text("Recordings")
                        Spacer()
                        NavigationLink {
                            RecordingsView()
                        } label: {
                            Text("\(allRecordings.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // To Do Section
            if !cachedTodoItems.isEmpty {
                Section {
                    ForEach(cachedTodoItems) { item in
                        todoRow(item)
                    }
                } header: {
                    Text("To Do")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: SetList.self) { set in
            SetListDetailView(setList: set)
        }
        .navigationDestination(for: Joke.self) { joke in
            JokeDetailView(joke: joke)
        }
        .sheet(isPresented: $showAddJoke) {
            AddJokeView()
        }
        .sheet(isPresented: $showTalkToText) {
            TalkToTextView(selectedFolder: nil as JokeFolder?)
        }
        .sheet(isPresented: $showQuickRecord) {
            StandaloneRecordingView()
        }
        .onAppear { rebuildCachedData() }
        .onChange(of: allJokes.count) { _, _ in rebuildCachedData() }
        .onChange(of: allSets.count) { _, _ in rebuildCachedData() }
        .onChange(of: allIdeas.count) { _, _ in rebuildCachedData() }
        .onChange(of: allRecordings.count) { _, _ in rebuildCachedData() }
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            // New Joke Button
            Button {
                haptic(.light)
                showAddJoke = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Text("New Joke")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            
            // Quick Idea Button
            Button {
                haptic(.light)
                showTalkToText = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Text("Quick Idea")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(NativeTheme.Colors.fillSecondary)
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            
            // Quick Record Button
            Button {
                haptic(.light)
                showQuickRecord = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Text("Record")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack {
            statItem(count: jokeCount, label: "Jokes", icon: "text.quote")
            Divider()
            statItem(count: setCount, label: "Sets", icon: "list.bullet")
            Divider()
            statItem(count: ideaCount, label: "Ideas", icon: "lightbulb")
        }
        .padding(.vertical, 8)
    }

    private func statItem(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent Item Row

    @ViewBuilder
    private func recentItemRow(_ item: RecentItem) -> some View {
        Group {
            switch item.type {
            case .joke:
                if let joke = item.joke {
                    NavigationLink(value: joke) {
                        recentItemContent(item)
                    }
                }
            case .setList:
                if let set = item.setList {
                    NavigationLink(value: set) {
                        recentItemContent(item)
                    }
                }
            case .idea:
                NavigationLink {
                    if let idea = item.idea {
                        BrainstormDetailView(idea: idea)
                    }
                } label: {
                    recentItemContent(item)
                }
            case .importBatch:
                NavigationLink {
                    ImportBatchHistoryView()
                } label: {
                    recentItemContent(item)
                }
            }
        }
    }

    private func recentItemContent(_ item: RecentItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.icon)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(item.date.relativeHomeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Set List Row

    private func setListRow(_ set: SetList) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text("\(set.totalItemCount) jokes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if set.isFinalized {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    // MARK: - Recording Row

    private func recordingRow(_ recording: Recording) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(durationString(from: recording.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if recording.transcription != nil {
                        Text("Transcribed")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Text(recording.dateCreated.relativeHomeLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func durationString(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Todo Row

    private func todoRow(_ item: TodoItem) -> some View {
        Button {
            if let screen = item.screen {
                NotificationCenter.default.post(
                    name: .navigateToScreen,
                    object: nil,
                    userInfo: ["screen": screen.rawValue]
                )
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.body)
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                Text(item.text)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToScreen = Notification.Name("navigateToScreen")
}

// MARK: - Supporting Types

struct RecentItem: Identifiable {
    let id: String
    let title: String
    let type: ItemType
    let date: Date
    var joke: Joke? = nil
    var setList: SetList? = nil
    var idea: BrainstormIdea? = nil

    enum ItemType {
        case joke, setList, idea, importBatch
        
        var icon: String {
            switch self {
            case .joke: return "text.quote"
            case .setList: return "list.bullet"
            case .idea: return "lightbulb"
            case .importBatch: return "square.and.arrow.down"
            }
        }
    }
}

struct TodoItem: Identifiable {
    var id: String { text }
    let icon: String
    let text: String
    var screen: AppScreen? = nil
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