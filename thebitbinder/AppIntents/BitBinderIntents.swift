import AppIntents
import SwiftData

struct SaveJokeIntent: AppIntent {
    static let title: LocalizedStringResource = "Save a Joke"
    static let description = IntentDescription("Save a spoken or written joke to your BitBinder library.")
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Joke", requestValueDialog: "What’s the joke?")
    var content: String

    @Dependency private var modelContainer: ModelContainer

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$content) as a joke")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else {
            throw $content.needsValueError("What joke would you like to save?")
        }

        _ = try await SiriJokeStore.save(content: normalizedContent, in: modelContainer)
        return .result(dialog: "Saved your joke in BitBinder.")
    }
}

struct FindJokesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Jokes"
    static let description = IntentDescription("Open BitBinder and search your joke library.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Search", requestValueDialog: "What would you like to find?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find jokes matching \(\.$query)")
    }

    func perform() async throws -> some IntentResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw $query.needsValueError("What would you like to find in your jokes?")
        }

        await SiriNavigationRouter.shared.open(.findJokes(query: normalizedQuery))
        return .result()
    }
}

struct OpenSetsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sets"
    static let description = IntentDescription("Open your set lists in BitBinder.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    func perform() async throws -> some IntentResult {
        await SiriNavigationRouter.shared.open(.sets)
        return .result()
    }
}

struct BitBinderShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveJokeIntent(),
            phrases: [
                "Save a joke in \(.applicationName)",
                "Add a joke to \(.applicationName)",
                "Capture a joke in \(.applicationName)"
            ],
            shortTitle: "Save a Joke",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: FindJokesIntent(),
            phrases: [
                "Find jokes in \(.applicationName)",
                "Search my jokes in \(.applicationName)"
            ],
            shortTitle: "Find Jokes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenSetsIntent(),
            phrases: [
                "Open my sets in \(.applicationName)",
                "Show my set lists in \(.applicationName)"
            ],
            shortTitle: "Open Sets",
            systemImageName: "list.number"
        )
    }
}
