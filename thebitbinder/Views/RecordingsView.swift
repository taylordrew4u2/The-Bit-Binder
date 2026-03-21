//
//  RecordingsView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct RecordingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.dateCreated, order: .reverse) private var recordings: [Recording]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var searchText = ""
    @State private var showingQuickRecord = false
    
    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        } else {
            return recordings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredRecordings.isEmpty {
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.Colors.recordingsAccent.opacity(0.12), AppTheme.Colors.recordingsAccent.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppTheme.Colors.recordingsAccent, AppTheme.Colors.recordingsAccent.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(spacing: 8) {
                            Text("No recordings yet")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Tap the mic button to start recording")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredRecordings) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingRowView(recording: recording)
                            }
                        }
                        .onDelete(perform: deleteRecordings)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(roastMode ? "🔥 Burn Recordings" : "Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: roastMode ? "Search recordings" : "Search recordings")
            .toolbarBackground(
                roastMode ? AnyShapeStyle(AppTheme.Colors.roastSurface) : AnyShapeStyle(AppTheme.Colors.paperCream),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(roastMode ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQuickRecord = true
                    } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.title3)
                            .foregroundStyle(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.recordingsAccent)
                    }
                }
            }
            .sheet(isPresented: $showingQuickRecord) {
                StandaloneRecordingView()
            }
        }
    }
    
    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = filteredRecordings[index]
            
            // Determine the actual file URL (handle both relative and absolute paths)
            var fileURL: URL
            if recording.fileURL.hasPrefix("/") {
                fileURL = URL(fileURLWithPath: recording.fileURL)
            } else {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                fileURL = documentsPath.appendingPathComponent(recording.fileURL)
            }
            
            try? FileManager.default.removeItem(at: fileURL)
            modelContext.delete(recording)
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording
    @AppStorage("roastModeEnabled") private var roastMode = false
    private let accent = AppTheme.Colors.recordingsAccent

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("•")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 32, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(durationString(from: recording.duration), systemImage: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accent.opacity(0.85))
                    Spacer()
                    Text(recording.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 11))
                        .foregroundColor(roastMode ? Color.white.opacity(0.45) : AppTheme.Colors.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(accent.opacity(0.7))
                .padding(.leading, 12)
        }
        .padding(.vertical, 12)
    }
    
    private func durationString(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
