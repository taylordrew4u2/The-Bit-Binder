import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Joke> { $0.isDeleted == true }, sort: \Joke.deletedDate, order: .reverse)
    private var trashedJokes: [Joke]

    @AppStorage("showFullContent") private var showFullContent = true
    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false
    @State private var jokeToDelete: Joke?
    @State private var showingDeleteOneAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false

    private var filteredTrash: [Joke] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trashedJokes }
        let lower = trimmed.lowercased()
        return trashedJokes.filter {
            $0.title.lowercased().contains(lower) ||
            $0.content.lowercased().contains(lower)
        }
    }

    var body: some View {
        Group {
            if filteredTrash.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Trash is Empty",
                    subtitle: "Deleted jokes appear here until you empty trash."
                )
            } else {
                List {
                    ForEach(filteredTrash) { joke in
                        NavigationLink(destination: JokeDetailView(joke: joke)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                                    .font(.headline)
                                if showFullContent {
                                    Text(joke.content)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let deletedDate = joke.deletedDate {
                                    Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                jokeToDelete = joke
                                showingDeleteOneAlert = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                restoreJoke(joke)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AppTheme.Colors.success)
                        }
                        .contextMenu {
                            Button {
                                restoreJoke(joke)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                jokeToDelete = joke
                                showingDeleteOneAlert = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search trash")
        .toolbar {
            if !trashedJokes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingEmptyTrashAlert = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("Delete Forever?", isPresented: $showingDeleteOneAlert) {
            Button("Cancel", role: .cancel) { jokeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let joke = jokeToDelete {
                    permanentlyDeleteJoke(joke)
                    jokeToDelete = nil
                }
            }
        } message: {
            Text("This joke will be permanently deleted. This cannot be undone.")
        }
        .alert("Empty Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently deletes all \(trashedJokes.count) joke\(trashedJokes.count == 1 ? "" : "s") in trash. This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    // MARK: - Actions

    private func restoreJoke(_ joke: Joke) {
        joke.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to restore joke: \(error)")
            persistenceError = "Could not restore joke: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func permanentlyDeleteJoke(_ joke: Joke) {
        modelContext.delete(joke)
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to permanently delete joke: \(error)")
            persistenceError = "Could not delete joke: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func emptyTrash() {
        for joke in trashedJokes {
            modelContext.delete(joke)
        }
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to empty trash: \(error)")
            persistenceError = "Could not empty trash: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
    .modelContainer(for: Joke.self, inMemory: true)
}
