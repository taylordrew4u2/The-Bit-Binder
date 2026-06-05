//
//  WorkspaceManageBrainstormView.swift
//  thebitbinder
//
//  Create or edit a BrainstormIdea in the new Core Data + CloudKit stack.
//

import SwiftUI
import CoreData

@MainActor
struct WorkspaceManageBrainstormView: View {

    enum Mode {
        case create(workspaceID: NSManagedObjectID)
        case edit(ideaID: NSManagedObjectID)
    }

    let mode: Mode
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
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
                        Text("Read-only access — edits will be rejected by CloudKit.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Idea") {
                    TextEditor(text: $content)
                        .frame(minHeight: 140)
                        .disabled(isReadOnly)
                }
                if case .edit = mode {
                    Section("Status") {
                        Toggle("Move to Trash", isOn: $isTrashed)
                            .disabled(isReadOnly)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(navigationTitle)
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
                    .disabled(isSaving || isReadOnly || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Idea"
        case .edit: return "Edit Idea"
        }
    }

    private func load() async {
        guard case .edit(let id) = mode else { return }
        let ctx = persistence.container.viewContext
        guard let idea = try? ctx.existingObject(with: id) else { return }
        content = (idea.value(forKey: "content") as? String) ?? ""
        isTrashed = (idea.value(forKey: "isTrashed") as? Bool) ?? false
        if persistence.isShared(idea) {
            isReadOnly = !persistence.container.canUpdateRecord(forManagedObjectWith: idea.objectID)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let ctx = persistence.container.viewContext

        do {
            switch mode {
            case .create(let workspaceID):
                guard let workspace = try? ctx.existingObject(with: workspaceID) else {
                    errorMessage = "Workspace no longer available."
                    return
                }
                guard let entity = NSEntityDescription.entity(forEntityName: BitBinderEntity.brainstormIdea.rawValue, in: ctx) else {
                    errorMessage = "BrainstormIdea entity not in model."
                    return
                }
                let idea = NSManagedObject(entity: entity, insertInto: ctx)
                idea.setValue(UUID(), forKey: "id")
                idea.setValue(content, forKey: "content")
                idea.setValue(Date(), forKey: "dateCreated")
                idea.setValue("F5E6D3", forKey: "colorHex")
                idea.setValue(workspace, forKey: "workspace")

            case .edit(let id):
                guard let idea = try? ctx.existingObject(with: id) else {
                    errorMessage = "Idea no longer available."
                    return
                }
                idea.setValue(content, forKey: "content")
                let wasTrashed = (idea.value(forKey: "isTrashed") as? Bool) ?? false
                if wasTrashed != isTrashed {
                    idea.setValue(isTrashed, forKey: "isTrashed")
                    idea.setValue(isTrashed ? Date() : nil, forKey: "deletedDate")
                }
            }

            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceManageBrainstormView.save"
            )
        }
    }
}
