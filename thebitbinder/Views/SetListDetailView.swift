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
    
    @Environment(\.dismiss) private var dismiss
    @Bindable var setList: SetList
    @State private var showingAddJokes = false
    @State private var isEditing = false
    @State private var mode: SetDetailMode = .arrange
    
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
    
    private var visibleItemCount: Int {
        roastMode ? setListRoastJokes.count : setListJokes.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                setHeader
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                setModeControls
                    .listRowSeparator(.hidden)

                if audioService.isRecording || mode == .rehearse {
                    setRecordingPanel
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                if visibleItemCount == 0 {
                    ContentUnavailableView {
                        Label(roastMode ? "No Roast Jokes" : "No Jokes Yet",
                              systemImage: roastMode ? "flame" : "text.quote")
                    } description: {
                        Text("Add jokes in Arrange to build your set.")
                    }
                } else if roastMode {
                    roastMaterialRows(proxy: proxy)
                } else {
                    regularMaterialRows(proxy: proxy)
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if audioService.isRecording {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: stopRecording) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(Color.recording)
                    .accessibilityLabel("Stop audio recording")
                    .accessibilityHint("Stops recording and opens the save options.")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
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
                .accessibilityLabel("Set list actions")
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .onChange(of: mode) { _, _ in isEditing = false }
        .onChange(of: roastMode) { _, _ in isEditing = false }
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
        }
    }
    
    private var setModeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Set mode", selection: $mode) {
                ForEach(SetDetailMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode == .arrange {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        arrangeButtons
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 12) {
                        arrangeButtons
                    }
                }

                if !audioService.isRecording {
                    Button(action: startRecording) {
                        Label("Record Set Audio", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityHint("Records audio that you can save after stopping.")
                }
            } else {
                Text("Read each joke in full. Use Next Joke to move through your set.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var arrangeButtons: some View {
        Button { showingAddJokes = true } label: {
            Label(roastMode ? "Add Roast Jokes" : "Add Jokes", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)

        Button { isEditing.toggle() } label: {
            Label(isEditing ? "Done Reordering" : "Reorder",
                  systemImage: isEditing ? "checkmark" : "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
        .disabled(visibleItemCount == 0)
        .accessibilityHint("Change the order or remove a joke from this set.")
    }

    private func regularMaterialRows(proxy: ScrollViewProxy) -> some View {
        let material = setListJokes
        return ForEach(Array(material.enumerated()), id: \.element.id) { index, joke in
            SetMaterialRow(
                number: index + 1,
                total: material.count,
                title: joke.title,
                content: joke.content,
                isRehearsing: mode == .rehearse,
                nextAction: index + 1 < material.count ? {
                    proxy.scrollTo(material[index + 1].id, anchor: .top)
                } : nil
            )
            .id(joke.id)
            .moveDisabled(mode == .rehearse)
            .deleteDisabled(mode == .rehearse)
        }
        .onMove(perform: moveJokes)
        .onDelete(perform: deleteJokes)
    }

    private func roastMaterialRows(proxy: ScrollViewProxy) -> some View {
        let material = setListRoastJokes
        return ForEach(Array(material.enumerated()), id: \.element.id) { index, joke in
            SetMaterialRow(
                number: index + 1,
                total: material.count,
                title: joke.title,
                content: joke.content,
                setup: joke.setup,
                targetName: joke.target?.name,
                isRehearsing: mode == .rehearse,
                nextAction: index + 1 < material.count ? {
                    proxy.scrollTo(material[index + 1].id, anchor: .top)
                } : nil
            )
            .id(joke.id)
            .moveDisabled(mode == .rehearse)
            .deleteDisabled(mode == .rehearse)
        }
        .onMove(perform: moveRoastJokes)
        .onDelete(perform: deleteRoastJokes)
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
                    Text(audioService.isRecording ? (audioService.isPaused ? "Recording Paused" : "Recording Set") : "Record Set Audio")
                        .font(.headline)
                    Text(audioService.isRecording ? timeString(from: audioService.recordingTime) : "Save an audio recording of your run-through.")
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
                        Label("Record Set Audio", systemImage: "record.circle.fill")
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
        recording.captureAudioData()   // capture bytes so the audio syncs across devices

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
        updateSetOrder(keyPath: \.jokeIDs, values: VisibleListOrder.moving(
            offsets: source, to: destination, visible: setListJokes.map(\.id), stored: setList.jokeIDs
        ))
    }

    private func deleteJokes(at offsets: IndexSet) {
        updateSetOrder(keyPath: \.jokeIDs, values: VisibleListOrder.removing(
            offsets: offsets, visible: setListJokes.map(\.id), stored: setList.jokeIDs
        ))
    }
    
    // MARK: - Roast Joke Helpers
    
    private func moveRoastJokes(from source: IndexSet, to destination: Int) {
        updateSetOrder(keyPath: \.roastJokeIDs, values: VisibleListOrder.moving(
            offsets: source, to: destination, visible: setListRoastJokes.map(\.id), stored: setList.roastJokeIDs
        ))
    }

    private func deleteRoastJokes(at offsets: IndexSet) {
        updateSetOrder(keyPath: \.roastJokeIDs, values: VisibleListOrder.removing(
            offsets: offsets, visible: setListRoastJokes.map(\.id), stored: setList.roastJokeIDs
        ))
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

    private func updateSetOrder(keyPath: ReferenceWritableKeyPath<SetList, [UUID]>, values: [UUID]) {
        let previousIDs = setList[keyPath: keyPath]
        let previousDate = setList.dateModified
        guard previousIDs != values else { return }
        setList[keyPath: keyPath] = values
        setList.dateModified = Date()
        do {
            try JokeEditorPersistence.saveOrRestore {
                try modelContext.save()
            } restore: {
                setList[keyPath: keyPath] = previousIDs
                setList.dateModified = previousDate
            }
        } catch {
            operationError = "Could not update set: \(error.localizedDescription)"
            showingOperationError = true
        }
    }

    private func deleteSet() {
        let wasTrashed = setList.isTrashed
        let deletedDate = setList.deletedDate
        let modifiedDate = setList.dateModified
        setList.moveToTrash()
        do {
            try JokeEditorPersistence.saveOrRestore {
                try modelContext.save()
            } restore: {
                setList.isTrashed = wasTrashed
                setList.deletedDate = deletedDate
                setList.dateModified = modifiedDate
            }
            dismiss()
        } catch {
            operationError = "Could not move this set to Trash: \(error.localizedDescription)"
            showingOperationError = true
        }
    }
}

private enum SetDetailMode: String, CaseIterable, Identifiable {
    case arrange = "Arrange"
    case rehearse = "Rehearse"

    var id: Self { self }
}

/// Set rows expose the complete material, independently of library preview preferences.
private struct SetMaterialRow: View {
    let number: Int
    let total: Int
    let title: String
    let content: String
    var setup: String = ""
    var targetName: String?
    let isRehearsing: Bool
    var nextAction: (() -> Void)?

    @State private var isExpanded = false

    private var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled Joke" : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRehearsing {
                rowHeading
                    .accessibilityAddTraits(.isHeader)
                fullText

                if let nextAction {
                    Button(action: nextAction) {
                        Label("Next Joke", systemImage: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Moves to joke \(number + 1) of \(total).")
                } else {
                    Text("End of set")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    fullText
                        .padding(.top, 8)
                } label: {
                    rowHeading
                }
            }
        }
        .padding(.vertical, isRehearsing ? 12 : 6)
    }

    private var rowHeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(displayTitle)
                .foregroundStyle(.primary)
        }
        .font(isRehearsing ? .title3.weight(.semibold) : .headline)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joke \(number) of \(total): \(displayTitle)")
    }

    private var fullText: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let targetName, !targetName.isEmpty {
                Text("For \(targetName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !setup.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(setup)
                }
            }

            if content.isEmpty {
                Text("No joke text yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(content)
            }
        }
        .font(.body)
        .lineSpacing(isRehearsing ? 6 : 3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
