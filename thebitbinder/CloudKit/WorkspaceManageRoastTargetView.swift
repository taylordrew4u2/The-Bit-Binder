//
//  WorkspaceManageRoastTargetView.swift
//  thebitbinder
//
//  Create or edit a RoastTarget in the new Core Data + CloudKit stack.
//  RoastTargets are first-class shared content alongside Jokes and Brainstorm
//  Ideas, so they get their own create / edit surface here.
//

import SwiftUI
import CoreData

@MainActor
struct WorkspaceManageRoastTargetView: View {

    enum Mode {
        case create(workspaceID: NSManagedObjectID)
        case edit(targetID: NSManagedObjectID)
    }

    let mode: Mode
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
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
                Section("Who are you roasting?") {
                    TextField("Their name", text: $name)
                        .disabled(isReadOnly)
                }
                Section("Notes about them") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
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
                    .disabled(isSaving || isReadOnly || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await load() }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Roast Target"
        case .edit: return "Edit Roast Target"
        }
    }

    private func load() async {
        guard case .edit(let id) = mode else { return }
        let ctx = persistence.container.viewContext
        guard let target = try? ctx.existingObject(with: id) else { return }
        name = (target.value(forKey: "name") as? String) ?? ""
        notes = (target.value(forKey: "notes") as? String) ?? ""
        isTrashed = (target.value(forKey: "isTrashed") as? Bool) ?? false
        if persistence.isShared(target) {
            isReadOnly = !persistence.container.canUpdateRecord(forManagedObjectWith: target.objectID)
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
                guard let entity = NSEntityDescription.entity(forEntityName: BitBinderEntity.roastTarget.rawValue, in: ctx) else {
                    errorMessage = "RoastTarget entity not in model."
                    return
                }
                let target = NSManagedObject(entity: entity, insertInto: ctx)
                target.setValue(UUID(), forKey: "id")
                target.setValue(name, forKey: "name")
                target.setValue(notes, forKey: "notes")
                target.setValue(Date(), forKey: "dateCreated")
                target.setValue(Date(), forKey: "dateModified")
                target.setValue(Int16(3), forKey: "openingRoastCount")
                target.setValue(workspace, forKey: "workspace")

            case .edit(let id):
                guard let target = try? ctx.existingObject(with: id) else {
                    errorMessage = "Roast target no longer available."
                    return
                }
                target.setValue(name, forKey: "name")
                target.setValue(notes, forKey: "notes")
                target.setValue(Date(), forKey: "dateModified")
                let wasTrashed = (target.value(forKey: "isTrashed") as? Bool) ?? false
                if wasTrashed != isTrashed {
                    target.setValue(isTrashed, forKey: "isTrashed")
                    target.setValue(isTrashed ? Date() : nil, forKey: "deletedDate")
                }
            }

            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceManageRoastTargetView.save"
            )
        }
    }
}
