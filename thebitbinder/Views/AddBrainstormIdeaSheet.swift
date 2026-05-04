//
//  AddBrainstormIdeaSheet.swift
//  thebitbinder
//
//  Sheet for adding new brainstorm ideas
//

import SwiftUI
import SwiftData

struct AddBrainstormIdeaSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var content = ""
    @State private var isVoiceNote: Bool
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false
    let initialText: String

    init(isVoiceNote: Bool = false, initialText: String = "") {
        _isVoiceNote = State(initialValue: isVoiceNote)
        self.initialText = initialText
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text(roastMode ? "What's the burn?" : "What's on your mind?")
                                .font(.body)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        TextEditor(text: $content)
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(minHeight: 160)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
             .toolbar {
                 ToolbarItem(placement: .cancellationAction) {
                     Button("Cancel") { dismiss() }
                         .foregroundColor(Color.bitbinderAccent)
                 }
                 ToolbarItem(placement: .confirmationAction) {
                     Button("Save") { saveIdea() }
                         .fontWeight(.semibold)
                         .foregroundColor(Color.bitbinderAccent)
                         .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                 }
             }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let draft = QuickCaptureDraftStore.loadBrainstormDraft(),
               !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content = draft
            } else if !initialText.isEmpty {
                content = initialText
            }
        }
        .onChange(of: content) { _, newValue in
            QuickCaptureDraftStore.saveBrainstormDraft(newValue)
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func saveIdea() {
        guard !isSaving else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        let idea = BrainstormIdea(content: trimmed, colorHex: BrainstormIdea.randomColor(), isVoiceNote: isVoiceNote)
        modelContext.insert(idea)
        do {
            try modelContext.save()
            QuickCaptureDraftStore.clearBrainstormDraft()
            dismiss()
        } catch {
            modelContext.delete(idea)
            isSaving = false
            print(" [AddBrainstormIdeaSheet] Failed to save idea: \(error)")
            saveErrorMessage = "Could not save thought. Your draft is preserved on this device."
            showSaveError = true
        }
    }
}

#Preview {
    AddBrainstormIdeaSheet()
        .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
