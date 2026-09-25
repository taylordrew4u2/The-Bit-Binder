import SwiftData
import UIKit
import XCTest
@testable import thebitbinder

/// Exercises Siri's real model and durable save path without touching the app's library.
@MainActor
final class SiriIntegrationTests: XCTestCase {
    func testSpokenJokeIsVisibleFromANewContextAndAfterReopeningStore() throws {
        let storeURL = try makeStoreURL()
        let spokenText = "  My alarm clock needs a snooze button.\nSo do I.  \n"
        let expectedContent = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)

        let savedID = try autoreleasepool {
            let container = try makeContainer(at: storeURL)
            let savedID = try SiriJokeStore.save(content: spokenText, in: container)
            let freshContext = ModelContext(container)
            let saved = try XCTUnwrap(try fetchJoke(id: savedID, in: freshContext))

            XCTAssertEqual(saved.content, expectedContent)
            XCTAssertEqual(saved.title, KeywordTitleGenerator.title(from: expectedContent))
            XCTAssertEqual(saved.wordCount, expectedContent.split(whereSeparator: \.isWhitespace).count)
            XCTAssertFalse(saved.isTrashed)
            XCTAssertNil(saved.deletedDate)
            return savedID
        }

        let reopenedContainer = try makeContainer(at: storeURL)
        let reopenedContext = ModelContext(reopenedContainer)
        let restored = try XCTUnwrap(try fetchJoke(id: savedID, in: reopenedContext))
        XCTAssertEqual(restored.content, expectedContent)
        XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<Joke>()), 1)
    }

    func testWhitespaceOnlySpeechIsRejectedWithoutInsertingAJoke() throws {
        let container = try makeContainer(at: makeStoreURL())

        XCTAssertThrowsError(try SiriJokeStore.save(content: " \n\t ", in: container)) { error in
            guard case SiriJokeCaptureError.emptyContent = error else {
                return XCTFail("Expected an empty-content error, received \(error)")
            }
        }

        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Joke>()), 0)
    }

    func testTemporaryStoreCannotReportASuccessfulSave() throws {
        let schema = Schema([Joke.self, JokeFolder.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        XCTAssertThrowsError(try SiriJokeStore.save(content: "A joke worth keeping.", in: container)) { error in
            guard case SiriJokeCaptureError.persistentStoreUnavailable = error else {
                return XCTFail("Expected a durable-store error, received \(error)")
            }
        }

        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Joke>()), 0)
    }

    func testReadOnlyStoreCannotReportASuccessfulSave() throws {
        let storeURL = try makeStoreURL()
        try autoreleasepool {
            let writableContainer = try makeContainer(at: storeURL)
            _ = try SiriJokeStore.save(content: "An existing joke.", in: writableContainer)
        }
        let container = try makeContainer(at: storeURL, allowsSave: false)

        XCTAssertThrowsError(try SiriJokeStore.save(content: "Another joke.", in: container)) { error in
            guard case SiriJokeCaptureError.persistentStoreUnavailable = error else {
                return XCTFail("Expected a durable-store error, received \(error)")
            }
        }

        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Joke>()), 1)
    }

    func testRepeatingTheSameSpokenTextCreatesSeparateJokes() throws {
        let container = try makeContainer(at: makeStoreURL())
        let content = "My calendar keeps canceling my free time."

        let firstID = try SiriJokeStore.save(content: content, in: container)
        let secondID = try SiriJokeStore.save(content: content, in: container)

        XCTAssertNotEqual(firstID, secondID)
        let storedJokes = try ModelContext(container).fetch(FetchDescriptor<Joke>())
        XCTAssertEqual(storedJokes.count, 2)
        XCTAssertEqual(Set(storedJokes.map(\.id)), Set([firstID, secondID]))
        XCTAssertTrue(storedJokes.allSatisfy { $0.content == content })
    }

    func testSiriSaveDoesNotCommitUnrelatedEditorChanges() throws {
        let storeURL = try makeStoreURL()
        let container = try makeContainer(at: storeURL)
        let editorContext = container.mainContext
        editorContext.autosaveEnabled = false
        let existingJoke = Joke(content: "Original saved content.", title: "Original title")
        editorContext.insert(existingJoke)
        try editorContext.save()

        existingJoke.content = "An unfinished edit in the joke editor."
        existingJoke.title = "Unsaved title"
        let unsavedDraft = Joke(content: "Another unfinished draft.")
        editorContext.insert(unsavedDraft)

        let savedID = try SiriJokeStore.save(content: "A joke spoken to Siri.", in: container)

        XCTAssertTrue(editorContext.hasChanges, "Siri must leave the editor's pending work alone")
        XCTAssertEqual(existingJoke.content, "An unfinished edit in the joke editor.")
        let verificationContainer = try makeContainer(at: storeURL)
        let verificationContext = ModelContext(verificationContainer)
        let original = try XCTUnwrap(try fetchJoke(id: existingJoke.id, in: verificationContext))
        XCTAssertEqual(original.content, "Original saved content.")
        XCTAssertEqual(original.title, "Original title")
        XCTAssertNil(try fetchJoke(id: unsavedDraft.id, in: verificationContext))
        XCTAssertNotNil(try fetchJoke(id: savedID, in: verificationContext))
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<Joke>()), 2)
    }

    func testNavigationCommandsWaitInOrderBeforeAViewIsReady() {
        let router = SiriNavigationRouter()

        router.open(.findJokes(query: "airports"))
        router.open(.sets)
        router.open(.findJokes(query: "family"))

        XCTAssertEqual(router.requests.map(\.destination), [
            .findJokes(query: "airports"),
            .sets,
            .findJokes(query: "family")
        ])
        XCTAssertEqual(Set(router.requests.map(\.id)).count, 3)
    }

    func testFinishingNavigationPreservesCommandsThatArrivedLater() throws {
        let router = SiriNavigationRouter()
        router.open(.findJokes(query: "airports"))
        let displayedRequest = try XCTUnwrap(router.requests.first)

        router.open(.sets)
        router.open(.findJokes(query: "family"))
        let laterRequests = Array(router.requests.dropFirst())
        router.finish(displayedRequest.id)

        XCTAssertEqual(router.requests, laterRequests)
        XCTAssertEqual(router.requests.first?.destination, .sets)
    }

    func testFinishingAnUnknownNavigationRequestDoesNotChangeTheQueue() {
        let router = SiriNavigationRouter()
        router.open(.findJokes(query: "airports"))
        router.open(.sets)
        let pendingRequests = router.requests

        router.finish(UUID())

        XCTAssertEqual(router.requests, pendingRequests)
    }

    func testNavigationWaitsUntilTheHostIsReady() async throws {
        let fixture = try await makePresentationFixture()
        defer { fixture.close() }
        fixture.router.open(.findJokes(query: "airports"))
        fixture.configure(isReady: false)

        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(fixture.root.presentedViewController)
        XCTAssertEqual(fixture.router.requests.count, 1)

        fixture.configure(isReady: true)
        try await waitUntil("Siri destination to appear after readiness") {
            guard let presented = fixture.root.presentedViewController else { return false }
            return presented.view.accessibilityIdentifier == "siri.destination" && !presented.isBeingPresented
        }
        XCTAssertEqual(fixture.router.requests.count, 1, "Presentation must not consume the request")
    }

    func testNavigationPresentsAboveAnExistingDraftWithoutClosingIt() async throws {
        let fixture = try await makePresentationFixture()
        defer { fixture.close() }
        let draft = UIViewController()
        let editor = UITextView()
        editor.text = "An unfinished joke that must remain in the editor."
        draft.view.addSubview(editor)
        draft.modalPresentationStyle = .pageSheet
        fixture.root.present(draft, animated: false)
        try await waitUntil("Draft sheet to appear") {
            draft.presentingViewController != nil && !draft.isBeingPresented
        }

        fixture.router.open(.findJokes(query: "airports"))
        fixture.configure(isReady: true)
        try await waitUntil("Siri destination to appear above the draft") {
            guard let presented = draft.presentedViewController else { return false }
            return presented.view.accessibilityIdentifier == "siri.destination" && !presented.isBeingPresented
        }

        XCTAssertTrue(fixture.root.presentedViewController === draft)
        XCTAssertNotNil(draft.presentingViewController)
        XCTAssertEqual(editor.text, "An unfinished joke that must remain in the editor.")
        XCTAssertEqual(fixture.router.requests.count, 1)
    }

    func testDismissingNavigationConsumesOnlyTheFirstRequestAndShowsTheNext() async throws {
        let fixture = try await makePresentationFixture()
        defer { fixture.close() }
        fixture.router.open(.findJokes(query: "airports"))
        fixture.router.open(.sets)
        let secondRequest = fixture.router.requests[1]
        fixture.configure(isReady: true)
        try await waitUntil("First Siri destination to finish presenting") {
            guard let presented = fixture.root.presentedViewController else { return false }
            return presented.view.accessibilityIdentifier == "siri.destination" && !presented.isBeingPresented
        }
        let firstController = try XCTUnwrap(fixture.root.presentedViewController)

        firstController.dismiss(animated: false)

        try await waitUntil("Next Siri request to replace the dismissed destination") {
            guard let presented = fixture.root.presentedViewController else { return false }
            return fixture.router.requests == [secondRequest]
                && presented !== firstController
                && presented.view.accessibilityIdentifier == "siri.destination"
                && !presented.isBeingPresented
        }
        XCTAssertNil(firstController.presentingViewController)
        XCTAssertEqual(fixture.router.requests.first?.destination, .sets)
    }

    private func makePresentationFixture() async throws -> PresentationFixture {
        try await waitUntil("App window scene to become active") {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        // Presentation tests do not exercise saving. Keep their store in memory:
        // SwiftUI may release its query observers after window teardown returns.
        let schema = Schema([Joke.self, JokeFolder.self, SetList.self, RoastJoke.self, RoastTarget.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let fixture = PresentationFixture(scene: scene, container: container)
        fixture.window.makeKeyAndVisible()
        fixture.root.view.layoutIfNeeded()
        return fixture
    }

    private func waitUntil(_ description: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description)")
        throw PresentationWaitError.timeout
    }

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiriIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("Jokes.store")
    }

    private func makeContainer(at url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema([Joke.self, JokeFolder.self, SetList.self, RoastJoke.self, RoastTarget.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: url,
            allowsSave: allowsSave,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fetchJoke(id: UUID, in context: ModelContext) throws -> Joke? {
        var descriptor = FetchDescriptor<Joke>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private enum PresentationWaitError: Error {
        case timeout
    }

    @MainActor
    private final class PresentationFixture {
        let window: UIWindow
        let root = UIViewController()
        let host = SiriNavigationHost.Controller()
        let router = SiriNavigationRouter()
        let container: ModelContainer
        let preferences = UserPreferences()
        private weak var previousKeyWindow: UIWindow?

        init(scene: UIWindowScene, container: ModelContainer) {
            self.container = container
            previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            window = UIWindow(windowScene: scene)
            window.rootViewController = root
            root.addChild(host)
            root.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            host.didMove(toParent: root)
            configure(isReady: false)
        }

        func configure(isReady: Bool) {
            host.configure(router: router, container: container, preferences: preferences, isReady: isReady)
        }

        func close() {
            configure(isReady: false)
            root.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            previousKeyWindow?.makeKey()
        }
    }
}
