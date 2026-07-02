//
//  LineNotebookView.swift
//  thebitbinder
//
//  Plain-text "line notebook" — a simple lined notebook of text notes that
//  replaced the photo notebook as the main Notebook tab. Existing photo data
//  is preserved and reachable from Settings → Photo Notebook (Legacy).
//

import SwiftUI
import SwiftData

struct LineNotebookView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<NotebookNote> { !$0.isTrashed },
           sort: \NotebookNote.dateModified, order: .reverse)
    private var notes: [NotebookNote]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var searchText = ""
    @State private var selectedNote: NotebookNote?

    private var filteredNotes: [NotebookNote] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if notes.isEmpty && searchText.isEmpty {
                BitBinderEmptyState(
                    icon: "note.text",
                    title: "No Notes Yet",
                    subtitle: "Jot down premises, bits, and to-dos in a plain lined notebook.",
                    actionTitle: "New Note",
                    action: createNote,
                    roastMode: roastMode
                )
            } else {
                List {
                    ForEach(filteredNotes) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            NoteRowView(note: note)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                trash(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteNotes)
                }
                .listStyle(.insetGrouped)
                .readableWidth(DS.wideContentWidth)
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Notebook")
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: createNote) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New note")
            }
        }
        .navigationDestination(item: $selectedNote) { note in
            NoteEditorView(note: note)
        }
    }

    private func createNote() {
        let note = NotebookNote()
        modelContext.insert(note)
        try? modelContext.save()
        selectedNote = note
    }

    private func trash(_ note: NotebookNote) {
        note.moveToTrash()
        try? modelContext.save()
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            filteredNotes[index].moveToTrash()
        }
        try? modelContext.save()
    }
}

// MARK: - Row

private struct NoteRowView: View {
    let note: NotebookNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(note.dateModified, format: .dateTime.month().day().year())
                if !note.previewLine.isEmpty && note.previewLine != note.displayTitle {
                    Text("·")
                    Text(note.previewLine).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor

struct NoteEditorView: View {
    @Bindable var note: NotebookNote
    @Environment(\.modelContext) private var modelContext
    @FocusState private var contentFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $note.title)
                .font(.title3.weight(.semibold))
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.sm)

            Divider().padding(.horizontal, DS.Spacing.lg)

            TextEditor(text: $note.content)
                .font(.body)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, DS.Spacing.lg - 4)
                .focused($contentFocused)
        }
        .readableWidth(DS.wideContentWidth)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.title) { _, _ in touch() }
        .onChange(of: note.content) { _, _ in touch() }
        .onDisappear { save() }
    }

    /// Stamp the modified date as the user edits; SwiftData autosaves, but we
    /// persist explicitly on disappear so the row list reorders reliably.
    private func touch() {
        note.dateModified = Date()
    }

    private func save() {
        try? modelContext.save()
    }
}
