//
//  WorkspaceQuickAddJokeView.swift
//  thebitbinder
//
//  Minimal write surface for the new Core Data + CloudKit stack.
//
//  Lets you create a Joke directly in a chosen Workspace (private or shared)
//  so you can verify on two iCloud accounts that:
//    - Owner-created jokes show up on the participant device.
//    - Participant-created jokes show up on the owner device.
//
//  This bypasses every existing SwiftData view code path and writes only to
//  the new persistence stack — used purely for cross-account-sync verification
//  ahead of the Phase 4 refactor.
//

import SwiftUI
import CoreData

@MainActor
struct WorkspaceQuickAddJokeView: View {

    let workspaceID: NSManagedObjectID
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let persistence = PersistenceController.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Optional title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                Section {
                    Text("Saves to the new Core Data + CloudKit stack only. Verify it appears on the other iCloud account's Sync Status → Browse Workspaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Joke")
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
                    .disabled(isSaving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let ctx = persistence.container.viewContext
        guard let workspace = try? ctx.existingObject(with: workspaceID) else {
            errorMessage = "Workspace no longer available."
            return
        }
        guard let entity = NSEntityDescription.entity(forEntityName: BitBinderEntity.joke.rawValue, in: ctx) else {
            errorMessage = "Joke entity not in model."
            return
        }
        let joke = NSManagedObject(entity: entity, insertInto: ctx)
        joke.setValue(UUID(), forKey: "id")
        joke.setValue(title.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "title")
        joke.setValue(content, forKey: "content")
        joke.setValue(Date(), forKey: "dateCreated")
        joke.setValue(Date(), forKey: "dateModified")
        joke.setValue(workspace, forKey: "workspace")

        do {
            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceQuickAddJokeView.save"
            )
        }
    }
}
