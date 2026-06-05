//
//  WorkspaceManageSetListView.swift
//  thebitbinder
//
//  Create or edit a SetList in the new Core Data + CloudKit stack.
//

import SwiftUI
import CoreData

@MainActor
struct WorkspaceManageSetListView: View {

    enum Mode {
        case create(workspaceID: NSManagedObjectID)
        case edit(setListID: NSManagedObjectID)
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
                Section("Name") {
                    TextField("Set name", text: $name)
                        .disabled(isReadOnly)
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
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
        case .create: return "New Set List"
        case .edit: return "Edit Set List"
        }
    }

    private func load() async {
        guard case .edit(let id) = mode else { return }
        let ctx = persistence.container.viewContext
        guard let set = try? ctx.existingObject(with: id) else { return }
        name = (set.value(forKey: "name") as? String) ?? ""
        notes = (set.value(forKey: "notes") as? String) ?? ""
        isTrashed = (set.value(forKey: "isTrashed") as? Bool) ?? false
        if persistence.isShared(set) {
            isReadOnly = !persistence.container.canUpdateRecord(forManagedObjectWith: set.objectID)
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
                guard let entity = NSEntityDescription.entity(forEntityName: BitBinderEntity.setList.rawValue, in: ctx) else {
                    errorMessage = "SetList entity not in model."
                    return
                }
                let set = NSManagedObject(entity: entity, insertInto: ctx)
                set.setValue(UUID(), forKey: "id")
                set.setValue(name, forKey: "name")
                set.setValue(notes, forKey: "notes")
                set.setValue(Date(), forKey: "dateCreated")
                set.setValue(Date(), forKey: "dateModified")
                set.setValue(workspace, forKey: "workspace")

            case .edit(let id):
                guard let set = try? ctx.existingObject(with: id) else {
                    errorMessage = "Set list no longer available."
                    return
                }
                set.setValue(name, forKey: "name")
                set.setValue(notes, forKey: "notes")
                set.setValue(Date(), forKey: "dateModified")
                let wasTrashed = (set.value(forKey: "isTrashed") as? Bool) ?? false
                if wasTrashed != isTrashed {
                    set.setValue(isTrashed, forKey: "isTrashed")
                    set.setValue(isTrashed ? Date() : nil, forKey: "deletedDate")
                }
            }

            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceManageSetListView.save"
            )
        }
    }
}
