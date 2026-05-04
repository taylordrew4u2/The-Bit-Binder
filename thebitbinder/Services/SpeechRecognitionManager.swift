//
//  SpeechRecognitionManager.swift
//  thebitbinder
//
//  Extracted from BrainstormView.swift — manages live speech-to-text
//  recognition with auto-restart, interruption handling, and route changes.
//  Uses shared helpers from SpeechRecognitionHelpers.swift.
//

import Foundation
import Speech
import AVFoundation

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
        guard !shouldBeRunning, !isRecording, recognitionTask == nil else {
            return
        }
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

        let request = makeRecognitionRequest()
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
            self?.handleRecognitionResult(result, error: error)
        }
    }

    private func makeRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        return request
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
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
                scheduleAutoRestart()
                return
            }

            if SpeechErrorCode.isTransientRecoverable(nsError) {
                #if DEBUG
                print(" [SpeechRecognitionManager] Transient recognition error — restarting")
                #endif
                scheduleAutoRestart()
                return
            }

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

        if isFinal {
            scheduleAutoRestart()
        }
    }

    /// Lightweight restart that keeps the audio engine running — swaps the
    /// recognition request in place so there is no gap in captured audio.
    private func restartRecognitionInPlace() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let oldRequest = recognitionRequest
        let newRequest = makeRecognitionRequest()
        recognitionRequest = newRequest
        oldRequest?.endAudio()

        segmentStartText = transcribedText

        guard let sr = speechRecognizer, sr.isAvailable else {
            isRestarting = false
            tearDownAudioPipeline(deactivateSession: false)
            startRecognitionSession()
            return
        }

        isRestarting = false
        recognitionTask = sr.recognitionTask(with: newRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result, error: error)
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
                guard let self = self, self.shouldBeRunning else { return }
                if let engine = self.audioEngine, engine.isRunning {
                    self.restartRecognitionInPlace()
                } else {
                    self.startRecognitionSession()
                }
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
