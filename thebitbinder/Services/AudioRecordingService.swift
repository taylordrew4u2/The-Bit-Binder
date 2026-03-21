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

class AudioRecordingService: NSObject, ObservableObject {
    
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var lastRecordingURL: URL?
    
    var recordingURL: URL? {
        return lastRecordingURL ?? audioRecorder?.url
    }
    
    override init() {
        super.init()
        setupAudioSession()
        setupMemoryWarningObserver()
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
            print("⚠️ Memory warning during recording - consider stopping")
        }
    }
    
    private func setupAudioSession() {
        // Lazily configure + activate the audio session on first recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
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
            print("✅ Audio session configured + activated for recording")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
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
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    func resumeRecording() {
        guard isRecording && isPaused else { return }
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
        
        print("🎙️ Stopped recording: \(url?.lastPathComponent ?? "unknown") duration: \(duration)s")
        
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
        audioRecorder = nil
        lastRecordingURL = nil
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("❌ Recording failed")
        }
        // Don't cleanup here - let the caller handle it
        // The URL needs to remain available after stopping
    }
}
