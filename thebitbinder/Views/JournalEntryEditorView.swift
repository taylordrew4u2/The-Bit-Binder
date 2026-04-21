//
//  JournalEntryEditorView.swift
//  thebitbinder
//
//  Editor for a single day's journal entry. Autosaves on every change.
//

import SwiftUI
import SwiftData

struct JournalEntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entry: DailyJournalEntry

    /// True when editing a past day via the backfill flow. Changes what we say
    /// in the header and hides the "completion" CTA chrome a little.
    let isBackfill: Bool

    // Local editing state. We mirror into the SwiftData model on change,
    // debouncing the save so typing stays smooth.
    @State private var freeform: String = ""
    @State private var answers: [String: String] = [:]
    @State private var mood: String = ""

    @State private var saveTask: Task<Void, Never>?

    @FocusState private var focusedPromptID: String?
    @FocusState private var freeformFocused: Bool

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.isComplete ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.isComplete ? "Complete" : "In progress")
                            .font(.subheadline.weight(.semibold))
                        Text(Self.headerFormatter.string(from: entry.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            Section("Prompts") {
                ForEach(DailyJournalPrompts.all) { prompt in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prompt.question)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Optional", text: bindingForAnswer(prompt.id), axis: .vertical)
                            .lineLimit(1...6)
                            .font(.body)
                            .focused($focusedPromptID, equals: prompt.id)
                            .submitLabel(.next)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                TextField("Write freely…", text: $freeform, axis: .vertical)
                    .lineLimit(6...20)
                    .font(.body)
                    .focused($freeformFocused)
            } header: {
                Text("Journal")
            } footer: {
                Text("Autosaved. One entry per day — you can come back and add more anytime.")
            }

            Section {
                MoodPicker(selection: $mood)
            } header: {
                Text("Mood")
            } footer: {
                Text("Optional.")
            }
        }
        .navigationTitle(isBackfill ? "Backfill Entry" : "Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    flushSaveNow()
                    dismiss()
                }
                .font(.body.weight(.semibold))
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedPromptID = nil
                    freeformFocused = false
                }
            }
        }
        .onAppear {
            freeform = entry.freeformJournal
            answers = entry.answers
            mood = entry.mood
        }
        .onChange(of: freeform) { _, _ in scheduleSave() }
        .onChange(of: mood) { _, _ in scheduleSave() }
        .onDisappear { flushSaveNow() }
    }

    // MARK: - Binding helpers

    private func bindingForAnswer(_ id: String) -> Binding<String> {
        Binding(
            get: { answers[id] ?? "" },
            set: { newValue in
                answers[id] = newValue
                scheduleSave()
            }
        )
    }

    // MARK: - Autosave

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s debounce
            if Task.isCancelled { return }
            persistChanges()
        }
    }

    private func flushSaveNow() {
        saveTask?.cancel()
        persistChanges()
    }

    private func persistChanges() {
        let wasComplete = entry.isComplete

        entry.freeformJournal = freeform
        entry.mood = mood
        for prompt in DailyJournalPrompts.all {
            let value = (answers[prompt.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            entry.setAnswer(value, for: prompt.id)
        }
        entry.touch()

        do {
            try modelContext.save()
        } catch {
            print(" [Journal] save failed: \(error)")
        }

        // If we just crossed from incomplete -> complete for today, suppress
        // any still-pending delivered reminder so we don't nag a finished user.
        if !wasComplete, entry.isComplete, entry.dateKey == DailyJournalEntry.todayKey {
            JournalReminderManager.shared.cancelTodayIfComplete(context: modelContext)
            haptic(.success)
        }
    }
}

// MARK: - Mood Picker

private struct MoodPicker: View {
    @Binding var selection: String

    private let options: [(label: String, value: String)] = [
        ("Off", ""),
        ("Low", "low"),
        ("Steady", "steady"),
        ("Good", "good"),
        ("Sharp", "sharp"),
    ]

    var body: some View {
        Picker("Mood", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
    }
}
