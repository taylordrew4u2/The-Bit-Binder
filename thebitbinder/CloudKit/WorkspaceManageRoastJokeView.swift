//
//  WorkspaceManageRoastJokeView.swift
//  thebitbinder
//
//  Create or edit a RoastJoke in the new Core Data + CloudKit stack.
//
//  Roast jokes belong to a RoastTarget (the person being roasted), so the
//  create mode includes a target picker. Edit mode keeps the existing
//  target binding and lets the user re-assign.
//

import SwiftUI
import CoreData

@MainActor
struct WorkspaceManageRoastJokeView: View {

    enum Mode {
        case create(workspaceID: NSManagedObjectID, defaultTargetID: NSManagedObjectID?)
        case edit(jokeID: NSManagedObjectID)
    }

    let mode: Mode
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var setup = ""
    @State private var punchline = ""
    @State private var isTrashed = false
    @State private var isReadOnly = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var availableTargets: [TargetOption] = []
    @State private var selectedTargetID: NSManagedObjectID?

    private let persistence = PersistenceController.shared

    private struct TargetOption: Identifiable, Hashable {
        let id: NSManagedObjectID
        let name: String
    }

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
                Section("Who's this roast for?") {
                    if availableTargets.isEmpty {
                        Text("No roast targets in this workspace yet. Add a target first, then come back to write a roast for them.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Picker("Roast Target", selection: $selectedTargetID) {
                            ForEach(availableTargets) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }
                        .disabled(isReadOnly)
                    }
                }
                Section("Title") {
                    TextField("Optional title", text: $title)
                        .disabled(isReadOnly)
                }
                Section("Setup") {
                    TextEditor(text: $setup)
                        .frame(minHeight: 60)
                        .disabled(isReadOnly)
                }
                Section("Punchline") {
                    TextEditor(text: $punchline)
                        .frame(minHeight: 60)
                        .disabled(isReadOnly)
                }
                Section("Full Joke") {
                    TextEditor(text: $content)
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
                    .disabled(isSaving || isReadOnly || !canSave)
                }
            }
            .task { await load() }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Roast"
        case .edit: return "Edit Roast"
        }
    }

    private var canSave: Bool {
        guard selectedTargetID != nil else { return false }
        let hasText = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !setup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !punchline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText
    }

    // MARK: - Load

    private func load() async {
        let ctx = persistence.container.viewContext

        // Build the picker options from non-trashed RoastTargets in this
        // workspace (across both private + shared stores so participants
        // can write for any visible target).
        await loadAvailableTargets(in: ctx)

        switch mode {
        case .create(_, let defaultTargetID):
            selectedTargetID = defaultTargetID ?? availableTargets.first?.id
        case .edit(let jokeID):
            guard let joke = try? ctx.existingObject(with: jokeID) else { return }
            title = (joke.value(forKey: "title") as? String) ?? ""
            content = (joke.value(forKey: "content") as? String) ?? ""
            setup = (joke.value(forKey: "setup") as? String) ?? ""
            punchline = (joke.value(forKey: "punchline") as? String) ?? ""
            isTrashed = (joke.value(forKey: "isTrashed") as? Bool) ?? false
            if let target = joke.value(forKey: "target") as? NSManagedObject {
                selectedTargetID = target.objectID
            }
            if persistence.isShared(joke) {
                isReadOnly = !persistence.container.canUpdateRecord(forManagedObjectWith: joke.objectID)
            }
        }
    }

    private func loadAvailableTargets(in ctx: NSManagedObjectContext) async {
        let request = NSFetchRequest<NSManagedObject>(entityName: BitBinderEntity.roastTarget.rawValue)
        request.predicate = NSPredicate(format: "isTrashed == NO OR isTrashed == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        guard let results = try? ctx.fetch(request) else { return }
        availableTargets = results.map { target in
            TargetOption(
                id: target.objectID,
                name: (target.value(forKey: "name") as? String) ?? "(Unnamed)"
            )
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let ctx = persistence.container.viewContext

        guard let targetID = selectedTargetID,
              let target = try? ctx.existingObject(with: targetID) else {
            errorMessage = "Pick a roast target first."
            return
        }

        do {
            switch mode {
            case .create(let workspaceID, _):
                guard let workspace = try? ctx.existingObject(with: workspaceID) else {
                    errorMessage = "Workspace no longer available."
                    return
                }
                guard let entity = NSEntityDescription.entity(forEntityName: BitBinderEntity.roastJoke.rawValue, in: ctx) else {
                    errorMessage = "RoastJoke entity not in model."
                    return
                }
                let joke = NSManagedObject(entity: entity, insertInto: ctx)
                joke.setValue(UUID(), forKey: "id")
                joke.setValue(title, forKey: "title")
                joke.setValue(content, forKey: "content")
                joke.setValue(setup, forKey: "setup")
                joke.setValue(punchline, forKey: "punchline")
                joke.setValue(Date(), forKey: "dateCreated")
                joke.setValue(Date(), forKey: "dateModified")
                joke.setValue(workspace, forKey: "workspace")
                joke.setValue(target, forKey: "target")

            case .edit(let id):
                guard let joke = try? ctx.existingObject(with: id) else {
                    errorMessage = "Roast joke no longer available."
                    return
                }
                joke.setValue(title, forKey: "title")
                joke.setValue(content, forKey: "content")
                joke.setValue(setup, forKey: "setup")
                joke.setValue(punchline, forKey: "punchline")
                joke.setValue(target, forKey: "target")
                joke.setValue(Date(), forKey: "dateModified")
                let wasTrashed = (joke.value(forKey: "isTrashed") as? Bool) ?? false
                if wasTrashed != isTrashed {
                    joke.setValue(isTrashed, forKey: "isTrashed")
                    joke.setValue(isTrashed ? Date() : nil, forKey: "deletedDate")
                }
            }

            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceManageRoastJokeView.save"
            )
        }
    }
}
