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
    
    @objc nonisolated private func handleMemoryWarning() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isRecording {
                print(" Memory warning during recording - consider stopping")
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
        guard let startTime = recordingStartTime else { return }
        recordingTime = Date().timeIntervalSince(startTime) - pausedDuration
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

    func startRecording(fileName: String) -> Bool {
        guard activateAudioSessionForRecording() else { return false }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFileName = documentsPath.appendingPathComponent("\(fileName).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFileName, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            isRecording = true
            isPaused = false
            activeRecordingName = fileName
            recordingStartTime = Date()
            recordingTime = 0
            pausedDuration = 0
            
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
            return false
        }
    }
    
    func pauseRecording() {
        guard isRecording && !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
        pauseStartTime = Date()
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func resumeRecording() {
        guard isRecording && isPaused else { return }
        
        // Accumulate the time spent paused
        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }
        pauseStartTime = nil
        
        audioRecorder?.record()
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
        
        let duration = recordingTime
        
        audioRecorder?.stop()
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

        print(" Stopped recording: \(url?.lastPathComponent ?? "unknown") duration: \(duration)s")
        
        return (url, duration)
    }
    
    func cancelRecording() {
        if let url = audioRecorder?.url {
            audioRecorder?.stop()
            try? FileManager.default.removeItem(at: url)
        }
        
        cleanup()
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
        audioRecorder = nil
        lastRecordingURL = nil
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
