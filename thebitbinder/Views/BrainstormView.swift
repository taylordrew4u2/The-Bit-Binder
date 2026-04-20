//
//  BrainstormView.swift
//  thebitbinder
//
//  Brainstorm tab for quick joke thoughts with zoomable grid
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct BrainstormView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BrainstormIdea> { !$0.isTrashed }, sort: \BrainstormIdea.dateCreated, order: .reverse) private var ideas: [BrainstormIdea]
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("showFullContent") private var showFullContent = true
    @AppStorage("brainstormGridScale") private var brainstormGridScale: Double = 1.0
    
    @State private var showAddSheet = false
    @GestureState private var pinchMagnification: CGFloat = 1.0
    @State private var isRecording = false
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var showingPermissionAlert = false
    
    // Batch select/delete mode
    @State private var isSelectMode = false
    @State private var selectedIdeaIDs: Set<UUID> = []

    // Destructive-action confirmations — tapping Delete on a thought (or on
    // the batch-delete button) stages the action here and presents a
    // confirmation alert before anything is actually removed. Prevents
    // accidental data loss from a fat-fingered context-menu tap.
    @State private var ideaToDelete: BrainstormIdea?
    @State private var showingBatchDeleteConfirmation = false
    
    // Programmatic navigation — avoids NavigationLink gesture conflicts with MagnifyGesture
    @State private var selectedIdea: BrainstormIdea?
    
    // Persistence error surfacing
    @State private var showingTrash = false
    @State private var showTalkToText = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false
    
    // Pinch-to-zoom
    private var effectiveGridScale: CGFloat {
        min(max(CGFloat(brainstormGridScale) * pinchMagnification, 0.5), 2.0)
    }
    
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                brainstormGridScale = Double(min(max(CGFloat(brainstormGridScale) * value.magnification, 0.5), 2.0))
            }
    }
    
    // Grid columns based on scale
    private var columns: [GridItem] {
        let count = max(2, Int(4 / effectiveGridScale))
        return Array(repeating: GridItem(.flexible(), spacing: 0), count: count)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if ideas.isEmpty {
                emptyState
            } else {
                ideaGrid
            }
        }
        .navigationDestination(item: $selectedIdea) { idea in
            BrainstormDetailView(idea: idea)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        toggleRecording()
                    } label: {
                        Label(isRecording ? "Stop Recording" : "Voice Note", systemImage: isRecording ? "stop.circle.fill" : "mic.fill")
                    }
                    Button {
                        showTalkToText = true
                    } label: {
                        Label("Talk to Text", systemImage: "mic.badge.plus")
                    }
                    Section {
                        Button(action: { showFullContent.toggle() }) {
                            Label(showFullContent ? "Show Titles Only" : "Show Full Content",
                                  systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                        }
                        if !ideas.isEmpty {
                            Button {
                                isSelectMode.toggle()
                                if !isSelectMode { selectedIdeaIDs.removeAll() }
                            } label: {
                                Label(isSelectMode ? "Cancel Select" : "Select Multiple",
                                      systemImage: isSelectMode ? "xmark.circle" : "checkmark.circle")
                            }
                        }
                    }
                    Section {
                        Button { showingTrash = true } label: {
                            Label("Trash", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            BrainstormTrashView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddBrainstormIdeaSheet(isVoiceNote: false, initialText: "")
        }
        .sheet(isPresented: $showTalkToText) {
            TalkToTextView(selectedFolder: nil, saveToBrainstorm: true)
        }
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings", role: .none) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in Settings to use voice recording.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        // Single-idea delete confirmation. Bound to `ideaToDelete` being
        // non-nil so we don't need a separate @State Bool.
        .alert("Delete This Thought?", isPresented: Binding(
            get: { ideaToDelete != nil },
            set: { if !$0 { ideaToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { ideaToDelete = nil }
            Button("Delete", role: .destructive) {
                if let idea = ideaToDelete {
                    withAnimation {
                        idea.moveToTrash()
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        print(" [BrainstormView] Failed to save after soft-delete: \(error)")
                        persistenceError = "Could not delete thought: \(error.localizedDescription)"
                        showingErrorAlert = true
                    }
                    ideaToDelete = nil
                }
            }
        } message: {
            Text("This thought will be moved to the Trash. You can restore it from there.")
        }
        // Batch-delete confirmation. Title adapts to count for grammar.
        .alert(
            "Delete \(selectedIdeaIDs.count) Thought\(selectedIdeaIDs.count == 1 ? "" : "s")?",
            isPresented: $showingBatchDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                batchDeleteSelectedIdeas()
            }
        } message: {
            Text("These thoughts will be moved to the Trash. You can restore them from there.")
        }
        .tint(Color.bitbinderAccent)
        .onChange(of: speechManager.isRecording) { oldValue, newValue in
            if oldValue && !newValue && isRecording {
                isRecording = false
            }
        }
        .onChange(of: speechManager.error) { _, newValue in
            if let msg = newValue {
                persistenceError = msg
                showingErrorAlert = true
                speechManager.error = nil
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        BrainstormEmptyState(
            roastMode: roastMode,
            onAddIdea: { showAddSheet = true }
        )
    }
    
    // MARK: - Idea Grid
    private var ideaGrid: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(ideas) { idea in
                        if isSelectMode {
                            ideaSelectableCard(idea: idea)
                        } else {
                            Button {
                                selectedIdea = idea
                            } label: {
                                IdeaCard(idea: idea, scale: effectiveGridScale, roastMode: roastMode, showFullContent: showFullContent)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button {
                                    promoteToJoke(idea)
                                } label: {
                                    Label("Promote to Joke", systemImage: "arrow.up.doc.fill")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    // Stage for confirmation — actual
                                    // moveToTrash happens in the alert handler.
                                    ideaToDelete = idea
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: effectiveGridScale)
            }
            .simultaneousGesture(pinchGesture)
            
            // Batch action bar
            if isSelectMode {
                brainstormBatchActionBar
            }
        }
    }
    
    // MARK: - Batch Select Views
    
    @ViewBuilder
    private func ideaSelectableCard(idea: BrainstormIdea) -> some View {
        let isSelected = selectedIdeaIDs.contains(idea.id)
        Button {
            toggleIdeaSelection(idea)
        } label: {
            ZStack(alignment: .topTrailing) {
                IdeaCard(idea: idea, scale: effectiveGridScale, roastMode: roastMode, showFullContent: showFullContent)
                    .opacity(isSelected ? 0.7 : 1.0)
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color.accentColor : .gray.opacity(0.5))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }

    private var brainstormBatchActionBar: some View {
        HStack(spacing: 16) {
            Button {
                selectedIdeaIDs = Set(ideas.map(\.id))
            } label: {
                Text("Select All")
                    .font(.subheadline)
            }
            
            Spacer()
            
            Text("\(selectedIdeaIDs.count) selected")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(role: .destructive) {
                // Stage for confirmation — actual batch delete happens
                // in the alert handler below.
                showingBatchDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.bold())
            }
            .disabled(selectedIdeaIDs.isEmpty)
            .tint(.accentColor)
            
            Button {
                isSelectMode = false
                selectedIdeaIDs.removeAll()
            } label: {
                Text("Done")
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
    
    private func toggleIdeaSelection(_ idea: BrainstormIdea) {
        if selectedIdeaIDs.contains(idea.id) {
            selectedIdeaIDs.remove(idea.id)
        } else {
            selectedIdeaIDs.insert(idea.id)
        }
    }
    
    private func batchDeleteSelectedIdeas() {
        withAnimation {
            for idea in ideas where selectedIdeaIDs.contains(idea.id) {
                idea.moveToTrash()
            }
            selectedIdeaIDs.removeAll()
            isSelectMode = false
            do {
                try modelContext.save()
            } catch {
                print(" [BrainstormView] Failed to save after batch soft-delete: \(error)")
                persistenceError = "Could not delete thoughts: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
    
    // MARK: - Speech Recognition
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestPermissionAndStartRecording()
        }
    }
    
    private func requestPermissionAndStartRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    if #available(iOS 17.0, *) {
                        AVAudioApplication.requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    self.startRecording()
                                } else {
                                    self.showingPermissionAlert = true
                                }
                            }
                        }
                    } else {
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    self.startRecording()
                                } else {
                                    self.showingPermissionAlert = true
                                }
                            }
                        }
                    }
                default:
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    private func startRecording() {
        speechManager.startRecording()
        isRecording = true
    }
    
    private func stopRecording() {
        speechManager.stopRecording()
        
        // Save the transcribed text as a new idea
        let text = speechManager.transcribedText
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let newIdea = BrainstormIdea(
                content: text,
                colorHex: BrainstormIdea.randomColor(),
                isVoiceNote: true
            )
            modelContext.insert(newIdea)
            do {
                try modelContext.save()
            } catch {
                print(" [BrainstormView] Failed to save voice note idea: \(error)")
                persistenceError = "Could not save voice note: \(error.localizedDescription)"
                showingErrorAlert = true
            }
            speechManager.transcribedText = ""
        }
        
        // Reset recording state with animation so pulsing ring is cleanly removed
        withAnimation(.easeOut(duration: 0.2)) {
            isRecording = false
        }
    }
    
    // MARK: - Promote to Joke
    
    private func promoteToJoke(_ idea: BrainstormIdea) {
        // Create a new joke from the brainstorm idea
        let title = String(idea.content.prefix(60))
        let joke = Joke(content: idea.content, title: title, folder: nil)
        joke.importSource = "Brainstorm"
        
        modelContext.insert(joke)
        
        // Save joke first — only soft-delete the idea once it's confirmed persisted
        do {
            try modelContext.save()
        } catch {
            // Save failed — remove the unsaved joke to avoid a phantom entry
            modelContext.delete(joke)
            print(" [BrainstormView] Failed to save promoted joke: \(error)")
            return
        }
        
        // Only soft-delete the idea after the joke is confirmed saved
        withAnimation {
            idea.moveToTrash()
        }
        
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormView] Joke saved but failed to trash original idea: \(error)")
        }
        
        // Notify user with haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Speech Recognition Manager

final class SpeechRecognitionManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    /// Resolved lazily via `SFSpeechRecognizer.preferred()` so the feature
    /// keeps working when en-US models aren't installed — we fall back to
    /// the user's current locale, then any supported locale.
    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer.preferred()
        r?.delegate = self
        return r
    }()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    // Lazy — only created when recording starts to avoid blocking the main thread on view init
    private var audioEngine: AVAudioEngine?

    @Published var transcribedText = ""
    @Published var isRecording = false
    @Published var error: String?

    /// Whether the manager should keep restarting after iOS's ~60s recognition limit
    private var shouldBeRunning = false
    /// Accumulated text from previous recognition segments (auto-restart appends here)
    private var accumulatedText = ""
    /// Guard against overlapping restart attempts
    private var isRestarting = false
    /// Counts consecutive auto-restarts that produced no new text. Reset
    /// when real speech arrives. Capped by
    /// `SpeechReliability.maxConsecutiveEmptyRestarts`.
    private var consecutiveEmptyRestarts = 0
    /// Snapshot of `transcribedText` when the current segment started.
    private var segmentStartText = ""

    /// Observer for audio session interruptions
    private var interruptionObserver: NSObjectProtocol?
    /// Observer for audio route changes (headphones, Bluetooth).
    private var routeChangeObserver: NSObjectProtocol?
    /// Observer for media-services-reset (audio stack crash).
    private var mediaResetObserver: NSObjectProtocol?

    override init() {
        super.init()
        // Handle audio session interruptions so recognition can resume automatically
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.shouldBeRunning else { return }
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                self.accumulatedText = self.transcribedText
                self.tearDownAudioPipeline(deactivateSession: false)
            case .ended:
                if self.shouldBeRunning {
                    self.isRestarting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.startRecognitionSession()
                    }
                }
            @unknown default:
                break
            }
        }

        // Route changes (headphones unplug / Bluetooth drop / speaker swap)
        // invalidate the current audio tap — the only clean recovery is a
        // fresh engine. Tear down and restart on the same `shouldBeRunning`
        // contract as the interruption path.
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.shouldBeRunning else { return }
            guard let info = notification.userInfo,
                  let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
            switch reason {
            case .oldDeviceUnavailable, .newDeviceAvailable, .override, .routeConfigurationChange:
                self.accumulatedText = self.transcribedText
                self.isRestarting = false
                self.tearDownAudioPipeline(deactivateSession: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + SpeechReliability.restartDelay) { [weak self] in
                    self?.startRecognitionSession()
                }
            default:
                break
            }
        }

        // Media-services-reset — the whole audio stack was rebuilt. Tear
        // down completely and re-activate the session.
        mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.shouldBeRunning else { return }
            self.accumulatedText = self.transcribedText
            self.isRestarting = false
            self.tearDownAudioPipeline(deactivateSession: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + SpeechReliability.restartDelay) { [weak self] in
                self?.startRecognitionSession()
            }
        }
    }

    // MARK: - SFSpeechRecognizerDelegate

    /// If the recognizer goes unavailable mid-session (network dropped on
    /// a server-backed locale, for example), stop cleanly and surface a
    /// friendly message instead of silently producing no text.
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available, shouldBeRunning else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.error = "Speech recognition is temporarily unavailable. Tap Start Recording to try again."
            self.shouldBeRunning = false
            self.isRestarting = false
            self.tearDownAudioPipeline(deactivateSession: true)
            self.isRecording = false
        }
    }
    
    func startRecording() {
        error = nil
        shouldBeRunning = true
        isRestarting = false
        consecutiveEmptyRestarts = 0
        // Don't reset transcribedText — preserve any existing text
        accumulatedText = transcribedText.isEmpty ? "" : transcribedText
        if accumulatedText.isEmpty { transcribedText = "" }

        startRecognitionSession()
    }
    
    /// Internal: starts or restarts one speech recognition session.
    private func startRecognitionSession() {
        guard !isRestarting else { return }
        isRestarting = true
        
        // Clean up any previous session — keep audio session active across restarts
        tearDownAudioPipeline(deactivateSession: false)
        
        guard shouldBeRunning else {
            isRestarting = false
            return
        }
        
        // Attempt to re-resolve a recognizer once if our cached one is nil —
        // models may have been downloaded since the last access.
        if speechRecognizer == nil {
            let resolved = SFSpeechRecognizer.preferred()
            resolved?.delegate = self
            speechRecognizer = resolved
        }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            isRestarting = false
            DispatchQueue.main.async { [weak self] in
                self?.error = "Speech recognition is not available"
                self?.isRecording = false
            }
            return
        }

        // Snapshot text for empty-segment detection.
        segmentStartText = transcribedText
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use .playAndRecord to match the rest of the app (AppDelegate, AudioRecordingService)
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isRestarting = false
            #if DEBUG
            print("Audio session setup failed: \(error)")
            #endif
            DispatchQueue.main.async { [weak self] in
                self?.error = "Microphone unavailable: \(error.localizedDescription)"
                self?.isRecording = false
            }
            return
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        
        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate audio format — some devices/routes report 0 sample rate
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            isRestarting = false
            audioEngine = nil
            #if DEBUG
            print("Audio input format is invalid (sampleRate=\(recordingFormat.sampleRate))")
            #endif
            DispatchQueue.main.async { [weak self] in
                self?.error = "Audio input format is invalid. Please check your microphone."
                self?.isRecording = false
            }
            return
        }
        
        // Install audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            autoreleasepool {
                self?.recognitionRequest?.append(buffer)
            }
        }
        
        // Prepare and start engine BEFORE creating the recognition task
        // so audio buffers flow immediately when the task begins consuming.
        engine.prepare()

        do {
            try engine.start()
        } catch {
            isRestarting = false
            tearDownAudioPipeline(deactivateSession: false)
            #if DEBUG
            print("Audio engine start failed: \(error)")
            #endif
            // Retry once after a brief delay
            if shouldBeRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, self.shouldBeRunning else { return }
                    self.startRecognitionSession()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.error = "Could not start recording: \(error.localizedDescription)"
                    self?.isRecording = false
                }
            }
            return
        }

        isRestarting = false
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                isFinal = result.isFinal
                let newText = result.bestTranscription.formattedString
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.accumulatedText.isEmpty {
                        self.transcribedText = newText
                    } else {
                        self.transcribedText = self.accumulatedText + " " + newText
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError

                if SpeechErrorCode.isCancelled(nsError) {
                    return
                }

                if SpeechErrorCode.isNoSpeechTimeout(nsError) || isFinal {
                    self.scheduleAutoRestart()
                    return
                }

                // Real error — surface a friendly message and stop.
                #if DEBUG
                print(" [SpeechRecognitionManager] Recognition error: \(nsError.domain) code \(nsError.code) — \(error.localizedDescription)")
                #endif
                DispatchQueue.main.async { [weak self] in
                    self?.error = SpeechErrorMapper.userMessage(for: error)
                    self?.isRecording = false
                    self?.isRestarting = false
                }
                return
            }

            // If result is final (recognizer decided speech ended), auto-restart
            if isFinal {
                self.scheduleAutoRestart()
            }
        }
    }

    /// Shared auto-restart path — enforces the empty-restart cap from
    /// `SpeechReliability` so a broken mic can't loop forever. Called
    /// whenever a segment ends cleanly (isFinal) or hits the "no speech"
    /// timeout.
    private func scheduleAutoRestart() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let trimmedNow = self.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedStart = self.segmentStartText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNow == trimmedStart {
                self.consecutiveEmptyRestarts += 1
            } else {
                self.consecutiveEmptyRestarts = 0
            }

            self.accumulatedText = self.transcribedText
            self.isRestarting = false

            guard self.shouldBeRunning else {
                self.isRecording = false
                return
            }

            if self.consecutiveEmptyRestarts >= SpeechReliability.maxConsecutiveEmptyRestarts {
                #if DEBUG
                print(" [SpeechRecognitionManager] Hit empty-restart cap — stopping")
                #endif
                self.shouldBeRunning = false
                self.tearDownAudioPipeline(deactivateSession: true)
                self.isRecording = false
                self.error = "Paused — we didn't hear anything. Tap the mic when you're ready."
                return
            }

            let extra = Double(self.consecutiveEmptyRestarts) * SpeechReliability.restartBackoffStep
            let delay = SpeechReliability.restartDelay + extra
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.startRecognitionSession()
            }
        }
    }
    
    func stopRecording() {
        shouldBeRunning = false
        consecutiveEmptyRestarts = 0
        tearDownAudioPipeline(deactivateSession: true)
        accumulatedText = ""
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
        }
    }
    
    /// Tears down audio engine and recognition without resetting user-facing state.
    private func tearDownAudioPipeline(deactivateSession: Bool) {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // During a restart, finish gracefully; on full stop, cancel.
        if deactivateSession {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionTask = nil
        
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = mediaResetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        shouldBeRunning = false
        recognitionTask?.cancel()
        audioEngine?.stop()
        audioEngine = nil
    }
}

// MARK: - Idea Card (simplified)

struct IdeaCard: View {
    let idea: BrainstormIdea
    let scale: CGFloat
    let roastMode: Bool
    var showFullContent: Bool = true
    
    private var accentColor: Color {
        let hex = idea.colorHex
        if !hex.isEmpty, let parsed = Color(hex: hex) {
            return parsed
        }
        return Color.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thin color accent bar at the top
            accentColor
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
            
            VStack(alignment: .leading, spacing: 6) {
                // Voice indicator (subtle badge)
                if idea.isVoiceNote {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Voice")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(roastMode ? Color.bitbinderAccent.opacity(0.7) : .accentColor.opacity(0.6))
                }
                
                // Content
                if showFullContent {
                    Text(idea.content)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineSpacing(2)
                        .lineLimit(6)
                } else {
                    Text(idea.content.components(separatedBy: .newlines).first ?? idea.content)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Timestamp (minimal)
                Text(idea.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, max(8, 10 * scale))
            .padding(.vertical, max(8, 10 * scale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Brainstorm Empty State

struct BrainstormEmptyState: View {
    var roastMode: Bool = false
    var onAddIdea: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame.fill" : "lightbulb.fill",
            title: roastMode ? "No Ideas Yet" : "No Ideas Yet",
            subtitle: "Tap + to write or use the mic to capture thoughts by voice",
            actionTitle: "Add Idea",
            action: onAddIdea,
            roastMode: roastMode
        )
    }
}

#Preview {
    BrainstormView()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
