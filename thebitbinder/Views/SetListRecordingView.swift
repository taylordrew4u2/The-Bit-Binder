//
//  SetListRecordingView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/3/25.
//

import SwiftUI
import SwiftData

struct SetListRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var jokes: [Joke]
    
    let setList: SetList
    @StateObject private var audioService = AudioRecordingService()
    @State private var recordingName = ""
    @State private var showingSaveAlert = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    var setListJokes: [Joke] {
        setList.jokeIDs.compactMap { jokeID in
            jokes.first { $0.id == jokeID }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recording Status Bar
                VStack(spacing: 12) {
                    if audioService.isRecording {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .opacity(0.8)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioService.isRecording)
                            
                            Text("Recording")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Spacer()
                            
                            Text(timeString(from: recordingDuration))
                                .font(.system(.title3, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                    }
                    
                    // Recording Controls
                    HStack(spacing: 30) {
                        if !audioService.isRecording {
                            Button(action: startRecording) {
                                VStack {
                                    Image(systemName: "record.circle.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.red)
                                    Text("Start Recording")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        } else {
                            Button(action: pauseResumeRecording) {
                                VStack {
                                    Image(systemName: audioService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.blue)
                                    Text(audioService.isPaused ? "Resume" : "Pause")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            Button(action: stopRecording) {
                                VStack {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.red)
                                    Text("Stop")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
                
                Divider()
                
                // Set List Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(setList.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        ForEach(Array(setListJokes.enumerated()), id: \.element.id) { index, joke in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(index + 1).")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                        .frame(width: 30, alignment: .leading)
                                    
                                    Text(joke.title.isEmpty ? "Untitled Joke" : joke.title)
                                        .font(.headline)
                                }
                                
                                Text(joke.content)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 30)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Recording Set List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if audioService.isRecording {
                            _ = audioService.stopRecording()
                        }
                        dismiss()
                    }
                }
            }
            .alert("Save Recording", isPresented: $showingSaveAlert) {
                TextField("Recording name", text: $recordingName)
                Button("Save") {
                    saveRecording()
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Enter a name for your recording")
            }
        }
        .onAppear {
            recordingName = "\(setList.name) - \(Date().formatted(date: .abbreviated, time: .shortened))"
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startRecording() {
        let name = recordingName.isEmpty ? setList.name : recordingName
        let started = audioService.startRecording(fileName: name)
        if started {
            recordingDuration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
            }
        }
    }
    
    private func pauseResumeRecording() {
        if audioService.isPaused {
            audioService.resumeRecording()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
            }
        } else {
            audioService.pauseRecording()
            timer?.invalidate()
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        let result = audioService.stopRecording()
        recordingDuration = result.duration
        showingSaveAlert = true
    }
    
    private func saveRecording() {
        guard let fileURL = audioService.recordingURL else {
            print("❌ No recording URL found")
            dismiss()
            return
        }
        
        // Verify file exists
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        print("📁 Recording file exists: \(fileExists) at \(fileURL.path)")
        
        // Store just the filename, not the full path (paths change between app launches)
        let fileName = fileURL.lastPathComponent
        
        let recording = Recording(
            title: recordingName.isEmpty ? "Recording \(Date())" : recordingName,
            fileURL: fileName,
            duration: recordingDuration
        )
        
        print("✅ Saving recording: \(fileName) with duration: \(recordingDuration)s")
        modelContext.insert(recording)
        
        // Save context explicitly
        do {
            try modelContext.save()
            print("✅ Recording saved to database")
        } catch {
            print("❌ Failed to save recording to database: \(error)")
        }
        
        dismiss()
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
