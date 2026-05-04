//
//  AddJokeView.swift
//  thebitbinder
//
//  A comfortable space to write a new joke.
//  Open canvas, generous room, auto-focused so you can start right away.
//

import SwiftUI
import SwiftData

struct AddJokeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<JokeFolder> { !$0.isTrashed }) private var folders: [JokeFolder]
    
    @State private var title = ""
    @State private var content = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    @State private var hasRecoveredDraft = false
    @FocusState private var titleFocused: Bool
    @FocusState private var contentFocused: Bool
    
    var selectedFolder: JokeFolder?
    
    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    
                    // Title field — feels like a page heading
                    TextField("Title (optional)", text: $title, axis: .vertical)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                        .focused($titleFocused)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    
                    // Folder badge
                    if let folder = selectedFolder {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                            Text(folder.name)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    }
                    
                    // Word count
                    if !content.isEmpty {
                        Text("\(content.split(separator: " ").count) words")
                            .font(.caption)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    
                    // Content editor — the main writing canvas
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("Start writing your joke…")
                                .font(.body)
                                .foregroundColor(Color(UIColor.placeholderText))
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                        
                        TextEditor(text: $content)
                            .font(.body)
                            .lineSpacing(6)
                            .frame(minHeight: 350)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .focused($contentFocused)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(UIColor.systemBackground))
            .navigationTitle("New Joke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveJoke()
                    }
                    .disabled(!canSave || isSaving)
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            contentFocused = false
                            titleFocused = false
                        }
                    }
                }
            }
            .onAppear {
                if let draft = QuickCaptureDraftStore.loadJokeDraft() {
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = draft.title
                    }
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        content = draft.content
                    }
                    hasRecoveredDraft = !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard scenePhase == .active else { return }
                    contentFocused = true
                }
            }
            .onChange(of: title) { _, newValue in
                QuickCaptureDraftStore.saveJokeDraft(title: newValue, content: content)
            }
            .onChange(of: content) { _, newValue in
                QuickCaptureDraftStore.saveJokeDraft(title: title, content: newValue)
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    
    private func saveJoke() {
        guard !isSaving else { return }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        haptic(.light)

        let joke = Joke(content: trimmedContent, title: trimmedTitle, folder: selectedFolder)
        modelContext.insert(joke)

        do {
            try modelContext.save()
            QuickCaptureDraftStore.clearJokeDraft()
            haptic(.success)
            NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
            dismiss()
        } catch {
            modelContext.delete(joke)
            isSaving = false
            haptic(.error)
            print("[AddJokeView] Failed to save joke: \(error)")
            saveErrorMessage = hasRecoveredDraft
                ? "Could not save joke. Your recovered draft is still preserved on this device."
                : "Could not save joke. Your draft is preserved on this device."
            showSaveError = true
        }
    }
}

#Preview {
    AddJokeView()
        .modelContainer(for: [Joke.self, JokeFolder.self], inMemory: true)
}
