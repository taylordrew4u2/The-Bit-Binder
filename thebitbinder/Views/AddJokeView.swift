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
    @Query(filter: #Predicate<Joke> { !$0.isTrashed }) private var allJokes: [Joke]

    @State private var title = ""
    @State private var content = ""
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    @State private var hasRecoveredDraft = false
    @FocusState private var titleFocused: Bool
    @FocusState private var contentFocused: Bool
    @FocusState private var tagFocused: Bool

    var selectedFolder: JokeFolder?

    private var canSave: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tags already used across the corpus, ranked by frequency desc.
    private var existingTagPool: [String] {
        var counts: [String: Int] = [:]
        for joke in allJokes {
            for t in joke.tags {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                counts[trimmed, default: 0] += 1
            }
        }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }.map { $0.key }
    }

    /// Autocomplete suggestions matching the current draft prefix.
    private var tagSuggestions: [String] {
        let draft = tagDraft.trimmingCharacters(in: .whitespaces).lowercased()
        guard !draft.isEmpty else { return [] }
        let added = Set(tags.map { $0.lowercased() })
        return existingTagPool
            .filter { $0.lowercased().hasPrefix(draft) && !added.contains($0.lowercased()) }
            .prefix(6)
            .map { $0 }
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

                    // Tag entry — native chip row with autocomplete
                    tagSection

                    Divider()
                        .padding(.horizontal, 20)

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
                            tagFocused = false
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
    
    // MARK: - Tag entry section

    @ViewBuilder
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Active tag chips
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.subheadline)
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .imageScale(.small)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Inline entry field
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                TextField("Add tag", text: $tagDraft)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                    .focused($tagFocused)
                    .onSubmit { commitTagDraft() }
                    .onChange(of: tagDraft) { _, new in
                        if new.contains(",") || new.contains("\n") {
                            commitTagDraft()
                        }
                    }
                if !tagDraft.isEmpty {
                    Button(action: commitTagDraft) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 20)

            // Suggestions or recent quick-picks
            let suggestionList: [String] = tagDraft.isEmpty
                ? Array(existingTagPool.filter { t in !tags.contains(where: { $0.lowercased() == t.lowercased() }) }.prefix(8))
                : tagSuggestions
            if !suggestionList.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestionList, id: \.self) { s in
                            Button {
                                addTag(s)
                            } label: {
                                Text("#\(s)")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(UIColor.secondarySystemFill))
                                    .foregroundStyle(.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 10)
    }

    private func commitTagDraft() {
        let parts = tagDraft.split(whereSeparator: { $0 == "," || $0 == "\n" }).map(String.init)
        for raw in parts { addTag(raw) }
        tagDraft = ""
    }

    private func addTag(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Tag model strips commas at write-time; do the same here.
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }) {
            tags.append(cleaned)
        }
    }

    private func saveJoke() {
        guard !isSaving else { return }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Flush any pending tag draft so user-typed text isn't lost.
        commitTagDraft()

        isSaving = true
        haptic(.light)

        let joke = Joke(content: trimmedContent, title: trimmedTitle, folder: selectedFolder)
        if !tags.isEmpty {
            joke.tags = tags
        }
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
