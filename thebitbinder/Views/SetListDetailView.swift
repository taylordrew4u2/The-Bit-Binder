//  SetListDetailView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct SetListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jokes: [Joke]
    @Query private var roastJokes: [RoastJoke]
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("showFullContent") private var showFullContent = true
    
    @Environment(\.dismiss) private var dismiss
    @Bindable var setList: SetList
    @State private var showingAddJokes = false
    @State private var isEditing = false
    
    @State private var showingDeleteSetAlert = false
    @State private var operationError: String?
    @State private var showingOperationError = false
    
    // Recording inline — uses shared service so recording persists across navigation
    @ObservedObject private var audioService = AudioRecordingService.shared
    @State private var recordingName = ""
    @State private var lastRecordingURL: URL?
    @State private var lastRecordingDuration: TimeInterval = 0
    @State private var showingSaveAlert = false
    @State private var showRecordingSaveError = false
    @State private var recordingSaveErrorMessage = ""
    
    var setListJokes: [Joke] {
        var seen = Set<UUID>()
        var result: [Joke] = []
        for jokeID in setList.jokeIDs where seen.insert(jokeID).inserted {
            if let match = jokes.first(where: { $0.id == jokeID }) {
                result.append(match)
            }
        }
        return result
    }

    var setListRoastJokes: [RoastJoke] {
        var seen = Set<UUID>()
        var result: [RoastJoke] = []
        for roastID in setList.roastJokeIDs where seen.insert(roastID).inserted {
            if let match = roastJokes.first(where: { $0.id == roastID }) {
                result.append(match)
            }
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            setHeader
            setRecordingPanel
            
            if roastMode {
                // Roast mode: show roast jokes
                if setListRoastJokes.isEmpty {
                    ContentUnavailableView {
                        Label("No Roast Jokes", systemImage: "flame")
                    } description: {
                        Text("Add roast jokes to build your set.")
                    } actions: {
                        Button("Add Roast Jokes") { showingAddJokes = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                    }
                } else {
                    List {
                        ForEach(setListRoastJokes) { joke in
                            roastJokeRow(joke)
                        }
                        .onMove(perform: moveRoastJokes)
                        .onDelete(perform: deleteRoastJokes)
                    }
                    .listStyle(.plain)
                }
            } else {
                // Regular mode: show regular jokes
                if setListJokes.isEmpty {
                    ContentUnavailableView {
                        Label("No Jokes Yet", systemImage: "text.quote")
                    } description: {
                        Text("Add jokes to build your set list.")
                    } actions: {
                        Button("Add Jokes") { showingAddJokes = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(setListJokes) { joke in
                            JokeRowView(joke: joke, showFullContent: showFullContent)
                        }
                        .onMove(perform: moveJokes)
                        .onDelete(perform: deleteJokes)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingAddJokes = true }) {
                    Label(roastMode ? "Add Roast Jokes" : "Add Jokes", systemImage: "plus")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingAddJokes = true }) {
                        Label(roastMode ? "Add Roast Jokes" : "Add Jokes", systemImage: "plus")
                    }
                    
                    Button(action: { showFullContent.toggle() }) {
                        Label(showFullContent ? "Show Titles Only" : "Show Full Content", systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                    }
                    
                    Button(action: { isEditing.toggle() }) {
                        Label(isEditing ? "Done" : "Edit Order", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(setList.totalItemCount == 0)

                    Button { shareSetList() } label: {
                        Label("Share Set List", systemImage: "square.and.arrow.up")
                    }
                    .disabled(setList.totalItemCount == 0)

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteSetAlert = true
                    } label: {
                        Label("Delete Set", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .sheet(isPresented: $showingAddJokes) {
            if roastMode {
                AddRoastJokesToSetListView(setList: setList, currentRoastJokeIDs: setList.roastJokeIDs)
            } else {
                AddJokesToSetListView(setList: setList, currentJokeIDs: setList.jokeIDs)
            }
        }
        .alert("Delete Set?", isPresented: $showingDeleteSetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSet()
            }
        } message: {
            Text("\"\(setList.name)\" will be moved to trash. You can restore it later from the trash.")
        }
        .alert("Error", isPresented: $showingOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationError ?? "An unknown error occurred")
        }
        .alert("Save Recording", isPresented: $showingSaveAlert) {
            TextField("Recording name", text: $recordingName)
            Button("Save") { saveRecording() }
            Button("Discard", role: .destructive) { discardStoppedRecording() }
        } message: {
            Text("Enter a name for your recording")
        }
        .alert("Recording Error", isPresented: $showRecordingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(recordingSaveErrorMessage)
        }
        .onAppear {
            recordingName = "\(setList.name) - \(Date().formatted(date: .abbreviated, time: .shortened))"
            cleanDanglingIDs()
        }
    }
    
    private var setHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(setList.name.isEmpty ? "Untitled Set" : setList.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                Spacer()

                Text("\(setList.totalItemCount)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.bitbinderAccent)
                    .accessibilityLabel("\(setList.totalItemCount) items")
            }

            HStack(spacing: 8) {
                if setList.estimatedMinutes > 0 {
                    Label("\(setList.estimatedMinutes) min", systemImage: "clock")
                }
                if !setList.venueName.isEmpty {
                    Label(setList.venueName, systemImage: "mappin.and.ellipse")
                }
                if let setDate = setList.performanceDate {
                    Label(setDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()), systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if !setList.notes.isEmpty {
                Text(setList.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var setRecordingPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: audioService.isRecording ? "record.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(audioService.isRecording ? Color.recording : Color.bitbinderAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(audioService.isRecording ? (audioService.isPaused ? "Recording Paused" : "Recording Set") : "Record This Set")
                        .font(.headline)
                    Text(audioService.isRecording ? timeString(from: audioService.recordingTime) : "Capture a run-through without leaving the set.")
                        .font(audioService.isRecording ? .system(.body, design: .monospaced) : .caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if audioService.isRecording {
                    Button(action: pauseResumeRecording) {
                        Label(audioService.isPaused ? "Resume" : "Pause", systemImage: audioService.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: stopRecording) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: startRecording) {
                        Label("Start Recording", systemImage: "record.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.recording)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func startRecording() {
        let name = recordingName.isEmpty ? setList.name : recordingName
        let started = audioService.startRecording(fileName: name)
        if !started {
            recordingSaveErrorMessage = audioService.audioSessionError ?? "Could not start recording. Please try again."
            showRecordingSaveError = true
        }
    }
    
    private func pauseResumeRecording() {
        if audioService.isPaused {
            audioService.resumeRecording()
        } else {
            audioService.pauseRecording()
        }
    }
    
    private func stopRecording() {
        let result = audioService.stopRecording()
        lastRecordingURL = result.url
        lastRecordingDuration = result.duration
        showingSaveAlert = true
    }
    
    private func saveRecording() {
        guard let fileURL = lastRecordingURL else {
            recordingSaveErrorMessage = "No recording file found."
            showRecordingSaveError = true
            return
        }
        let recording = Recording(
            title: recordingName.isEmpty ? "Recording \(Date())" : recordingName,
            fileURL: fileURL.lastPathComponent,
            duration: lastRecordingDuration
        )
        modelContext.insert(recording)

        do {
            try modelContext.save()
            #if DEBUG
            print("Recording saved successfully: \(recording.title)")
            #endif
            audioService.clearFinishedRecording()
            lastRecordingURL = nil
            lastRecordingDuration = 0
        } catch {
            #if DEBUG
            print(" Failed to save recording: \(error)")
            #endif
            recordingSaveErrorMessage = "Could not save recording: \(error.localizedDescription)"
            showRecordingSaveError = true
        }
    }

    private func discardStoppedRecording() {
        audioService.cancelRecording()
        lastRecordingURL = nil
        lastRecordingDuration = 0
    }
    
    private func moveJokes(from source: IndexSet, to destination: Int) {
        setList.jokeIDs.move(fromOffsets: source, toOffset: destination)
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            operationError = "Could not save reorder: \(error.localizedDescription)"
            showingOperationError = true
        }
    }

    private func deleteJokes(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            if index < setList.jokeIDs.count {
                setList.jokeIDs.remove(at: index)
            }
        }
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            operationError = "Could not remove joke: \(error.localizedDescription)"
            showingOperationError = true
        }
    }
    
    // MARK: - Roast Joke Helpers
    
    @ViewBuilder
    private func roastJokeRow(_ joke: RoastJoke) -> some View {
            HStack(alignment: .top, spacing: 12) {
                 Image(systemName: "flame.fill")
                     .font(.system(size: 14))
                     .foregroundColor(Color.accentColor)
                     .padding(.top, 3)
                 
                 VStack(alignment: .leading, spacing: 4) {
                     if showFullContent {
                         if !joke.setup.isEmpty {
                             Text("SETUP")
                                 .font(.caption2.weight(.bold))
                                 .foregroundColor(Color.accentColor)
                             Text(joke.setup)
                                 .font(.system(size: 14))
                                 .foregroundColor(.secondary)
                         }

                         Text(joke.content)
                             .font(.system(size: 15))
                             .foregroundColor(.primary)
                     } else {
                         Text(joke.previewDisplayText)
                             .font(.system(size: 15, weight: .medium))
                             .foregroundColor(.primary)
                             .lineLimit(1)
                     }
                     
                     if let targetName = joke.target?.name {
                         Text("for \(targetName)")
                             .font(.system(size: 12, weight: .medium))
                             .foregroundColor(Color.accentColor.opacity(0.8))
                     }
                 }
             }
        .padding(.vertical, 4)
    }
    
    private func moveRoastJokes(from source: IndexSet, to destination: Int) {
        setList.roastJokeIDs.move(fromOffsets: source, toOffset: destination)
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            operationError = "Could not save reorder: \(error.localizedDescription)"
            showingOperationError = true
        }
    }

    private func deleteRoastJokes(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            if index < setList.roastJokeIDs.count {
                setList.roastJokeIDs.remove(at: index)
            }
        }
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            operationError = "Could not remove roast: \(error.localizedDescription)"
            showingOperationError = true
        }
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes, seconds)
    }
    
    private func shareSetList() {
        var lines: [String] = [setList.name, ""]
        for (index, joke) in setListJokes.enumerated() {
            let title = joke.title.isEmpty ? "Joke \(index + 1)" : joke.title
            lines.append("\(index + 1). \(title)")
            if !joke.content.isEmpty { lines.append(joke.content) }
            lines.append("")
        }
        for (index, joke) in setListRoastJokes.enumerated() {
            let num = setListJokes.count + index + 1
            let label = joke.title.isEmpty ? joke.content.prefix(40).description : joke.title
            lines.append("\(num). \(label)")
            if !joke.content.isEmpty { lines.append(joke.content) }
            lines.append("")
        }
        ShareHelper.shareText(lines.joined(separator: "\n"))
    }

    private func deleteSet() {
        setList.moveToTrash()
        do {
            try modelContext.save()
            dismiss()
        } catch {
            #if DEBUG
            print("⚠️ [SetListDetailView] Failed to delete set: \(error)")
            #endif
            operationError = "Delete may not have saved. The set will stay deleted but please check later."
            showingOperationError = true
            dismiss()
        }
    }

    private func cleanDanglingIDs() {
        let jokeIDSet = Set(jokes.map(\.id))
        let roastIDSet = Set(roastJokes.map(\.id))
        if setList.cleanDanglingIDs(existingJokeIDs: jokeIDSet, existingRoastJokeIDs: roastIDSet) {
            try? modelContext.save()
        }
    }
}
