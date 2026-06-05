//
//  WorkspaceDetailView.swift
//  thebitbinder
//
//  Read-only drill-in for a single Workspace from the new Core Data stack.
//
//  Shows the actual rows inside each child collection (jokes, set lists,
//  roast targets, etc.) so you can verify on two iCloud accounts that the
//  same content arrives on the participant device after share acceptance.
//
//  Also surfaces share management:
//    - For workspaces owned by the current user: list participants,
//      offer "Stop Sharing" (deletes the CKShare → workspace becomes
//      private again).
//    - For workspaces accepted from another user: show owner identity and
//      a Leave Share affordance (re-uses stopSharing on the participant
//      side which deletes the local CKShare association).
//

import SwiftUI
import CoreData
import CloudKit

@MainActor
struct WorkspaceDetailView: View {

    let workspaceID: NSManagedObjectID
    let scope: String          // "Private" or "Shared"

    @State private var workspace: NSManagedObject?
    @State private var share: CKShare?
    @State private var isPreparingShare = false
    @State private var isStoppingShare = false
    @State private var shareSheetPayload: ShareSheetPayload?
    @State private var actionError: String?
    @State private var quickAddEntity: BitBinderEntity?
    @State private var showEndShareConfirm = false

    private let persistence = PersistenceController.shared
    private let sharing = SharingService.shared

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    private static let displayedEntities: [(BitBinderEntity, relationshipName: String, label: String)] = [
        (.joke, "jokes", "Jokes"),
        (.jokeFolder, "jokeFolders", "Joke Folders"),
        (.setList, "setLists", "Set Lists"),
        (.notebookFolder, "notebookFolders", "Notebook Folders"),
        (.notebookPhotoRecord, "notebookPhotos", "Notebook Photos"),
        (.recording, "recordings", "Recordings"),
        (.roastTarget, "roastTargets", "Roast Targets"),
        (.roastJoke, "roastJokes", "Roast Jokes"),
        (.brainstormIdea, "brainstormIdeas", "Brainstorm Ideas"),
        (.importBatch, "importBatches", "Import Batches"),
        (.chatMessage, "chatMessages", "Chat Messages"),
    ]

    var body: some View {
        List {
            Section("Workspace") {
                if let workspace {
                    LabeledContent("Scope") {
                        Text(scope)
                            .font(.caption.bold())
                            .foregroundStyle(scope == "Shared" ? .orange : .green)
                    }
                    LabeledContent("ID") {
                        Text((workspace.value(forKey: "id") as? UUID)?.uuidString ?? "—")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let created = workspace.value(forKey: "dateCreated") as? Date {
                        LabeledContent("Created") {
                            Text(created.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Workspace no longer available.")
                        .foregroundStyle(.secondary)
                }
            }

            Section(sharedHeader) {
                if let share {
                    // Participants viewing someone else's library need to see
                    // the owner. Owners viewing their own library don't need
                    // to see themselves in their own list.
                    let visibleParticipants: [CKShare.Participant] = {
                        if scope == "Shared" {
                            return share.participants
                        }
                        return share.participants.filter { $0.role != .owner }
                    }()
                    ForEach(Array(visibleParticipants.enumerated()), id: \.offset) { _, participant in
                        ParticipantRow(participant: participant)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Only the owner can remove others, and never
                                // the owner themselves.
                                if scope == "Private" && participant.role != .owner {
                                    Button(role: .destructive) {
                                        Task { await removeParticipant(participant) }
                                    } label: {
                                        Label("Remove", systemImage: "person.crop.circle.badge.minus")
                                    }
                                }
                            }
                    }
                    Button(role: .destructive) {
                        showEndShareConfirm = true
                    } label: {
                        if isStoppingShare {
                            ProgressView()
                        } else {
                            Text(scope == "Shared" ? "Leave Share" : "Stop Sharing")
                        }
                    }
                    .disabled(isStoppingShare)
                } else {
                    Text(scope == "Shared"
                         ? "This workspace was shared with you, but no CKShare metadata is loaded yet."
                         : "Not currently shared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if scope == "Private" {
                        Button {
                            Task { await prepareShare() }
                        } label: {
                            if isPreparingShare {
                                ProgressView()
                            } else {
                                Label("Share This Workspace", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                        .disabled(isPreparingShare)
                    }
                }
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Quick Verify") {
                Menu {
                    Button {
                        quickAddEntity = .joke
                    } label: {
                        Label("Add Joke", systemImage: "text.bubble")
                    }
                    Button {
                        quickAddEntity = .brainstormIdea
                    } label: {
                        Label("Add Brainstorm Idea", systemImage: "lightbulb")
                    }
                    Button {
                        quickAddEntity = .setList
                    } label: {
                        Label("Add Set List", systemImage: "list.bullet.rectangle.portrait")
                    }
                    Button {
                        quickAddEntity = .roastTarget
                    } label: {
                        Label("Add Roast Target", systemImage: "person.crop.circle.badge.exclamationmark")
                    }
                    Button {
                        quickAddEntity = .roastJoke
                    } label: {
                        Label("Add Roast", systemImage: "flame")
                    }
                } label: {
                    Label("Add Record to This Workspace", systemImage: "plus.circle")
                }
                .disabled(workspace == nil)
                Text("Use this to push a record into the workspace and watch it appear on the other iCloud account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Self.displayedEntities, id: \.0) { entity, relationship, label in
                if let count = childCount(for: relationship), count > 0 {
                    Section("\(label) (\(count))") {
                        NavigationLink {
                            WorkspaceEntityListView(
                                workspaceID: workspaceID,
                                entity: entity,
                                relationshipName: relationship,
                                title: label
                            )
                        } label: {
                            Label("Browse \(label)", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
        }
        .navigationTitle("Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            Task { await refresh() }
        }
        .refreshable {
            await refresh()
        }
        .sheet(item: $shareSheetPayload) { payload in
            CloudSharingControllerView(share: payload.share, container: payload.container) {
                shareSheetPayload = nil
                Task { await refresh() }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            endShareDialogTitle,
            isPresented: $showEndShareConfirm,
            titleVisibility: .visible
        ) {
            Button(endShareConfirmLabel, role: .destructive) {
                Task { await stopSharing() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(endShareDialogMessage)
        }
        .sheet(item: $quickAddEntity) { entity in
            if let workspace {
                switch entity {
                case .joke:
                    WorkspaceQuickAddJokeView(workspaceID: workspace.objectID) {
                        Task { await refresh() }
                    }
                case .brainstormIdea:
                    WorkspaceManageBrainstormView(mode: .create(workspaceID: workspace.objectID)) {
                        Task { await refresh() }
                    }
                case .setList:
                    WorkspaceManageSetListView(mode: .create(workspaceID: workspace.objectID)) {
                        Task { await refresh() }
                    }
                case .roastTarget:
                    WorkspaceManageRoastTargetView(mode: .create(workspaceID: workspace.objectID)) {
                        Task { await refresh() }
                    }
                case .roastJoke:
                    WorkspaceManageRoastJokeView(mode: .create(workspaceID: workspace.objectID, defaultTargetID: nil)) {
                        Task { await refresh() }
                    }
                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Participant removal

    private func removeParticipant(_ participant: CKShare.Participant) async {
        guard let share else { return }
        // Mutate the participant list locally, then persist back via the
        // private database. NSPersistentCloudKitContainer doesn't expose
        // a higher-level "remove participant" call.
        share.removeParticipant(participant)
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
        do {
            _ = try await ckContainer.privateCloudDatabase.modifyRecords(
                saving: [share],
                deleting: []
            )
            DataOperationLogger.shared.logSuccess(
                "Removed share participant: \(participant.userIdentity.lookupInfo?.emailAddress ?? "<no email>")"
            )
            await refresh()
        } catch {
            actionError = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(
                error,
                operation: "WorkspaceDetailView.removeParticipant"
            )
        }
    }

    // MARK: - Loading

    private func refresh() async {
        try? await persistence.loadStoresAsync()
        workspace = persistence.container.viewContext.object(with: workspaceID)
        share = try? loadShare()
    }

    private func loadShare() throws -> CKShare? {
        guard let workspace else { return nil }
        let map = try persistence.container.fetchShares(matching: [workspace.objectID])
        return map[workspace.objectID]
    }

    private func childCount(for relationshipName: String) -> Int? {
        guard let workspace else { return nil }
        if let set = workspace.value(forKey: relationshipName) as? NSSet {
            return set.count
        }
        if let array = workspace.value(forKey: relationshipName) as? [NSManagedObject] {
            return array.count
        }
        return nil
    }

    // MARK: - Actions

    private func prepareShare() async {
        guard let workspace else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        actionError = nil
        do {
            let (share, ckContainer) = try await sharing.prepareShare(for: workspace)
            self.share = share
            shareSheetPayload = ShareSheetPayload(share: share, container: ckContainer)
        } catch {
            actionError = CloudErrorClassifier.classify(error).userFacingMessage
            DataOperationLogger.shared.logError(error, operation: "WorkspaceDetailView.prepareShare")
        }
    }

    private func stopSharing() async {
        guard let share else { return }
        isStoppingShare = true
        defer { isStoppingShare = false }
        actionError = nil
        // Role-aware: owner deletes the share; participant purges their local
        // copy of the shared zone.
        await sharing.endShare(share)
        await refresh()
    }

    // MARK: - End-share dialog copy (role aware)

    private var isParticipant: Bool {
        // Workspace lives in the shared store → user is a participant of
        // someone else's library.
        scope == "Shared"
    }

    private var endShareDialogTitle: String {
        isParticipant ? "Leave this shared library?" : "Stop sharing this library?"
    }

    private var endShareDialogMessage: String {
        isParticipant
            ? "You'll lose access to this library on this device. The owner and other people can keep using it."
            : "Everyone you invited will lose access. Your own jokes, brainstorms, set lists, and roasts stay safe on your device."
    }

    private var endShareConfirmLabel: String {
        isParticipant ? "Leave Share" : "Stop Sharing"
    }

    /// Header for the Sharing section that summarizes who has access.
    private var sharedHeader: String {
        guard let share else { return "Sharing" }
        // For participants, the section is the people in this library
        // (including the owner). For owners, it's their invitees.
        if scope == "Shared" { return "People in This Library" }
        let invitees = share.participants.filter { $0.role != .owner }
        let accepted = invitees.filter { $0.acceptanceStatus == .accepted }.count
        let pending = invitees.filter { $0.acceptanceStatus == .pending }.count
        if accepted == 0 && pending == 0 { return "Shared With" }
        if pending == 0 {
            return accepted == 1 ? "Shared With 1 Person" : "Shared With \(accepted) People"
        }
        if accepted == 0 {
            return pending == 1 ? "1 Invite Pending" : "\(pending) Invites Pending"
        }
        return "\(accepted) Joined · \(pending) Pending"
    }

}

// MARK: - Participant row

private struct ParticipantRow: View {
    let participant: CKShare.Participant

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(displayName)
                    .font(.caption)
                Spacer()
                Text(roleLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            Text(stateLabel + " · " + permissionLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var displayName: String {
        let identity = participant.userIdentity
        if let first = identity.nameComponents?.givenName,
           let last = identity.nameComponents?.familyName {
            return "\(first) \(last)"
        }
        if let email = identity.lookupInfo?.emailAddress {
            return email
        }
        if let phone = identity.lookupInfo?.phoneNumber {
            return phone
        }
        return "Participant"
    }

    private var roleLabel: String {
        switch participant.role {
        case .owner: return "Owner"
        case .administrator: return "Admin"
        case .privateUser: return "Invitee"
        case .publicUser: return "Public"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private var stateLabel: String {
        switch participant.acceptanceStatus {
        case .accepted: return "Accepted"
        case .pending: return "Pending"
        case .removed: return "Removed"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    private var permissionLabel: String {
        switch participant.permission {
        case .readOnly: return "Read-only"
        case .readWrite: return "Read + write"
        case .none: return "No access"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Per-entity list

@MainActor
struct WorkspaceEntityListView: View {
    let workspaceID: NSManagedObjectID
    let entity: BitBinderEntity
    let relationshipName: String
    let title: String

    @State private var rows: [EntityRow] = []
    @State private var isLoading = false
    @State private var editTarget: EditTarget?
    @State private var searchText = ""
    @State private var showTrashed = false

    private struct EditTarget: Identifiable {
        let id: NSManagedObjectID
        let entity: BitBinderEntity
    }

    private let persistence = PersistenceController.shared

    private struct EntityRow: Identifiable {
        let id: NSManagedObjectID
        let primary: String
        let secondary: String?
        let trashed: Bool
    }

    var body: some View {
        List {
            if isLoading && rows.isEmpty {
                ProgressView()
            } else if filteredRows.isEmpty {
                emptyHint
            } else {
                ForEach(filteredRows) { row in
                    rowContent(row)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search \(title)")
        .toolbar {
            if hasTrashedRows {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showTrashed) {
                        Label("Show Trashed", systemImage: showTrashed ? "trash.fill" : "trash")
                    }
                    .toggleStyle(.button)
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            Task { await load() }
        }
        .refreshable { await load() }
        .sheet(item: $editTarget) { target in
            switch target.entity {
            case .joke:
                WorkspaceEditJokeView(jokeID: target.id) {
                    Task { await load() }
                }
            case .brainstormIdea:
                WorkspaceManageBrainstormView(mode: .edit(ideaID: target.id)) {
                    Task { await load() }
                }
            case .setList:
                WorkspaceManageSetListView(mode: .edit(setListID: target.id)) {
                    Task { await load() }
                }
            case .roastTarget:
                WorkspaceManageRoastTargetView(mode: .edit(targetID: target.id)) {
                    Task { await load() }
                }
            case .roastJoke:
                WorkspaceManageRoastJokeView(mode: .edit(jokeID: target.id)) {
                    Task { await load() }
                }
            default:
                EmptyView()
            }
        }
    }

    private var isEditable: Bool {
        switch entity {
        case .joke, .brainstormIdea, .setList, .roastTarget, .roastJoke: return true
        default: return false
        }
    }

    /// Rows after applying the trash + search filters.
    private var filteredRows: [EntityRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rows.filter { row in
            if !showTrashed && row.trashed { return false }
            guard !trimmed.isEmpty else { return true }
            if row.primary.lowercased().contains(trimmed) { return true }
            if let secondary = row.secondary, secondary.lowercased().contains(trimmed) { return true }
            return false
        }
    }

    private var hasTrashedRows: Bool {
        rows.contains(where: { $0.trashed })
    }

    @ViewBuilder
    private var emptyHint: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Text("No matches for \u{201C}\(trimmed)\u{201D}.")
                .foregroundStyle(.secondary)
        } else if rows.isEmpty {
            Text("No rows in this collection.")
                .foregroundStyle(.secondary)
        } else {
            Text("All rows are in the trash. Toggle Show Trashed to see them.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func rowContent(_ row: EntityRow) -> some View {
        if isEditable {
            Button {
                editTarget = EditTarget(id: row.id, entity: entity)
            } label: {
                rowBody(row)
            }
            .buttonStyle(.plain)
        } else {
            rowBody(row)
        }
    }

    @ViewBuilder
    private func rowBody(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.primary)
                    .font(.body)
                    .lineLimit(2)
                if row.trashed {
                    Spacer()
                    Text("Trashed")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            if let secondary = row.secondary {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        try? await persistence.loadStoresAsync()
        let ctx = persistence.container.viewContext
        let workspace = ctx.object(with: workspaceID)
        let children: [NSManagedObject] = {
            if let set = workspace.value(forKey: relationshipName) as? NSSet {
                return set.allObjects as? [NSManagedObject] ?? []
            }
            if let array = workspace.value(forKey: relationshipName) as? [NSManagedObject] {
                return array
            }
            return []
        }()
        rows = children.prefix(200).map(extract).sorted { $0.primary < $1.primary }
    }

    private func extract(_ object: NSManagedObject) -> EntityRow {
        switch entity {
        case .joke, .roastJoke:
            let title = object.value(forKey: "title") as? String ?? ""
            let content = object.value(forKey: "content") as? String ?? ""
            return EntityRow(
                id: object.objectID,
                primary: title.isEmpty ? content : title,
                secondary: title.isEmpty ? nil : preview(content),
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .jokeFolder, .notebookFolder:
            return EntityRow(
                id: object.objectID,
                primary: object.value(forKey: "name") as? String ?? "(Unnamed folder)",
                secondary: nil,
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .setList:
            let name = object.value(forKey: "name") as? String ?? ""
            let notes = object.value(forKey: "notes") as? String ?? ""
            return EntityRow(
                id: object.objectID,
                primary: name.isEmpty ? "(Unnamed set)" : name,
                secondary: notes.isEmpty ? nil : preview(notes),
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .notebookPhotoRecord:
            return EntityRow(
                id: object.objectID,
                primary: object.value(forKey: "notes") as? String ?? "(Photo)",
                secondary: nil,
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .recording:
            let title = object.value(forKey: "title") as? String ?? "(Recording)"
            let duration = (object.value(forKey: "duration") as? Double) ?? 0
            return EntityRow(
                id: object.objectID,
                primary: title,
                secondary: String(format: "%.1fs", duration),
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .roastTarget:
            return EntityRow(
                id: object.objectID,
                primary: object.value(forKey: "name") as? String ?? "(Target)",
                secondary: object.value(forKey: "notes") as? String,
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .brainstormIdea:
            return EntityRow(
                id: object.objectID,
                primary: preview(object.value(forKey: "content") as? String ?? "(Idea)"),
                secondary: nil,
                trashed: (object.value(forKey: "isTrashed") as? Bool) ?? false
            )
        case .importBatch:
            return EntityRow(
                id: object.objectID,
                primary: object.value(forKey: "sourceFileName") as? String ?? "(Batch)",
                secondary: nil,
                trashed: false
            )
        case .chatMessage:
            return EntityRow(
                id: object.objectID,
                primary: preview(object.value(forKey: "text") as? String ?? ""),
                secondary: (object.value(forKey: "isUser") as? Bool) == true ? "User" : "Assistant",
                trashed: false
            )
        case .workspace, .importedJokeMetadata, .unresolvedImportFragment:
            return EntityRow(
                id: object.objectID,
                primary: object.entity.name ?? "(Object)",
                secondary: nil,
                trashed: false
            )
        }
    }

    private func preview(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        return String(collapsed.prefix(120))
    }
}
