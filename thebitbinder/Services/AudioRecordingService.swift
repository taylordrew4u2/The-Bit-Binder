//
//  AudioRecordingService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import AVFoundation
import UIKit
import Combine

/// Audio recording service - @MainActor isolated so @Published properties
/// are always mutated on the main thread.
@MainActor
class AudioRecordingService: NSObject, ObservableObject {

    static let shared = AudioRecordingService()

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    /// Published error message for views to display in an alert when audio session setup fails.
    @Published var audioSessionError: String?

    /// Name of the file currently being recorded (for UI display when navigated away)
    @Published var activeRecordingName: String = ""
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?
    private var lastRecordingURL: URL?
    private var wasInterrupted = false
    private var wasPausedBeforeInterruption = false
    
    /// Maximum number of retry attempts for audio session configuration
    private let maxAudioSessionRetries = 3
    /// Delay between retry attempts (seconds)
    private let retryDelay: TimeInterval = 1.0
    
    var recordingURL: URL? {
        return lastRecordingURL ?? audioRecorder?.url
    }
    
    override init() {
        super.init()
        setupMemoryWarningObserver()
        setupAudioSessionObservers()
        setupAudioSession()
    }
    
    deinit {
        // Cannot call @MainActor-isolated cleanup() from nonisolated deinit.
        // Invalidate the timer directly — it is safe to call from any thread.
        recordingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    private func setupAudioSessionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc nonisolated private func handleMemoryWarning() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isRecording {
                print(" Memory warning during recording - consider stopping")
            }
        }
    }

    @objc nonisolated private func handleAudioInterruption(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self,
                  let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                guard self.isRecording else { return }
                self.wasInterrupted = true
                self.wasPausedBeforeInterruption = self.isPaused
                if !self.isPaused {
                    self.pauseRecording()
                }
                self.audioSessionError = "Recording paused because audio was interrupted. It will resume automatically if iOS allows it."
            case .ended:
                guard self.wasInterrupted else { return }
                self.wasInterrupted = false
                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                guard self.isRecording, !self.wasPausedBeforeInterruption, options.contains(.shouldResume) else { return }
                self.resumeRecording()
            @unknown default:
                break
            }
        }
    }

    @objc nonisolated private func handleRouteChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            guard let info = notification.userInfo,
                  let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

            switch reason {
            case .oldDeviceUnavailable, .newDeviceAvailable, .routeConfigurationChange:
                self.audioSessionError = nil
            default:
                break
            }
        }
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.isOtherAudioPlaying {
            print(" [Audio] Another app is currently playing audio — session may conflict")
        }
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .mixWithOthers
                ]
            )
            audioSessionError = nil
            print(" [Audio] Audio session category configured for recording")
        } catch {
            let errorMsg = "Could not configure audio category for recording: \(error.localizedDescription)"
            print(" [Audio] \(errorMsg)")
            audioSessionError = errorMsg
        }
    }

    @objc private func updateRecordingTimeFromTimer() {
        recordingTime = currentElapsedRecordingTime()
    }

    private func currentElapsedRecordingTime() -> TimeInterval {
        guard let startTime = recordingStartTime else { return recordingTime }
        let activePausedDuration: TimeInterval
        if let pauseStart = pauseStartTime {
            activePausedDuration = pausedDuration + Date().timeIntervalSince(pauseStart)
        } else {
            activePausedDuration = pausedDuration
        }
        return max(0, Date().timeIntervalSince(startTime) - activePausedDuration)
    }

    private func activateAudioSessionForRecording() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        var lastError: Error?

        for attempt in 1...maxAudioSessionRetries {
            do {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                audioSessionError = nil
                print(" [Audio] Audio session activated for recording (attempt \(attempt))")
                return true
            } catch {
                lastError = error
                print(" [Audio] Audio session activation attempt \(attempt)/\(maxAudioSessionRetries) failed: \(error.localizedDescription)")
                // Avoid blocking the main actor with retry sleeps during recording setup.
                if attempt < maxAudioSessionRetries {
                    RunLoop.main.run(until: Date().addingTimeInterval(retryDelay))
                }
            }
        }

        if audioSession.isOtherAudioPlaying {
            audioSessionError = "Could not start recording — another app is using audio. Close it and try again."
        } else {
            audioSessionError = "Could not activate audio for recording: \(lastError?.localizedDescription ?? "unknown error")."
        }
        return false
    }

    private func deactivateAudioSessionAfterRecording() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print(" [Audio] Could not deactivate audio session: \(error.localizedDescription)")
        }
    }

    func startRecording(fileName: String) -> Bool {
        guard !isRecording else {
            audioSessionError = "A recording is already in progress."
            return false
        }
        guard lastRecordingURL == nil else {
            audioSessionError = "Save or discard the stopped recording before starting a new one."
            return false
        }

        setupAudioSession()
        guard activateAudioSessionForRecording() else { return false }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeFileName = sanitizedFileName(fileName)
        let audioFileName = uniqueRecordingURL(in: documentsPath, baseName: safeFileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFileName, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
            guard audioRecorder?.record() == true else {
                let failedURL = audioRecorder?.url
                audioRecorder = nil
                if let failedURL {
                    try? FileManager.default.removeItem(at: failedURL)
                }
                deactivateAudioSessionAfterRecording()
                audioSessionError = "Could not start recording. Check microphone access and try again."
                return false
            }
            
            isRecording = true
            isPaused = false
            activeRecordingName = safeFileName
            recordingStartTime = Date()
            recordingTime = 0
            pausedDuration = 0
            pauseStartTime = nil
            wasInterrupted = false
            wasPausedBeforeInterruption = false
            
            // Invalidate any leftover timer before creating a new one to prevent
            // a leaked repeating timer if startRecording is called twice.
            recordingTimer?.invalidate()

            // Start timer to update recording time
            recordingTimer = Timer.scheduledTimer(
                timeInterval: 0.1,
                target: self,
                selector: #selector(updateRecordingTimeFromTimer),
                userInfo: nil,
                repeats: true
            )
            
            return true
        } catch {
            print("Failed to start recording: \(error)")
            deactivateAudioSessionAfterRecording()
            audioSessionError = "Failed to start recording: \(error.localizedDescription)"
            return false
        }
    }
    
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        audioRecorder?.pause()
        recordingTime = currentElapsedRecordingTime()
        isPaused = true
        pauseStartTime = Date()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func resumeRecording() {
        guard isRecording && isPaused else { return }
        guard activateAudioSessionForRecording() else { return }
        
        guard audioRecorder?.record() == true else {
            audioSessionError = "Could not resume recording. Try stopping and saving what was captured."
            return
        }

        // Accumulate the time spent paused only after recording actually resumes.
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        isPaused = false
        
        // Restart timer
        recordingTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(updateRecordingTimeFromTimer),
            userInfo: nil,
            repeats: true
        )
    }
    
    func stopRecording() -> (url: URL?, duration: TimeInterval) {
        let url = audioRecorder?.url
        
        // If we're currently paused, account for the final pause duration
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartTime = nil
        }
        
        let duration = currentElapsedRecordingTime()
        
        audioRecorder?.stop()
        audioRecorder = nil
        deactivateAudioSessionAfterRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Store the URL before clearing everything
        lastRecordingURL = url
        
        isRecording = false
        isPaused = false
        activeRecordingName = ""
        recordingTime = 0
        recordingStartTime = nil
        pausedDuration = 0
        pauseStartTime = nil
        wasInterrupted = false
        wasPausedBeforeInterruption = false

        print(" Stopped recording: \(url?.lastPathComponent ?? "unknown") duration: \(duration)s")
        
        return (url, duration)
    }
    
    func cancelRecording() {
        let url = audioRecorder?.url ?? lastRecordingURL
        audioRecorder?.stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        
        cleanup()
        deactivateAudioSessionAfterRecording()
    }

    func clearFinishedRecording() {
        audioRecorder = nil
        lastRecordingURL = nil
        audioSessionError = nil
        deactivateAudioSessionAfterRecording()
    }
    
    private func cleanup() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isPaused = false
        activeRecordingName = ""
        recordingTime = 0
        recordingStartTime = nil
        pausedDuration = 0
        pauseStartTime = nil
        wasInterrupted = false
        wasPausedBeforeInterruption = false
        audioRecorder = nil
        lastRecordingURL = nil
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
            .union(.controlCharacters)
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        while sanitized.contains("__") {
            sanitized = sanitized.replacingOccurrences(of: "__", with: "_")
        }
        if sanitized.isEmpty {
            sanitized = "Recording_\(UUID().uuidString.prefix(8))"
        }
        return sanitized
    }

    private func uniqueRecordingURL(in directory: URL, baseName: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).m4a")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        candidate = directory.appendingPathComponent("\(baseName)_\(timestamp).m4a")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        return directory.appendingPathComponent("\(baseName)_\(UUID().uuidString.prefix(8)).m4a")
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print(" Recording failed")
        }
        // Don't cleanup here - let the caller handle it
        // The URL needs to remain available after stopping
    }
}
