//
//  RecordRoastSetView.swift
//  thebitbinder
//
//  A view for recording a full stand-up set focused on a roast target,
//  then splitting the recording into individual roast jokes.
//

import SwiftUI
import AVFoundation

struct RecordRoastSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var audioService = AudioRecordingService.shared
    
    let target: RoastTarget
    
    @State private var recordingURL: URL?
    @State private var stoppedRecordingDuration: TimeInterval = 0
    @State private var errorMessage: String?
    @State private var showDiscardAlert = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    private var accentColor: Color { FirePalette.core }
    
    /// Safe access to target name
    private var safeTargetName: String {
        target.isValid ? target.name : "Target"
    }
    
    var formattedTime: String {
        let displayTime = audioService.isRecording ? audioService.recordingTime : stoppedRecordingDuration
        let minutes = Int(displayTime) / 60
        let seconds = Int(displayTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(audioService.isRecording ? Color.recording.opacity(DS.Opacity.light) : accentColor.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .scaleEffect(audioService.isRecording && !reduceMotion ? 1.04 : 1.0)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioService.isRecording)
                        
                        Image(systemName: audioService.isRecording ? "record.circle.fill" : "record.circle")
                            .font(.system(size: 40))
                            .foregroundColor(audioService.isRecording ? .recording : accentColor)
                            .symbolEffect(.variableColor, isActive: audioService.isRecording && !reduceMotion)
                    }
                    
                    Text(audioService.isRecording ? "Recording..." : "Ready")
                         .font(.title3)
                         .fontWeight(.semibold)
                    
                    // Time display
                     Text(formattedTime)
                         .font(.system(size: 36, weight: .bold, design: .monospaced))
                         .foregroundColor(audioService.isRecording ? .recording : accentColor)
                         .padding()
                         .background(Color(UIColor.secondarySystemBackground))
                         .cornerRadius(12)
                }
                .padding(.top, 20)
                
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(accentColor)
                        Text("Record your full set, then review and split into individual roasts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                if let error = errorMessage {
                     Text(error)
                         .font(.caption)
                         .foregroundColor(.red)
                         .padding(.horizontal, 20)
                 }
                
                // Controls
                VStack(spacing: 16) {
                    Button {
                        if audioService.isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: audioService.isRecording ? "stop.fill" : "record.circle.fill")
                                .font(.system(size: 20))
                            Text(audioService.isRecording ? "Stop Recording" : "Start Recording")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                         .padding(.vertical, 16)
                         .background(audioService.isRecording ? Color.recording : accentColor)
                         .foregroundColor(.white)
                         .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    if recordingURL != nil && !audioService.isRecording {
                        Button {
                            saveRecording()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                Text("Done")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                             .padding(.vertical, 16)
                             .background(Color.bitbinderAccent)
                             .foregroundColor(.white)
                             .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if audioService.isRecording || recordingURL != nil {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Discard Recording?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    if audioService.isRecording {
                        audioService.cancelRecording()
                    }
                    if let url = recordingURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    dismiss()
                }
                Button("Keep Recording", role: .cancel) { }
            } message: {
                Text("You have an active or unsaved recording. Are you sure you want to discard it?")
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    private func saveRecording() {
        guard let fileURL = recordingURL else {
            saveErrorMessage = "No recording file found."
            showSaveError = true
            return
        }
        
        // Safety check - ensure target is still valid
        guard target.isValid else {
            saveErrorMessage = "Target was deleted. Recording saved but not linked."
            showSaveError = true
            return
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            saveErrorMessage = "Recording file was not created. Please try again."
            showSaveError = true
            return
        }
        
        // Create a Recording model
        let recording = Recording(
            title: "Roast Set – \(safeTargetName)",
            fileURL: fileURL.lastPathComponent,
            duration: stoppedRecordingDuration
        )
        modelContext.insert(recording)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [RecordRoastSetView] Recording saved for '\(target.name)' (duration: \(stoppedRecordingDuration)s)")
            #endif
            audioService.clearFinishedRecording()
            recordingURL = nil
            stoppedRecordingDuration = 0
            dismiss()
        } catch {
            #if DEBUG
            print(" [RecordRoastSetView] Failed to save recording model: \(error)")
            #endif
            saveErrorMessage = "Could not save recording: \(error.localizedDescription)"
            showSaveError = true
        }
    }
    
    private func startRecording() {
        Task {
            // Request microphone permission
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }
            }
            
            guard granted else {
                await MainActor.run {
                    self.errorMessage = "Microphone permission required"
                }
                return
            }
            
            await MainActor.run {
                let started = audioService.startRecording(fileName: "Roast Set - \(safeTargetName)")
                if started {
                    recordingURL = nil
                    stoppedRecordingDuration = 0
                    errorMessage = nil
                } else {
                    errorMessage = audioService.audioSessionError ?? "Failed to start recording. Check microphone access and try again."
                }
            }
        }
    }
    
    private func stopRecording() {
        let result = audioService.stopRecording()
        recordingURL = result.url
        stoppedRecordingDuration = result.duration
    }
}

#Preview {
    RecordRoastSetView(target: RoastTarget(name: "Dave Chappelle", notes: "Comedy legend"))
}
