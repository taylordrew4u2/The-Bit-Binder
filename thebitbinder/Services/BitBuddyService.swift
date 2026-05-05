//
//  BitBuddyService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/18/26.
//

import Foundation
import AVFoundation

/// BitBuddy — Your on-device comedy writing assistant.
/// 100% local and rule-based. NEVER uses the GagGrabber extraction providers.
/// GagGrabber's on-device extraction providers are reserved exclusively for
/// file imports and are token-gated via `AIExtractionToken`.
/// Powered by a 93-intent router that covers all 11 app sections.
@MainActor
final class BitBuddyService: NSObject, ObservableObject {
    static let shared = BitBuddyService()
    
    // MARK: - Dependencies
    private let authService = AuthService.shared
    private var backend: BitBuddyBackend
    private let intentRouter = BitBuddyIntentRouter.shared
    
    // MARK: - State
    @Published var isLoading = false
    /// Human-readable status message shown in the chat while BitBuddy is working.
    /// Updated at each processing stage so the user knows the app hasn't frozen.
    @Published var statusMessage: String = ""
    /// Whether the backend is reachable. Always `true` for the local engine.
    @Published var isConnected: Bool
    @Published private(set) var backendName: String
    /// Published so the UI can navigate to the section an intent targets.
    @Published var pendingNavigation: BitBuddySection? = nil
    /// Last structured response for action dispatch.
    @Published private(set) var lastActions: [BitBuddyAction] = []
    /// Joke the user is currently viewing — populates dataContext.focusedJoke.
    var focusedJoke: BitBuddyJokeSummary?
    /// Message to auto-send when the chat view opens (e.g. "Punch up this joke").
    /// BitBuddyChatView consumes and clears this on appear.
    var pendingMessage: String?
    /// Current page the user is on. Set by ContentView/MainTabView whenever
    /// the active tab changes. BitBuddy uses this so questions like
    /// "what is this", "help me here", or "what can I do on this page" get
    /// page-aware answers instead of generic responses.
    @Published private(set) var currentPage: BitBuddySection?

    /// Updates the page context. Idempotent — safe to call on every tab change.
    func setCurrentPage(_ page: BitBuddySection?) {
        guard currentPage != page else { return }
        currentPage = page
    }

    private let maxConversationTurns = 16
    /// Maximum number of old conversations to retain in memory
    private let maxRetainedConversations = 3
    private var conversationId: String?
    private var turnsByConversation: [String: [BitBuddyTurn]] = [:]
    private var recentJokeProvider: (() -> [BitBuddyJokeSummary])?
    
    /// Stores a pending navigation section that BitBuddy suggested but is waiting
    /// for the user to confirm (e.g. "yes", "take me there").
    private var awaitingNavigationConfirmation: BitBuddySection?
    
    /// Actions that modify user data and must NOT be dispatched from a route-only
    /// match (i.e. when the backend response is conversational text, not a structured
    /// JSON payload with validated fields).
    private static let dataMutatingActions: Set<String> = [
        "add_joke", "save_joke", "save_joke_in_folder", "duplicate_joke",
        "edit_joke", "rename_joke", "delete_joke", "restore_deleted_joke",
        "delete_brainstorm_note", "delete_set_list", "delete_recording",
        "delete_folder", "remove_joke_from_set", "reject_imported_joke",
        "add_brainstorm_note", "add_roast_joke", "create_roast_target",
        "create_set_list", "create_folder",
        "save_notebook_text", "approve_imported_joke",
    ]
    
    private override init() {
        let selectedBackend = BitBuddyBackendFactory.makeBackend()
        self.backend = selectedBackend
        self.backendName = selectedBackend.backendName
        self.isConnected = selectedBackend.isAvailable
        super.init()
    }
    
    func refreshBackend() {
        let newBackend = BitBuddyBackendFactory.makeBackend()
        backend = newBackend
        backendName = newBackend.backendName
        isConnected = newBackend.isAvailable
    }

    // MARK: - Public API

    /// Optional hook so BitBuddy can ground responses in current app joke data.
    ///
    /// - Important: Callers **must** use `[weak self]` (or `[weak viewModel]`)
    ///   capture semantics in the closure to avoid retain cycles.
    ///   `BitBuddyService` holds a strong reference to the closure for
    ///   the lifetime of the service.
    func registerJokeDataProvider(_ provider: @escaping () -> [BitBuddyJokeSummary]) {
        recentJokeProvider = provider
    }
    
    /// Send a text message and get a response from the local BitBuddy backend.
    func sendMessage(_ message: String) async throws -> String {
        try await authService.ensureAuthenticated()
        
        isLoading = true
        statusMessage = "Thinking…"
        defer {
            isLoading = false
            statusMessage = ""
        }
        
        lastActions = []
        pendingNavigation = nil
        
        // Check if the user is confirming a previously suggested navigation
        let lowerMessage = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let confirmationPhrases = ["yes", "yeah", "yep", "sure", "ok", "okay", "take me there",
                                   "go there", "let's go", "do it", "go ahead", "bring me there",
                                   "navigate", "open it", "show me", "yes please", "yea"]
        if let pendingSection = awaitingNavigationConfirmation,
           confirmationPhrases.contains(where: { lowerMessage.contains($0) }) {
            awaitingNavigationConfirmation = nil
            pendingNavigation = pendingSection
            let displayText = "Taking you there now! 👍"
            let activeConversationId = conversationId ?? UUID().uuidString
            conversationId = activeConversationId
            appendTurn(.init(role: .user, text: message), conversationId: activeConversationId)
            appendTurn(.init(role: .assistant, text: displayText), conversationId: activeConversationId)
            return displayText
        }
        awaitingNavigationConfirmation = nil
        
        let activeConversationId = conversationId ?? UUID().uuidString
        conversationId = activeConversationId
        appendTurn(.init(role: .user, text: message), conversationId: activeConversationId)
        
        let session = BitBuddySessionSnapshot(
            conversationId: activeConversationId,
            turns: turnsByConversation[activeConversationId] ?? []
        )
        
        // Route the intent
        let routeResult = intentRouter.route(message)
        
        // Update status based on what we're about to do
        if let route = routeResult {
            statusMessage = statusHint(for: route.intent.id)
        }
        
        var dataContext = BitBuddyDataContext()
        dataContext.userName = UserDefaults.standard.string(forKey: "userName") ?? "Comedian"
        dataContext.recentJokes = recentJokeProvider?() ?? []
        dataContext.focusedJoke = focusedJoke
        dataContext.routedIntent = routeResult
        // Prefer the routed section (the user's intent), fall back to the
        // page they're currently viewing so generic asks like "help me here"
        // resolve to the right context.
        dataContext.activeSection = routeResult?.section ?? currentPage
        dataContext.currentPage = currentPage
        dataContext.isRoastMode = UserDefaults.standard.bool(forKey: "roastModeEnabled")
        
        do {
            let rawResponse: String
            statusMessage = statusMessage.isEmpty ? "Thinking…" : statusMessage
            rawResponse = try await backend.send(message: message, session: session, dataContext: dataContext)
            
            // Process the response through our JSON handler (handles
            // any future structured-JSON backends). For the local
            // rule-based backend this is a no-op pass-through.
            let displayText = handleBitBuddyResponse(rawResponse)
            
            // Dispatch the structured action from the routed intent.
            // The local backend returns plain text (never JSON), so
            // handleBitBuddyResponse's JSON path never fires. We
            // dispatch directly from the route result instead.
            //
            // IMPORTANT: Only dispatch non-mutating actions from the route
            // result alone. Data-mutating actions (save_joke, delete_joke, etc.)
            // require a validated structured payload — executing them from a
            // conversational response with no payload causes empty saves,
            // "missing joke text" errors, and bad UI loops.
            if let route = routeResult {
                if !Self.dataMutatingActions.contains(route.intent.id) {
                    var intentAction: [String: Any] = [
                        "type": route.intent.id
                    ]
                    // Forward extracted entities so action handlers can use
                    // names, folders, targets, etc. from the user's message.
                    for (key, value) in route.extractedEntities {
                        intentAction[key] = value
                    }
                    executeBitBuddyAction(intentAction)
                }
                
                // Store navigation target for confirmation — BitBuddy will ask
                // the user before navigating. The user can say "yes" or "take me there"
                // in their next message to trigger the navigation.
                if route.category == .navigation && route.section != .bitbuddy {
                    awaitingNavigationConfirmation = route.section
                }
                
                // For import_file / import_image, offer navigation to Jokes
                if route.intent.id == "import_file" || route.intent.id == "import_image" {
                    awaitingNavigationConfirmation = .importFlow
                }
            }
            
            appendTurn(.init(role: .assistant, text: displayText), conversationId: activeConversationId)
            isConnected = true
            return displayText
        } catch {
            isConnected = false
            throw error
        }
    }
    
    /// Start a new conversation.
    func startNewConversation() {
        // Remove the old conversation's turns to free memory
        if let oldId = conversationId {
            turnsByConversation.removeValue(forKey: oldId)
        }
        conversationId = nil
        // isConnected stays true — the local backend is always available.
        pendingNavigation = nil
        awaitingNavigationConfirmation = nil
        lastActions = []
        
        // Evict oldest conversations if we're retaining too many
        while turnsByConversation.count > maxRetainedConversations {
            // Remove the conversation with the fewest turns (likely the oldest/least active)
            if let leastActiveKey = turnsByConversation.min(by: { $0.value.count < $1.value.count })?.key {
                turnsByConversation.removeValue(forKey: leastActiveKey)
            } else {
                break
            }
        }
    }
    
    /// Clear the pending navigation (call after the UI has acted on it).
    func clearPendingNavigation() {
        pendingNavigation = nil
    }
    
    /// Expose the intent router for UI components that want to show suggestions.
    var router: BitBuddyIntentRouter { intentRouter }
    
    /// Analyze a single joke and return category, tags, difficulty, and humor rating.
    /// Local-only heuristic fallback keeps this feature working without external APIs.
    func analyzeJoke(_ jokeText: String) async throws -> JokeAnalysis {
        try await authService.ensureAuthenticated()
        
        let lower = jokeText.lowercased()
        let category = inferCategory(from: lower)
        let tags = inferTags(from: lower)
        let difficulty = inferDifficulty(from: jokeText)
        let humorRating = inferHumorRating(from: jokeText)
        
        return JokeAnalysis(
            category: category,
            tags: tags,
            difficulty: difficulty,
            humorRating: humorRating
        )
    }
    
    /// Analyze multiple jokes and group them by category.
    /// Updates the original `Joke` objects in-place so changes are visible
    /// to SwiftData without creating detached copies.
    func analyzeMultipleJokes(_ jokes: [Joke]) async throws -> [String: [Joke]] {
        var categorized: [String: [Joke]] = [:]
        
        for joke in jokes {
            let analysis = try await analyzeJoke(joke.content)
            
            // Update the original in-place — no detached copies
            joke.category = analysis.category
            joke.tags = analysis.tags
            joke.difficulty = analysis.difficulty
            joke.humorRating = analysis.humorRating
            
            categorized[analysis.category, default: []].append(joke)
        }
        
        return categorized
    }
    
    /// Get organization suggestions for a set of jokes using local reasoning.
    func getOrganizationSuggestions(for jokes: [Joke]) async throws -> String {
        try await authService.ensureAuthenticated()
        
        let grouped = Dictionary(grouping: jokes) { inferCategory(from: $0.content.lowercased()) }
        let lines = grouped.keys.sorted().map { category in
            let count = grouped[category]?.count ?? 0
            return "• \(category): \(count) joke\(count == 1 ? "" : "s")"
        }
        
        return """
        Here’s a local organization pass:
        \(lines.joined(separator: "\n"))
        
        Suggested order:
        1. Start with the most accessible observational material.
        2. Group darker or weirder bits once trust is built.
        3. Save act-out or callback-heavy material for later in the set.
        """
    }
    
    // MARK: - Audio Recording/Playback
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordedAudioURL: URL? = nil
    
    func cleanupAudioResources() {
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        // NOTE: recordedAudioURL is NOT deleted here.
        // stopRecording() returns the URL and clears the reference.
        // Callers are responsible for the file after stopRecording().
        // Deleting it here would silently lose unprocessed recordings.
        recordedAudioURL = nil
    }
    
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("bitbuddy_recording.m4a")
        recordedAudioURL = fileURL
        
        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        let url = recordedAudioURL
        recordedAudioURL = nil
        return url
    }
    
    func playAudio(from url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
    
    func playAudio(data: Data) throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
    
    func sendAudio(_ audioURL: URL) async throws -> String {
        try await authService.ensureAuthenticated()
        
        isLoading = true
        statusMessage = "Processing audio…"
        defer {
            isLoading = false
            statusMessage = ""
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw BitBuddyError.invalidResponse
        }
        
        // Transcribe the audio using on-device speech recognition
        statusMessage = "Transcribing your recording…"
        let transcriptionService = AudioTranscriptionService.shared
        do {
            let result = try await transcriptionService.transcribe(audioURL: audioURL)
            let transcript = result.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                return try await sendMessage("I recorded something but couldn't make out any words. Could you help me brainstorm instead?")
            }
            // Send the actual transcribed text for analysis
            statusMessage = "Analyzing your idea…"
            return try await sendMessage("Analyze this idea I just recorded: \(transcript)")
        } catch {
            print(" [BitBuddy] Transcription failed: \(error.localizedDescription)")
            // Fall back gracefully — the user still gets a response
            return try await sendMessage("I recorded an audio note but transcription wasn't available. Can you help me brainstorm some ideas?")
        }
    }
    
    // MARK: - JSON Response Handling
    
    /// Handles structured JSON responses from BitBuddy and executes any actions
    /// - Parameter rawResponse: The raw response string from the LLM
    /// - Returns: The cleaned response text to display in the chat UI
    func handleBitBuddyResponse(_ rawResponse: String) -> String {
        print(" [BitBuddy] Raw response: \(rawResponse.prefix(120))")

        // Try to parse as JSON — only structured JSON responses can trigger actions.
        // Plain-text conversational responses are returned as-is with NO action dispatch.
        guard let jsonData = rawResponse.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return Self.stripMarkdown(rawResponse)
        }
        
        // Extract the response text
        let responseText = jsonObject["response"] as? String ?? rawResponse
        
        // Handle single action — requires valid JSON with explicit action payload
        if let actionDict = jsonObject["action"] as? [String: Any] {
            // Validate that data-mutating actions have required fields before dispatch
            if validateActionPayload(actionDict) {
                executeBitBuddyAction(actionDict)
            } else {
                print(" [BitBuddy] Skipping action dispatch — payload validation failed")
            }
        }
        
        // Handle multiple actions
        if let actionsArray = jsonObject["actions"] as? [[String: Any]] {
            for actionDict in actionsArray {
                if validateActionPayload(actionDict) {
                    executeBitBuddyAction(actionDict)
                } else {
                    print(" [BitBuddy] Skipping action in array — payload validation failed")
                }
            }
        }
        
        return Self.stripMarkdown(responseText)
    }

    private static func stripMarkdown(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "###", with: "")
        s = s.replacingOccurrences(of: "##", with: "")
        s = s.replacingOccurrences(of: "# ", with: "")
        return s
    }

    /// Validates that a data-mutating action payload contains the required fields.
    /// Non-mutating actions (navigation, status checks) pass through without validation.
    private func validateActionPayload(_ action: [String: Any]) -> Bool {
        guard let actionType = action["type"] as? String else { return false }
        
        // Non-mutating actions don't need payload validation
        guard Self.dataMutatingActions.contains(actionType) else { return true }
        
        // Specific field requirements for data-mutating actions
        switch actionType {
        case "add_joke", "save_joke", "save_joke_in_folder":
            guard let joke = action["joke"] as? String, !joke.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print(" [BitBuddy] Blocked \(actionType): missing or empty 'joke' field")
                return false
            }
        case "add_brainstorm_note", "save_notebook_text":
            guard let text = action["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print(" [BitBuddy] Blocked \(actionType): missing or empty 'text' field")
                return false
            }
        case "add_roast_joke":
            guard let joke = action["joke"] as? String, !joke.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print(" [BitBuddy] Blocked \(actionType): missing or empty 'joke' field")
                return false
            }
        default:
            // Other mutating actions pass if they have any non-type key
            break
        }
        return true
    }
    
    /// Executes a single BitBuddy action.
    ///
    /// Actions fall into four buckets:
    /// 1. **Data creation** — posts a notification with payload; the UI layer
    ///    (BitBuddyChatView) handles SwiftData persistence via ModelContext.
    /// 2. **Navigation** — sets `pendingNavigation` so the chat dismisses and
    ///    the user lands on the correct app section.
    /// 3. **Direct execution** — inline work like toggling settings, syncing,
    ///    clearing cache.
    /// 4. **Backend-handled** — the text response from the backend *is* the
    ///    action (joke analysis, premise generation, etc.). No extra dispatch.
    private func executeBitBuddyAction(_ action: [String: Any]) {
        guard let actionType = action["type"] as? String else {
            print(" [BitBuddy] Invalid action - missing type")
            return
        }
        
        print(" [BitBuddy] Executing action: \(actionType)")
        
        // Build a structured action for downstream consumers
        var params: [String: String] = [:]
        for (key, value) in action where key != "type" {
            if let str = value as? String { params[key] = str }
        }
        let structuredAction = BitBuddyAction(type: actionType, parameters: params)
        lastActions.append(structuredAction)
        
        // Dispatch by intent category
        switch actionType {

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Jokes — Data Creation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "add_joke", "save_joke":
            handleAddJokeAction(action)
        case "save_joke_in_folder":
            handleAddJokeAction(action) // folder param handled inside
        case "duplicate_joke":
            handleAddJokeAction(action) // creates a copy as a new joke
        case "create_folder":
            handleCreateFolderAction(action)

        // MARK: Jokes — Navigate to section for context-dependent actions
        case "edit_joke", "rename_joke", "delete_joke", "restore_deleted_joke",
             "mark_hit", "unmark_hit", "add_tags", "remove_tags",
             "move_joke_folder", "rename_folder", "delete_folder",
             "share_joke", "merge_jokes":
            print(" [BitBuddy] \(actionType) → navigating to Jokes for user to act")
            pendingNavigation = .jokes

        // MARK: Jokes — Search / Filter → Navigate to Jokes
        case "search_jokes", "filter_jokes_recent", "filter_jokes_by_folder",
             "filter_jokes_by_tag", "list_hits":
            print(" [BitBuddy] \(actionType) → navigating to Jokes section")
            pendingNavigation = .jokes

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Brainstorm — Data Creation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "add_brainstorm_note":
            handleAddBrainstormNoteAction(action)
        case "voice_capture_idea":
            // Navigate to Brainstorm where voice capture UI lives
            print(" [BitBuddy] voice_capture_idea → navigating to Brainstorm")
            pendingNavigation = .brainstorm

        // MARK: Brainstorm — Context-dependent → Navigate
        case "edit_brainstorm_note", "delete_brainstorm_note",
             "promote_idea_to_joke", "search_brainstorm", "group_brainstorm_topics":
            print(" [BitBuddy] \(actionType) → navigating to Brainstorm")
            pendingNavigation = .brainstorm

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Set Lists — Data Creation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "create_set_list":
            handleCreateSetListAction(action)

        // MARK: Set Lists — Context-dependent → Navigate
        case "rename_set_list", "delete_set_list", "add_joke_to_set",
             "remove_joke_from_set", "reorder_set", "shuffle_set",
             "present_set", "find_set_list":
            print(" [BitBuddy] \(actionType) → navigating to Set Lists")
            pendingNavigation = .setLists

        // MARK: Set Lists — Analysis (handled by backend text, no navigation)
        case "estimate_set_time", "suggest_set_opener", "suggest_set_closer":
            // The backend's text response IS the action result
            print(" [BitBuddy] \(actionType) — handled by backend response text")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Recordings — Direct + Navigate
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "start_recording":
            print(" [BitBuddy] start_recording → navigating to Recordings")
            pendingNavigation = .recordings
        case "stop_recording":
            print(" [BitBuddy] stop_recording")

        // MARK: Recordings — Context-dependent → Navigate
        case "rename_recording", "delete_recording", "play_recording",
             "transcribe_recording", "search_transcripts", "clip_recording",
             "attach_recording_to_set", "review_set_from_recording":
            print(" [BitBuddy] \(actionType) → navigating to Recordings")
            pendingNavigation = .recordings

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: BitBuddy Writing — Backend-Handled
        // The backend's text response IS the action. No extra dispatch.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "analyze_joke", "improve_joke", "generate_premise", "generate_joke",
             "summarize_style", "suggest_unexplored_topics", "find_similar_jokes",
             "shorten_joke", "expand_joke", "generate_tags_for_joke",
             "rewrite_in_my_style", "crowdwork_help", "roast_line_generation",
             "compare_versions", "extract_premises_from_notes", "explain_comedy_theory":
            print(" [BitBuddy] \(actionType) — handled by backend response text")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Notebook — Data Creation + Navigation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "open_notebook":
            pendingNavigation = .notebook
        case "save_notebook_text":
            handleSaveNotebookTextAction(action)
        case "attach_photo_to_notebook":
            // Photo attachment needs the Notebook UI
            print(" [BitBuddy] attach_photo_to_notebook → navigating to Notebook")
            pendingNavigation = .notebook
        case "search_notebook":
            print(" [BitBuddy] search_notebook → navigating to Notebook")
            pendingNavigation = .notebook

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Roast Mode — Direct + Data Creation + Navigation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "toggle_roast_mode":
            let current = UserDefaults.standard.bool(forKey: "roastModeEnabled")
            UserDefaults.standard.set(!current, forKey: "roastModeEnabled")
            print(" [BitBuddy] toggle_roast_mode → \(!current)")
        case "create_roast_target":
            handleCreateRoastTargetAction(action)
        case "add_roast_joke":
            handleAddRoastJokeAction(action)
        case "search_roasts", "create_roast_set", "present_roast_set",
             "attach_photo_to_target":
            print(" [BitBuddy] \(actionType) → navigating to Roast Mode")
            pendingNavigation = .roastMode

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Import — Direct + Navigation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "import_file":
            // No longer triggers file picker — backend text response explains GagGrabber
            print(" [BitBuddy] import_file → explained GagGrabber in text response")
        case "import_image":
            // No longer triggers file picker — backend text response explains GagGrabber
            print(" [BitBuddy] import_image → explained GagGrabber in text response")
        case "review_import_queue", "approve_imported_joke", "reject_imported_joke",
             "edit_imported_joke", "show_import_history":
            // Import review lives inside Jokes
            print(" [BitBuddy] \(actionType) → navigating to Jokes (import review)")
            pendingNavigation = .importFlow
        case "check_import_limit":
            // Handled by backend text response (shows remaining grabs)
            print(" [BitBuddy] check_import_limit — handled by backend response text")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Sync — Direct Execution
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "check_sync_status":
            print(" [BitBuddy] check_sync_status → navigating to Sync settings")
            pendingNavigation = .sync
        case "sync_now":
            print(" [BitBuddy] sync_now — triggering manual sync")
            Task { @MainActor in await iCloudSyncService.shared.syncNow() }
        case "toggle_icloud_sync":
            let syncService = iCloudSyncService.shared
            Task { @MainActor in
                if syncService.isSyncEnabled {
                    syncService.disableiCloudSync()
                } else {
                    await syncService.enableiCloudSync()
                }
            }
            print(" [BitBuddy] toggle_icloud_sync — toggled")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Settings — Direct Execution + Navigation
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "export_all_jokes", "export_recordings":
            print(" [BitBuddy] \(actionType) → navigating to Settings")
            pendingNavigation = .settings
        case "clear_cache":
            print(" [BitBuddy] clear_cache — clearing temp files")
            clearTempFiles()

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // MARK: Help — Navigation + Backend
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        case "open_help_faq":
            pendingNavigation = .help
        case "explain_feature":
            // Backend text response IS the explanation
            print(" [BitBuddy] explain_feature — handled by backend response text")

        default:
            print(" [BitBuddy] Unknown action type: \(actionType)")
        }
    }
    
    // MARK: - Action Handlers (Notification Publishers)
    
    /// Posts a notification to create a brainstorm note. The UI layer
    /// handles SwiftData persistence via its active ModelContext.
    private func handleAddBrainstormNoteAction(_ action: [String: Any]) {
        let text = (action["text"] as? String)
            ?? (action["quoted_value"] as? String)
            ?? (action["value"] as? String)
        guard let noteText = text, !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print(" [BitBuddy] add_brainstorm_note missing text — navigating to Brainstorm instead")
            pendingNavigation = .brainstorm
            return
        }
        print(" [BitBuddy] Publishing add_brainstorm_note for UI persistence")
        NotificationCenter.default.post(
            name: .bitBuddyAddBrainstormNote,
            object: nil,
            userInfo: ["text": noteText]
        )
    }
    
    /// Posts a notification to create a set list.
    private func handleCreateSetListAction(_ action: [String: Any]) {
        let name = (action["set_name"] as? String)
            ?? (action["name"] as? String)
            ?? (action["quoted_value"] as? String)
            ?? (action["value"] as? String)
        guard let setName = name, !setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print(" [BitBuddy] create_set_list missing name — navigating to Set Lists instead")
            pendingNavigation = .setLists
            return
        }
        print(" [BitBuddy] Publishing create_set_list for UI persistence")
        NotificationCenter.default.post(
            name: .bitBuddyCreateSetList,
            object: nil,
            userInfo: ["name": setName]
        )
    }
    
    /// Posts a notification to create a joke folder.
    private func handleCreateFolderAction(_ action: [String: Any]) {
        let name = (action["folder"] as? String)
            ?? (action["name"] as? String)
            ?? (action["quoted_value"] as? String)
            ?? (action["value"] as? String)
        guard let folderName = name, !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print(" [BitBuddy] create_folder missing name — navigating to Jokes instead")
            pendingNavigation = .jokes
            return
        }
        print(" [BitBuddy] Publishing create_folder for UI persistence")
        NotificationCenter.default.post(
            name: .bitBuddyCreateFolder,
            object: nil,
            userInfo: ["name": folderName]
        )
    }
    
    /// Posts a notification to create a roast target.
    private func handleCreateRoastTargetAction(_ action: [String: Any]) {
        let name = (action["target"] as? String)
            ?? (action["name"] as? String)
            ?? (action["quoted_value"] as? String)
            ?? (action["value"] as? String)
        guard let targetName = name, !targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print(" [BitBuddy] create_roast_target missing name — navigating to Roast Mode instead")
            pendingNavigation = .roastMode
            return
        }
        let notes = action["notes"] as? String
        print(" [BitBuddy] Publishing create_roast_target for UI persistence")
        NotificationCenter.default.post(
            name: .bitBuddyCreateRoastTarget,
            object: nil,
            userInfo: [
                "name": targetName,
                "notes": notes as Any
            ]
        )
    }
    
    /// Posts a notification to add a roast joke.
    private func handleAddRoastJokeAction(_ action: [String: Any]) {
        let jokeText = (action["joke"] as? String)
            ?? (action["text"] as? String)
            ?? (action["quoted_value"] as? String)
        guard let content = jokeText, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print(" [BitBuddy] add_roast_joke missing joke text — navigating to Roast Mode instead")
            pendingNavigation = .roastMode
            return
        }
        let target = action["target"] as? String
        print(" [BitBuddy] Publishing add_roast_joke for UI persistence")
        NotificationCenter.default.post(
            name: .bitBuddyAddRoastJoke,
            object: nil,
            userInfo: [
                "joke": content,
                "target": target as Any
            ]
        )
    }
    
    /// Posts a notification to save notebook text.
    private func handleSaveNotebookTextAction(_ action: [String: Any]) {
        let text = (action["text"] as? String)
            ?? (action["quoted_value"] as? String)
            ?? (action["value"] as? String)
        guard let noteText = text, !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print(" [BitBuddy] save_notebook_text missing text — navigating to Notebook instead")
            pendingNavigation = .notebook
            return
        }
        print(" [BitBuddy] Publishing save_notebook_text for UI persistence")
        NotificationCenter.default.post(
            name: .bitBuddySaveNotebookText,
            object: nil,
            userInfo: ["text": noteText]
        )
    }
    
    /// Handles the add_joke action — publishes the joke text so the UI layer
    /// can create a proper SwiftData `Joke` with the active `ModelContext`.
    ///
    ///   This used to write a `.txt` file to Documents/Jokes, which was
    /// invisible to the SwiftData-backed UI. Fixed to publish via
    /// `NotificationCenter` so any listening view can persist it correctly.
    private func handleAddJokeAction(_ action: [String: Any]) {
        guard let jokeText = action["joke"] as? String, !jokeText.isEmpty else {
            print(" [BitBuddy] add_joke action missing joke text")
            return
        }

        let folder = action["folder"] as? String
        print(" [BitBuddy] Publishing add_joke for UI persistence")
        print(" [BitBuddy] Joke content: \(jokeText.prefix(50))...")

        NotificationCenter.default.post(
            name: .bitBuddyAddJoke,
            object: nil,
            userInfo: [
                "jokeText": jokeText,
                "folder": folder as Any
            ]
        )
    }
    
    // MARK: - Private helpers
    
    /// Returns a user-facing status hint for the given intent so the chat
    /// shows what BitBuddy is working on instead of a generic spinner.
    private func statusHint(for intentId: String) -> String {
        switch intentId {
        // Joke writing / analysis
        case "analyze_joke":                     return "Analyzing your joke…"
        case "improve_joke":                     return "Crafting improvements…"
        case "generate_premise":                 return "Brainstorming premises…"
        case "generate_joke":                    return "Writing jokes…"
        case "shorten_joke":                     return "Tightening the punchline…"
        case "expand_joke":                      return "Expanding the bit…"
        case "rewrite_in_my_style":              return "Studying your style…"
        case "find_similar_jokes":               return "Searching your library…"
        case "generate_tags_for_joke":           return "Generating tags…"
        case "compare_versions":                 return "Comparing versions…"
        case "extract_premises_from_notes":      return "Extracting premises…"
        case "explain_comedy_theory":            return "Looking that up…"
        case "summarize_style":                  return "Analyzing your style…"
        case "suggest_unexplored_topics":        return "Scanning for fresh topics…"
        // Roast
        case "roast_line_generation":            return "Loading the burns…"
        case "crowdwork_help":                   return "Prepping crowd work…"
        // Set lists
        case "create_set_list":                  return "Building your set list…"
        case "estimate_set_time":                return "Calculating set time…"
        case "suggest_set_opener", "suggest_set_closer": return "Picking the perfect bit…"
        case "reorder_set":                      return "Reordering your set…"
        // Recordings
        case "transcribe_recording":             return "Transcribing audio…"
        // Import
        case "import_file":                      return "Preparing file import…"
        // Sync
        case "sync_now":                         return "Syncing…"
        case "check_sync_status":                return "Checking sync status…"
        // Search
        case _ where intentId.hasPrefix("search"), _ where intentId.hasPrefix("filter"), _ where intentId.hasPrefix("find"):
            return "Searching…"
        default:
            return "Thinking…"
        }
    }
    
    /// Removes all files from the app's temporary directory.
    /// Safe to call at any time — only affects throwaway caches/scratch files.
    private func clearTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }
        var removed = 0
        for file in files {
            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                // Temp files in use — skip silently
            }
        }
        print(" [BitBuddy] Cleared \(removed) temp file(s)")
    }
    
    private func appendTurn(_ turn: BitBuddyTurn, conversationId: String) {
        var turns = turnsByConversation[conversationId] ?? []
        turns.append(turn)
        if turns.count > maxConversationTurns {
            turns = Array(turns.suffix(maxConversationTurns))
        }
        turnsByConversation[conversationId] = turns

        // Periodic eviction: trim stale conversations even between explicit
        // startNewConversation() calls so the dictionary can't grow unbounded.
        if turnsByConversation.count > maxRetainedConversations + 1 {
            let activeKey = conversationId
            while turnsByConversation.count > maxRetainedConversations + 1 {
                // Evict the conversation with the fewest turns, skipping the active one
                if let leastActiveKey = turnsByConversation
                    .filter({ $0.key != activeKey })
                    .min(by: { $0.value.count < $1.value.count })?.key {
                    turnsByConversation.removeValue(forKey: leastActiveKey)
                } else {
                    break
                }
            }
        }
    }
    
    private func inferCategory(from lower: String) -> String {
        if lower.contains("dating") || lower.contains("girlfriend") || lower.contains("boyfriend") || lower.contains("wife") || lower.contains("husband") {
            return "Relationships"
        }
        if lower.contains("work") || lower.contains("office") || lower.contains("boss") || lower.contains("coworker") || lower.contains("job") {
            return "Work"
        }
        if lower.contains("family") || lower.contains("mom") || lower.contains("dad") || lower.contains("parent") || lower.contains("child") {
            return "Family"
        }
        if lower.contains("airplane") || lower.contains("airport") || lower.contains("uber") || lower.contains("driving") || lower.contains("travel") {
            return "Travel"
        }
        if lower.contains("phone") || lower.contains("app") || lower.contains("internet") || lower.contains("ai") || lower.contains("tech") {
            return "Technology"
        }
        if lower.contains("body") || lower.contains("doctor") || lower.contains("therapy") || lower.contains("anxiety") || lower.contains("gym") {
            return "Personal"
        }
        return "Observational"
    }
    
    private func inferTags(from lower: String) -> [String] {
        let candidatePairs: [(String, String)] = [
            ("dating", "dating"), ("relationship", "relationship"), ("work", "work"),
            ("family", "family"), ("travel", "travel"), ("airport", "airport"),
            ("tech", "tech"), ("phone", "phone"), ("gym", "gym"),
            ("therapy", "therapy"), ("money", "money"), ("food", "food")
        ]
        let tags = candidatePairs.compactMap { lower.contains($0.0) ? $0.1.capitalized : nil }
        return Array(tags.prefix(3))
    }
    
    private func inferDifficulty(from text: String) -> String {
        if text.count < 60 { return "Easy" }
        if text.count < 180 { return "Medium" }
        return "Hard"
    }
    
    private func inferHumorRating(from text: String) -> Int {
        let lengthBonus = min(text.count / 40, 3)
        let punctuationBonus = text.contains("?") || text.contains("!") ? 1 : 0
        return min(5 + lengthBonus + punctuationBonus, 9)
    }
}

// MARK: - Models

struct JokeAnalysis {
    let category: String
    let tags: [String]
    let difficulty: String
    let humorRating: Int
}

// MARK: - Errors

enum BitBuddyError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from BitBuddy"
        case .apiError(_, let message):
            return message
        case .parseError:
            return "BitBuddy couldn't understand that request"
        case .notConnected:
            return "BitBuddy isn't available right now"
        }
    }
}

extension BitBuddyService: AVAudioRecorderDelegate {}
extension BitBuddyService: AVAudioPlayerDelegate {}
