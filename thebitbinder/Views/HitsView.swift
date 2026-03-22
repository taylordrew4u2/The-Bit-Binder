//
//  HitsView.swift
//  thebitbinder
//
//  Dedicated folder view showing only jokes marked as "Hits"
//

import SwiftUI
import SwiftData

struct HitsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Query(sort: \Joke.dateCreated, order: .reverse)
    private var allJokes: [Joke]
    
    @State private var searchText = ""
    
    private var hitJokes: [Joke] {
        allJokes.filter { $0.isHit && !$0.isDeleted }
    }
    
    private var filteredHits: [Joke] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return hitJokes }
        let lower = trimmed.lowercased()
        return hitJokes.filter {
            $0.content.lowercased().contains(lower) ||
            $0.title.lowercased().contains(lower)
        }
    }
    
    var body: some View {
        Group {
            if filteredHits.isEmpty {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [roastMode ? AppTheme.Colors.roastAccent.opacity(0.3) : Color.yellow.opacity(0.3),
                                             roastMode ? AppTheme.Colors.roastAccent.opacity(0) : Color.yellow.opacity(0)],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                        Image(systemName: roastMode ? "flame" : "star")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                roastMode
                                ? AppTheme.Colors.roastEmberGradient
                                : LinearGradient(colors: [.orange, .yellow],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Text(roastMode ? "No Fire Hits Yet" : "No Hits Yet")
                            .font(.title3.bold())
                            .foregroundColor(roastMode ? .white : .primary)
                        Text("Mark your best jokes as Hits from the joke detail page and they'll show up here.")
                            .font(.subheadline)
                            .foregroundColor(roastMode ? .white.opacity(0.6) : .secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(filteredHits) { joke in
                            NavigationLink(destination: JokeDetailView(joke: joke)) {
                                JokeCardView(joke: joke)
                            }
                            .aspectRatio(1, contentMode: .fit) // Ensure square cells
                            .contextMenu {
                                Button {
                                    joke.isHit = false
                                } label: {
                                    Label("Remove from Hits", systemImage: "star.slash")
                                }
                                Button(role: .destructive) {
                                    // Soft-delete into trash
                                    joke.moveToTrash()
                                } label: {
                                    Label("Delete Joke", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(roastMode ? AppTheme.Colors.roastBackground : Color.clear)
        .navigationTitle(roastMode ? "🔥 The Hits" : "⭐ The Hits")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.paperCream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(roastMode ? .dark : .light, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search hits")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { expandAllJokes.toggle() }) {
                    Label(expandAllJokes ? "Collapse" : "Expand", systemImage: expandAllJokes ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                }
                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : nil)
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
    }
}

#Preview {
    NavigationStack {
        HitsView()
    }
    .modelContainer(for: Joke.self, inMemory: true)
}
