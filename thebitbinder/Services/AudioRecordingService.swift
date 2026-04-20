//
//  AudioRecordingService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import AVFoundation
import UIKit
import Foundation
import Combine

/// Audio recording service - thread-safe via SwiftUI's @Published property dispatch.
/// All mutating methods should be called from the main thread (SwiftUI handles this).
class AudioRecordingService: NSObject, ObservableObject {
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    /// Published error message for views to display in an alert when audio session setup fails.
    @Published var audioSessionError: String?
    
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
        // Audio session setup may retry with delays; run off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupAudioSession()
        }
    }
    
    deinit {
        cleanup()
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
    
    @objc private func handleMemoryWarning() {
        // Stop recording if memory is low
        if isRecording {
            print(" Memory warning during recording - consider stopping")
        }
    }
    
    private func setupAudioSession() {
        // Check if another app is playing audio and warn
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.isOtherAudioPlaying {
            print(" [Audio] Another app is currently playing audio — session may conflict")
        }
        
        // Retry loop: attempt up to maxAudioSessionRetries times with retryDelay between attempts
        var lastError: Error?
        for attempt in 1...maxAudioSessionRetries {
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
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                print(" [Audio] Audio session configured + activated for recording (attempt \(attempt))")
                DispatchQueue.main.async { [weak self] in self?.audioSessionError = nil }
                return // success
            } catch {
                lastError = error
                print(" [Audio] Audio session setup attempt \(attempt)/\(maxAudioSessionRetries) failed: \(error.localizedDescription)")
                if attempt < maxAudioSessionRetries {
                    // Safe: this method is dispatched off the main thread by callers.
                    Thread.sleep(forTimeInterval: retryDelay)
                }
            }
        }

        // All retries exhausted
        let errorMsg: String
        if audioSession.isOtherAudioPlaying {
            errorMsg = "Could not configure audio — another app is using the speaker. Close other audio apps and try again."
        } else {
            errorMsg = "Could not configure audio for recording: \(lastError?.localizedDescription ?? "unknown error"). Please restart the app."
        }
        print(" [Audio] Audio session setup failed after \(maxAudioSessionRetries) attempts: \(errorMsg)")
        DispatchQueue.main.async { [weak self] in self?.audioSessionError = errorMsg }
    }

    /// Re-attempts audio session setup. Call from UI when user taps "Try Again".
    func retryAudioSessionSetup() {
        audioSessionError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupAudioSession()
        }
    }
    
    func startRecording(fileName: String) -> Bool {
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
            recordingStartTime = Date()
            recordingTime = 0
            pausedDuration = 0
            
            // Start timer to update recording time
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self, let startTime = self.recordingStartTime else { return }
                    self.recordingTime = Date().timeIntervalSince(startTime) - self.pausedDuration
                }
            }
            
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
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingTime = Date().timeIntervalSince(startTime) - self.pausedDuration
            }
        }
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
        recordingTime = 0
        recordingStartTime = nil
        pausedDuration = 0
        pauseStartTime = nil
        audioRecorder = nil
        lastRecordingURL = nil
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print(" Recording failed")
        }
        // Don't cleanup here - let the caller handle it
        // The URL needs to remain available after stopping
    }
}
