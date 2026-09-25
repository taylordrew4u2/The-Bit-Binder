import SwiftUI
import SwiftData

struct SiriDestinationView: View {
    let request: SiriNavigationRouter.Request
    let container: ModelContainer
    let preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss
    @StateObject private var drawer = BitBuddyDrawerController()
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("appTextSize") private var textSize = AppTextSize.system.rawValue

    var body: some View {
        NavigationStack {
            Group {
                switch request.destination {
                case .findJokes(let query):
                    SiriJokeSearchView(query: query)
                case .sets:
                    SetListsView()
                        .navigationTitle("Sets")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("siri.done")
                }
            }
        }
        .bitBuddyDrawer(controller: drawer, roastMode: roastMode)
        .modelContainer(container)
        .environmentObject(preferences)
        .tint(roastMode ? FirePalette.core : .blue)
        .appTextSize(AppTextSize(rawValue: textSize) ?? .system)
    }
}

/// Search every active joke without changing the user's saved library filters.
private struct SiriJokeSearchView: View {
    @Query(filter: #Predicate<Joke> { !$0.isTrashed }, sort: \Joke.dateModified, order: .reverse)
    private var jokes: [Joke]
    @State private var query: String

    init(query: String) {
        _query = State(initialValue: query)
    }

    private var results: [Joke] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return jokes }
        return jokes.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.content.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(results) { joke in
            NavigationLink {
                JokeDetailView(joke: joke)
            } label: {
                JokeRowView(joke: joke, showFullContent: false)
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Search jokes")
        .navigationTitle("Find Jokes")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("siri.jokeSearch")
    }
}
