//
//  RecordingDetailView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import AVFoundation
import SwiftData
import Speech

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @Bindable var recording: Recording
    @StateObject private var audioPlayer = AudioPlayerService()
    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var showingTranscriptionError = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Player controls
                VStack(spacing: 20) {
                    // Show error if loading failed
                    if let error = audioPlayer.loadError {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 100, height: 100)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                            }
                            
                            Text("Unable to Play")
                                .font(.headline)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                audioPlayer.loadAudio(from: recording.resolvedURL)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 8)
                                .frame(width: 200, height: 200)
                            
                            if audioPlayer.isPlaying {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.3))
                                    .frame(width: 180, height: 180)
                            }
                            
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.accentColor)
                        }
                        
                        // Progress bar
                        VStack(spacing: 8) {
                            Slider(value: $audioPlayer.currentTime, in: 0...max(audioPlayer.duration, 1), onEditingChanged: { editing in
                                if !editing {
                                    audioPlayer.seek(to: audioPlayer.currentTime)
                                }
                            })
                            .tint(.accentColor)
                            
                            HStack {
                                Text(timeString(from: audioPlayer.currentTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(timeString(from: audioPlayer.duration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Playback controls
                        HStack(spacing: 40) {
                            Button(action: { audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15)) }) {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 30))
                            }
                            
                            Button(action: togglePlayback) {
                                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 60))
                            }
                            
                            Button(action: { audioPlayer.seek(to: min(audioPlayer.duration, audioPlayer.currentTime + 15)) }) {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 30))
                            }
                        }
                        .foregroundColor(.accentColor)
                    }
                }
                .padding()
                
                // Transcription section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Transcription", systemImage: "text.quote")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isTranscribing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if recording.transcription == nil {
                            Button(action: transcribeRecording) {
                                Label("Transcribe", systemImage: "waveform")
                                    .font(.subheadline)
                            }
                        } else {
                            Button(action: transcribeRecording) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.subheadline)
                            }
                        }
                    }
                    
                    if let transcription = recording.transcription {
                        Text(transcription)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                    } else if isTranscribing {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Transcribing audio...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    } else {
                        Text("Tap 'Transcribe' to convert this recording to text")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // Recording info
                VStack(alignment: .leading, spacing: 16) {
                    InfoRow(label: "Name", value: recording.title)
                    InfoRow(label: "Duration", value: timeString(from: recording.duration))
                    InfoRow(label: "Date", value: recording.dateCreated.formatted(date: .long, time: .shortened))
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Share button
                Button(action: shareRecording) {
                    Label("Share Recording", systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Small delay to ensure audio session is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard scenePhase == .active else { return }
                audioPlayer.loadAudio(from: recording.resolvedURL)
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .alert("Transcription Error", isPresented: $showingTranscriptionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(transcriptionError ?? "An unknown error occurred")
        }
        .alert("Speech Recognition Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("BitBinder needs speech recognition permission to transcribe your recordings. Please enable it in Settings.")
        }
    }
    
    private func togglePlayback() {
        // Don't try to play if there's a load error
        guard audioPlayer.loadError == nil else {
            audioPlayer.loadAudio(from: recording.resolvedURL)
            return
        }
        
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else {
            audioPlayer.play()
        }
    }
    
    private func transcribeRecording() {
        // Check permission first
        let status = SFSpeechRecognizer.authorizationStatus()
        
        if status == .denied || status == .restricted {
            showingPermissionAlert = true
            return
        }
        
        isTranscribing = true
        transcriptionError = nil
        
        Task {
            do {
                // Request permission if not determined
                if status == .notDetermined {
                    let newStatus = await AudioTranscriptionService.requestAuthorization()
                    if newStatus != .authorized {
                        await MainActor.run {
                            isTranscribing = false
                            showingPermissionAlert = true
                        }
                        return
                    }
                }
                
                let url = recording.resolvedURL
                
                // Verify file exists
                guard FileManager.default.fileExists(atPath: url.path) else {
                    await MainActor.run {
                        transcriptionError = "Recording file not found. It may have been deleted."
                        showingTranscriptionError = true
                        isTranscribing = false
                    }
                    return
                }
                
                #if DEBUG
                print(" [Transcribe] Attempting transcription of: \(url.path)")
                #endif
                
                let result = try await AudioTranscriptionService.shared.transcribe(audioURL: url)
                
                #if DEBUG
                print(" [Transcribe] Success — \(result.transcription.count) chars, confidence: \(String(format: "%.0f", result.confidencePercentage))%")
                #endif
                
                await MainActor.run {
                    recording.transcription = result.transcription
                    recording.isProcessed = true
                    do {
                        try modelContext.save()
                        haptic(.success)
                    } catch {
                        print(" [RecordingDetailView] Failed to save transcription: \(error)")
                        transcriptionError = "Transcription completed but could not be saved: \(error.localizedDescription)"
                        showingTranscriptionError = true
                    }
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    transcriptionError = error.localizedDescription
                    showingTranscriptionError = true
                    isTranscribing = false
                    haptic(.error)
                }
            }
        }
    }
    
    private func shareRecording() {
        let url = recording.resolvedURL
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print(" Cannot share - file not found: \(url.path)")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var loadError: String?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
        setupMemoryWarningObserver()
    }
    
    deinit {
        cleanup()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAudioSession() {
        // Don't reconfigure - use the app-wide session from AppDelegate
        // AppDelegate already configured .playAndRecord which works for both
        do {
            let session = AVAudioSession.sharedInstance()
            // Just ensure it's active, don't change category
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print(" Audio session activated for playback")
        } catch {
            print(" Failed to activate audio session: \(error)")
            loadError = "Failed to configure audio: \(error.localizedDescription)"
        }
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
        // Pause playback on memory warning
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPlaying else { return }
            self.pause()
            print(" Memory warning - pausing playback")
        }
    }
    
    func loadAudio(from url: URL) {
        // Clean up previous audio first
        cleanup()
        loadError = nil
        
        print(" Loading audio from: \(url.path)")
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            let errorMsg = "Audio file not found: \(url.lastPathComponent)"
            print(" \(errorMsg)")
            print(" Documents directory: \(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path)")
            
            // List files in documents directory for debugging
            if let files = try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path) {
                print(" Files in documents: \(files.filter { $0.hasSuffix(".m4a") })")
            }
            
            loadError = errorMsg
            return
        }
        
        print(" File exists at: \(url.path)")
        
        // Audio session already configured app-wide in AppDelegate
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            print(" Audio loaded successfully: duration = \(duration)s")
        } catch {
            let errorMsg = "Error loading audio: \(error.localizedDescription)"
            print(" \(errorMsg)")
            loadError = errorMsg
        }
    }
    
    func play() {
        guard let player = audioPlayer else {
            print(" Cannot play - audio player is nil")
            loadError = "Audio not loaded"
            return
        }
        player.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }
    
    private func startTimer() {
        stopTimer() // Ensure no duplicate timers
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func cleanup() {
        stopTimer()
        if let player = audioPlayer {
            if player.isPlaying {
                player.stop()
            }
        }
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
    }
    
    // AVAudioPlayerDelegate methods
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
            self?.currentTime = 0
            self?.stopTimer()
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                print("Audio player decode error: \(error.localizedDescription)")
            }
            self?.isPlaying = false
            self?.stopTimer()
        } 
    }
}
