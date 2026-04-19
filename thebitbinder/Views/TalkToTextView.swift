//  TalkToTextView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/1/26.
//

import SwiftUI
import Speech
import AVFoundation
import AVFAudio

struct TalkToTextView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    let selectedFolder: JokeFolder?
    let saveToBrainstorm: Bool
    
    @State private var transcribedText = ""
    @State private var isRecording = false
    @State private var permissionStatus: PermissionStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var errorMessage: String?
    @State private var showSavedConfirmation = false
    @State private var isSaving = false
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    init(selectedFolder: JokeFolder?, saveToBrainstorm: Bool = false) {
        self.selectedFolder = selectedFolder
        self.saveToBrainstorm = saveToBrainstorm
    }
    
    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
    }

    private enum MicPermissionStatus {
        case undetermined
        case granted
        case denied
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header - Mic icon with animation
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isRecording ? .red : .accentColor)
                            .symbolEffect(.variableColor, isActive: isRecording)
                    }
                    
                    Text(isRecording ? "Listening..." : "Ready")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top, 20)
                    
                    // Live transcription area
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Transcription")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            if !transcribedText.isEmpty {
                                Button("Clear") {
                                    transcribedText = ""
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            }
                        }
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(UIColor.secondarySystemBackground))
                            
                            if transcribedText.isEmpty && !isRecording {
                                Text("Your transcription will appear here...")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(14)
                            }
                            
                            ScrollView {
                                Text(transcribedText)
                                    .font(.body)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(minHeight: 200)
                    }
                    .padding(.horizontal, 20)
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Controls
                    VStack(spacing: 16) {
                        // Main record button
                        Button {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        } label: {
                            Label(isRecording ? "Stop" : "Start Recording",
                                  systemImage: isRecording ? "stop.fill" : "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRecording ? .red : .accentColor)
                        .controlSize(.large)
                        .disabled(permissionStatus == .denied)
                        
                        // Save button (only show when there's text and not recording)
                        if !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                            Button {
                                saveItem()
                            } label: {
                                HStack(spacing: 10) {
                                    if isSaving {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    Text(saveToBrainstorm ? "Save Idea" : "Save Joke")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(saveToBrainstorm ? .blue : .blue)
                            .controlSize(.large)
                            .disabled(isSaving)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            if isRecording {
                                stopRecording()
                            }
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    checkPermissions()
                }
                .onDisappear {
                    // Ensure audio pipeline is fully torn down when leaving this view
                    if isRecording {
                        isRecording = false
                    }
                    speechRecognizer.stopTranscribing()
                }
                .alert("Permissions Required", isPresented: $showingPermissionAlert) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                } message: {
                    Text("Microphone and Speech Recognition permissions are required for Talk-to-Text Joke. Please enable them in Settings.")
                }
                .onChange(of: speechRecognizer.transcribedText) { _, newValue in
                    transcribedText = newValue
                }
                .onChange(of: speechRecognizer.error) { _, newValue in
                    errorMessage = newValue
                }
                .overlay {
                    if showSavedConfirmation {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(saveToBrainstorm ? .blue : .blue)
                            Text(saveToBrainstorm ? "Idea Saved!" : "Joke Saved!")
                                .font(.headline)
                        }
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showSavedConfirmation)
            }
        }
    }
    
    private func checkPermissions() {
        Task {
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            let audioStatus = currentMicPermission()
            
            if speechStatus == .authorized && audioStatus == .granted {
                await MainActor.run {
                    permissionStatus = .authorized
                }
            } else if speechStatus == .denied || audioStatus == .denied {
                await MainActor.run {
                    permissionStatus = .denied
                    showingPermissionAlert = true
                }
            } else {
                // Request permissions
                await requestPermissions()
            }
        }
    }

    private func currentMicPermission() -> MicPermissionStatus {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .undetermined
            }
        }
    }
    
    private func requestPermissions() async {
        // Request speech recognition permission
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        // Request microphone permission
        let micGranted = await requestMicPermission()
        
        await MainActor.run {
            if speechGranted && micGranted {
                permissionStatus = .authorized
            } else {
                permissionStatus = .denied
                showingPermissionAlert = true
            }
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    private func startRecording() {
        // If permissions haven't been determined yet, request them and auto-start on success
        if permissionStatus == .notDetermined {
            Task {
                await requestPermissions()
                // After permissions are resolved, start recording automatically if granted
                if permissionStatus == .authorized {
                    beginRecordingSession()
                }
            }
            return
        }
        
        guard permissionStatus == .authorized else {
            showingPermissionAlert = true
            return
        }
        
        beginRecordingSession()
    }
    
    /// Actually kicks off the speech recognition session (call only when permissions are confirmed).
    private func beginRecordingSession() {
        errorMessage = nil
        isRecording = true
        speechRecognizer.startTranscribing()
    }
    
    private func stopRecording() {
        isRecording = false
        speechRecognizer.stopTranscribing()
    }
    
    private func saveItem() {
        if saveToBrainstorm {
            saveBrainstormIdea()
        } else {
            saveJoke()
        }
    }
    
    private func saveBrainstormIdea() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Cannot save an empty idea."
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        // Create the brainstorm idea
        let idea = BrainstormIdea(
            content: text,
            colorHex: BrainstormIdea.randomColor(),
            isVoiceNote: true
        )
        
        modelContext.insert(idea)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [TalkToTextView] Brainstorm idea saved — id: \(idea.id)")
            #endif
            
            isSaving = false
            showSavedConfirmation = true
            
            // Brief confirmation then dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } catch {
            isSaving = false
            #if DEBUG
            print(" [TalkToTextView] Failed to save brainstorm idea: \(error)")
            #endif
            errorMessage = "Could not save idea: \(error.localizedDescription)"
        }
    }
    
    private func saveJoke() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Cannot save an empty joke."
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        // Create the joke
        let title = generateTitle(from: text)
        let newJoke = Joke(
            content: text,
            title: title,
            folder: selectedFolder
        )
        
        modelContext.insert(newJoke)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [TalkToTextView] Joke saved — id: \(newJoke.id), title: \"\(title)\", folder: \(selectedFolder?.name ?? "none")")
            #endif
            
            // Notify other views that the joke database changed (matches AddJokeView pattern)
            NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
            
            isSaving = false
            showSavedConfirmation = true
            
            // Brief confirmation then dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } catch {
            isSaving = false
            #if DEBUG
            print(" [TalkToTextView] Failed to save joke: \(error)")
            #endif
            errorMessage = "Could not save joke: \(error.localizedDescription)"
        }
    }
    
    private func generateTitle(from text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let titleWords = words.prefix(5).joined(separator: " ")
        if words.count > 5 {
            return titleWords + "..."
        }
        return titleWords
    }
}

// MARK: - Speech Recognizer
//
// Simplified, reliable speech recognition based on Apple's canonical
// SFSpeechRecognizer sample. Uses a single long-lived AVAudioEngine and
// avoids layered defensive logic that can interfere with recognition.
// NOT @MainActor-isolated — audio tap callback fires on real-time audio
// thread and recognition result handler is called from an internal queue.
// All UI-facing @Published updates are explicitly dispatched to main.
final class SpeechRecognizer: NSObject, ObservableObject {
    @Published var transcribedText = ""
    @Published var error: String?
    @Published var isTranscribing = false

    // New engine created per session — AVAudioEngine doesn't always restart
    // cleanly after stop(), so a fresh instance is the most reliable approach.
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// Text already finalised from previous recognition segments. Used when the
    /// recognizer auto-restarts (~60s limit) so the user doesn't lose text.
    private var accumulatedText = ""
    /// True while the user wants to be recording. Controls auto-restart.
    private var shouldBeRunning = false
    /// Prevents overlapping startRecognitionSession calls.
    private var isStarting = false
    /// Observer token for audio session interruptions.
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        shouldBeRunning = false
        recognitionTask?.cancel()
        audioEngine?.stop()
        audioEngine = nil
    }

    // MARK: - Interruption Handling

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            accumulatedText = transcribedText
            tearDown(deactivateSession: false)
            isTranscribing = false
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && shouldBeRunning {
                isStarting = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startRecognitionSession()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Public API

    /// Start / resume transcription. Preserves any text already in `transcribedText`.
    func startTranscribing() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.error = nil
            self.shouldBeRunning = true
            self.accumulatedText = self.transcribedText
            self.startRecognitionSession()
        }
    }

    /// Fully stop transcription. Tears down audio and clears accumulated state.
    func stopTranscribing() {
        shouldBeRunning = false
        isStarting = false
        tearDown(deactivateSession: true)
        accumulatedText = ""
        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = false
        }
    }

    /// Prepare for a fresh recording session. Clears prior transcription.
    func resetForNewSession() {
        shouldBeRunning = false
        isStarting = false
        tearDown(deactivateSession: true)
        accumulatedText = ""
        DispatchQueue.main.async { [weak self] in
            self?.transcribedText = ""
            self?.isTranscribing = false
        }
    }

    // MARK: - Internals

    private func startRecognitionSession() {
        guard !isStarting else { return }
        isStarting = true

        // 1. Clean up any prior session (keep audio session active for fast restart).
        tearDown(deactivateSession: false)

        guard shouldBeRunning else {
            isStarting = false
            return
        }

        // 2. Confirm the recognizer is available.
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            DispatchQueue.main.async { [weak self] in
                self?.error = "Speech recognition is not available right now. Please try again in a moment."
                self?.isTranscribing = false
            }
            isStarting = false
            return
        }

        // 3. Configure the audio session.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print(" [SpeechRecognizer] Audio session setup failed: \(error)")
            // Retry once after a brief async delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.shouldBeRunning else { return }
                do {
                    try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    self.continueStartingSession(speechRecognizer: speechRecognizer)
                } catch {
                    self.error = "Could not start the microphone. Please try again."
                    self.isTranscribing = false
                    self.isStarting = false
                }
            }
            return
        }

        continueStartingSession(speechRecognizer: speechRecognizer)
    }

    /// Completes starting a recognition session after the audio session is confirmed active.
    private func continueStartingSession(speechRecognizer: SFSpeechRecognizer) {
        // 4. Create the recognition request.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        // 5. Create a fresh AVAudioEngine for this session.
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.error = "Microphone is not available. Please check your audio settings."
                self?.isTranscribing = false
            }
            audioEngine = nil
            isStarting = false
            return
        }

        // 6. Install tap, prepare, and start engine.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            print(" [SpeechRecognizer] Engine start failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.error = "Audio engine failed to start. Please try again."
                self?.isTranscribing = false
            }
            tearDown(deactivateSession: false)
            isStarting = false
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = true
        }
        print(" [SpeechRecognizer] Audio engine started, listening…")

        // 7. Kick off the recognition task.
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                isFinal = result.isFinal
                let spoken = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if self.accumulatedText.isEmpty {
                        self.transcribedText = spoken
                    } else {
                        self.transcribedText = self.accumulatedText + " " + spoken
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                let isCancelled = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
                let isTimeout   = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110

                if isCancelled {
                    self.isStarting = false
                    return
                }

                if isTimeout || isFinal {
                    DispatchQueue.main.async {
                        self.accumulatedText = self.transcribedText
                        self.isStarting = false
                        if self.shouldBeRunning {
                            self.startRecognitionSession()
                        } else {
                            self.isTranscribing = false
                        }
                    }
                    return
                }

                print(" [SpeechRecognizer] Recognition error: \(nsError.domain) code \(nsError.code) — \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.error = "Recognition paused. Tap Start Recording to continue."
                    self.isTranscribing = false
                    self.isStarting = false
                }
                return
            }

            if isFinal {
                DispatchQueue.main.async {
                    self.accumulatedText = self.transcribedText
                    self.isStarting = false
                    if self.shouldBeRunning {
                        self.startRecognitionSession()
                    }
                }
            }
        }

        isStarting = false
    }

    /// Stop the audio engine, remove the tap, and cancel any in-flight request.
    private func tearDown(deactivateSession: Bool) {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

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
}

#Preview {
    TalkToTextView(selectedFolder: nil, saveToBrainstorm: false)
}