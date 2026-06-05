//
//  WorkspaceEditJokeView.swift
//  thebitbinder
//
//  Edit / soft-delete a single Joke stored in the new Core Data + CloudKit
//  stack. Used to verify on two iCloud accounts that updates from one device
//  propagate to the other through the shared CloudKit zone.
//

import SwiftUI
import CoreData

@MainActor
struct WorkspaceEditJokeView: View {

    let jokeID: NSManagedObjectID
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var isTrashed = false
    @State private var isReadOnly = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Form {
                if isReadOnly {
                    Section {
                        Text("You have read-only access to this shared workspace. Edits will be rejected.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Title") {
                    TextField("Title", text: $title)
                        .disabled(isReadOnly)
                }
                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 160)
                        .disabled(isReadOnly)
                }
                Section("Status") {
                    Toggle("Move to Trash", isOn: $isTrashed)
                        .disabled(isReadOnly)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Joke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || isReadOnly)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let ctx = persistence.container.viewContext
        guard let joke = try? ctx.existingObject(with: jokeID) else { return }
        title = (joke.value(forKey: "title") as? String) ?? ""
        content = (joke.value(forKey: "content") as? String) ?? ""
        isTrashed = (joke.value(forKey: "isTrashed") as? Bool) ?? false

        // If the joke lives in the shared store, check whether the local user
        // can write to it. NSPersistentCloudKitContainer's canUpdateRecord
        // returns false for read-only participants.
        if persistence.isShared(joke) {
            isReadOnly = !persistence.container.canUpdateRecord(forManagedObjectWith: joke.objectID)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let ctx = persistence.container.viewContext
        guard let joke = try? ctx.existingObject(with: jokeID) else {
            errorMessage = "Joke no longer available."
            return
        }
        joke.setValue(title, forKey: "title")
        joke.setValue(content, forKey: "content")
        joke.setValue(Date(), forKey: "dateModified")

        let wasTrashed = (joke.value(forKey: "isTrashed") as? Bool) ?? false
        if wasTrashed != isTrashed {
            joke.setValue(isTrashed, forKey: "isTrashed")
            joke.setValue(isTrashed ? Date() : nil, forKey: "deletedDate")
        }

        do {
            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceEditJokeView.save"
            )
        }
    }
}
