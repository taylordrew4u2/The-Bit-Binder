//
//  ShareLibraryView.swift
//  thebitbinder
//
//  Simple user-facing entry point for sharing the BitBinder library with
//  another iCloud account.
//
//  Design choices
//  --------------
//  - Everyone you invite gets the same access (read + write). No per-person
//    permission picker, no read-only mode.
//  - The list of people you're sharing with is always visible.
//  - The technical migration step is hidden — a single progress line.
//

import SwiftUI
import CloudKit
import CoreData

@MainActor
struct ShareLibraryView: View {

    @State private var phase: Phase = .checkingStatus
    @State private var share: CKShare?
    @State private var participants: [CKShare.Participant] = []
    @State private var progressMessage = ""
    @State private var showStopSharingConfirm = false
    @State private var didCopyLink = false
    @State private var incomingShares: [IncomingShareEntry] = []
    @State private var welcomeBannerOwner: String?

    @State private var shareSheetPayload: ShareSheetPayload?

    private struct IncomingShareEntry: Identifiable {
        let id: NSManagedObjectID
        let workspaceID: NSManagedObjectID
        let ownerDisplayName: String
        let ownerEmail: String?
        let acceptedDate: Date?
    }

    private let persistence = PersistenceController.shared
    @ObservedObject private var migrator = SwiftDataToCoreDataMigrator.shared
    private let sharing = SharingService.shared
    private let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)

    enum Phase: Equatable {
        case checkingStatus
        case notShared
        case preparing
        case shared
        case failed(message: String)
    }

    private struct ShareSheetPayload: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    var body: some View {
        List {
            if let owner = welcomeBannerOwner {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You joined \(owner)'s library")
                                .font(.callout.weight(.semibold))
                            Text("Their jokes, brainstorms, set lists, and roasts are now available below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            switch phase {
            case .checkingStatus:
                checkingSection

            case .notShared:
                notSharedSection

            case .preparing:
                preparingSection

            case .shared:
                sharedSection

            case .failed(let message):
                failedSection(message)
            }

            // Always render incoming shares (libraries others shared with you),
            // regardless of whether you've shared your own. The user asked for
            // invites to be visible from the Shared Libraries surface.
            if !incomingShares.isEmpty {
                incomingSection
            }
        }
        .navigationTitle("Share Library")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            Task { await refreshStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBinderShareAccepted)) { note in
            let owner = (note.userInfo?["ownerName"] as? String) ?? "Library owner"
            withAnimation { welcomeBannerOwner = owner }
            Task {
                await refreshStatus()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                withAnimation { welcomeBannerOwner = nil }
            }
        }
        .sheet(item: $shareSheetPayload) { payload in
            CloudSharingControllerView(
                share: payload.share,
                container: payload.container
            ) {
                shareSheetPayload = nil
                Task { await refreshStatus() }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Stop sharing this library?",
            isPresented: $showStopSharingConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop Sharing", role: .destructive) {
                Task { await stopSharing() }
            }
            Button("Keep Sharing", role: .cancel) {}
        } message: {
            Text("Everyone you invited will lose access. Your own library stays on your device.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var checkingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var notSharedSection: some View {
        Section {
            Text("Share your library with another iCloud user. You'll both see edits live.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section {
            Button {
                Task { await beginSharing() }
            } label: {
                Label("Share My Library", systemImage: "person.crop.circle.badge.plus")
                    .font(.body.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var preparingSection: some View {
        Section {
            HStack(spacing: 10) {
                ProgressView()
                Text(migrator.liveStageMessage.isEmpty ? progressMessage : migrator.liveStageMessage)
            }
        }
    }

    @ViewBuilder
    private var sharedSection: some View {
        let joined = participants.filter { $0.acceptanceStatus == .accepted }
        let pending = participants.filter { $0.acceptanceStatus == .pending }
        let removed = participants.filter { $0.acceptanceStatus == .removed }

        if !joined.isEmpty {
            Section("Joined") {
                ForEach(Array(joined.enumerated()), id: \.offset) { _, participant in
                    SimpleParticipantRow(participant: participant)
                }
            }
        }

        if !pending.isEmpty {
            Section("Pending Invites") {
                ForEach(Array(pending.enumerated()), id: \.offset) { _, participant in
                    SimpleParticipantRow(participant: participant)
                }
            }
        }

        if joined.isEmpty && pending.isEmpty {
            Section("Shared With") {
                Text("Just you. Tap Invite More to add someone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !removed.isEmpty {
            Section("Removed") {
                ForEach(Array(removed.enumerated()), id: \.offset) { _, participant in
                    SimpleParticipantRow(participant: participant)
                }
            }
        }
        Section {
            Button {
                Task { await reopenShareSheet() }
            } label: {
                Label("Invite More People", systemImage: "person.crop.circle.badge.plus")
            }
            if let url = share?.url {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    didCopyLink = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        didCopyLink = false
                    }
                } label: {
                    Label(didCopyLink ? "Link Copied" : "Copy Invite Link",
                          systemImage: didCopyLink ? "checkmark" : "link")
                }
            }
            Button(role: .destructive) {
                showStopSharingConfirm = true
            } label: {
                Label("Stop Sharing", systemImage: "person.crop.circle.badge.xmark")
            }
        }
    }

    @ViewBuilder
    private var incomingSection: some View {
        Section("Libraries Shared With You") {
            ForEach(incomingShares) { entry in
                NavigationLink {
                    WorkspaceDetailView(workspaceID: entry.workspaceID, scope: "Shared")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.square.filled.and.at.rectangle")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.ownerDisplayName)
                                .font(.body)
                            if let email = entry.ownerEmail, email != entry.ownerDisplayName {
                                Text(email)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func failedSection(_ message: String) -> some View {
        Section {
            Label("Couldn't set up sharing", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await refreshStatus() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Status loading

    private func refreshStatus() async {
        do {
            try await persistence.loadStoresAsync()
        } catch {
            phase = .failed(message: CloudErrorClassifier.classify(error).userFacingMessage)
            return
        }

        // Always reload incoming (libraries others shared with you) — visible
        // even when you haven't shared your own.
        incomingShares = loadIncomingShares()

        guard let workspace = (try? persistence.currentWorkspace()) else {
            phase = .notShared
            return
        }

        do {
            let shareMap = try persistence.container.fetchShares(matching: [workspace.objectID])
            if let existing = shareMap[workspace.objectID] {
                share = existing
                participants = existing.participants.filter { $0.role != .owner }
                phase = .shared
            } else {
                phase = .notShared
            }
        } catch {
            phase = .failed(message: CloudErrorClassifier.classify(error).userFacingMessage)
        }
    }

    /// Pulls every workspace from the shared store, plus its owner identity
    /// from the associated CKShare, so the user can see what libraries
    /// they've joined.
    private func loadIncomingShares() -> [IncomingShareEntry] {
        guard let sharedStore = persistence.store(for: .shared) else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: BitBinderEntity.workspace.rawValue)
        request.affectedStores = [sharedStore]
        guard let workspaces = try? persistence.container.viewContext.fetch(request) else { return [] }

        return workspaces.compactMap { workspace -> IncomingShareEntry? in
            guard let shareMap = try? persistence.container.fetchShares(matching: [workspace.objectID]),
                  let share = shareMap[workspace.objectID] else {
                return IncomingShareEntry(
                    id: workspace.objectID,
                    workspaceID: workspace.objectID,
                    ownerDisplayName: "Unknown owner",
                    ownerEmail: nil,
                    acceptedDate: nil
                )
            }
            let owner = share.participants.first { $0.role == .owner }
            let displayName: String = {
                if let first = owner?.userIdentity.nameComponents?.givenName,
                   let last = owner?.userIdentity.nameComponents?.familyName {
                    return "\(first) \(last)"
                }
                if let email = owner?.userIdentity.lookupInfo?.emailAddress { return email }
                return "Library owner"
            }()
            return IncomingShareEntry(
                id: workspace.objectID,
                workspaceID: workspace.objectID,
                ownerDisplayName: displayName,
                ownerEmail: owner?.userIdentity.lookupInfo?.emailAddress,
                acceptedDate: nil
            )
        }
    }

    // MARK: - Actions

    private func beginSharing() async {
        phase = .preparing
        progressMessage = "Setting up your shared library…"

        do {
            try await persistence.loadStoresAsync()
        } catch {
            phase = .failed(message: CloudErrorClassifier.classify(error).userFacingMessage)
            return
        }

        if !migrator.hasMigrated {
            _ = await migrator.runIfNeeded()
            if !migrator.hasMigrated {
                phase = .failed(message: "Couldn't prepare your library for sharing.")
                return
            }
        }

        guard let workspace = try? persistence.currentWorkspace() else {
            phase = .failed(message: "No library workspace was found.")
            return
        }

        progressMessage = "Creating invitation…"
        do {
            let (share, container) = try await sharing.prepareShare(for: workspace)
            self.share = share
            self.participants = share.participants.filter { $0.role != .owner }
            self.phase = .shared
            self.shareSheetPayload = ShareSheetPayload(share: share, container: container)
        } catch {
            phase = .failed(message: CloudErrorClassifier.classify(error).userFacingMessage)
        }
    }

    private func reopenShareSheet() async {
        guard let share else {
            await beginSharing()
            return
        }
        shareSheetPayload = ShareSheetPayload(share: share, container: ckContainer)
    }

    private func stopSharing() async {
        guard let share else { return }
        phase = .preparing
        progressMessage = sharing.isOwner(of: share)
            ? "Stopping sharing…"
            : "Leaving share…"
        await sharing.endShare(share)
        self.share = nil
        self.participants = []
        await refreshStatus()
    }

    // MARK: - Helper for Settings badge

    /// Friendly status snippet for the Settings row badge.
    /// Reflects both directions:
    ///  - You sharing your own library: "1 person", "3 people", "Just you"
    ///  - You joined someone else's library: "Joined"
    ///  - Both: "Sharing + Joined"
    static func currentStatusSummary() -> String? {
        let persistence = PersistenceController.shared
        guard persistence.storesLoaded else { return nil }

        // Outgoing: do you share your own library?
        var outgoing: String? = nil
        if let workspace = try? persistence.currentWorkspace(),
           let shareMap = try? persistence.container.fetchShares(matching: [workspace.objectID]),
           let share = shareMap[workspace.objectID] {
            let invitees = share.participants.filter { $0.role != .owner }
            let accepted = invitees.filter { $0.acceptanceStatus == .accepted }.count
            if invitees.isEmpty {
                outgoing = "Just you"
            } else if accepted == 0 {
                outgoing = "\(invitees.count) invited"
            } else {
                outgoing = accepted == 1 ? "1 person" : "\(accepted) people"
            }
        }

        // Incoming: have you joined someone else's library?
        let incoming = hasJoinedSharedLibrary()

        switch (outgoing, incoming) {
        case (nil, false): return "Off"
        case (let o?, false): return o
        case (nil, true): return "Joined"
        case (let o?, true): return "\(o) · Joined"
        }
    }

    private static func hasJoinedSharedLibrary() -> Bool {
        let persistence = PersistenceController.shared
        guard let sharedStore = persistence.store(for: .shared) else { return false }
        let request = NSFetchRequest<NSManagedObject>(entityName: BitBinderEntity.workspace.rawValue)
        request.fetchLimit = 1
        request.affectedStores = [sharedStore]
        return (try? persistence.container.viewContext.fetch(request).first) != nil
    }
}

// MARK: - Simple participant row (no permission language; everyone has the same access)

private struct SimpleParticipantRow: View {
    let participant: CKShare.Participant

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(displayName)
                .font(.body)
            Spacer()
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch participant.acceptanceStatus {
        case .accepted: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .removed: return "minus.circle.fill"
        default: return "person.fill"
        }
    }

    private var iconColor: Color {
        switch participant.acceptanceStatus {
        case .accepted: return .green
        case .pending: return .orange
        case .removed: return .secondary
        default: return .secondary
        }
    }

    private var displayName: String {
        let identity = participant.userIdentity
        if let first = identity.nameComponents?.givenName,
           let last = identity.nameComponents?.familyName {
            return "\(first) \(last)"
        }
        if let email = identity.lookupInfo?.emailAddress { return email }
        if let phone = identity.lookupInfo?.phoneNumber { return phone }
        return "Invitee"
    }

    private var statusLabel: String {
        switch participant.acceptanceStatus {
        case .accepted: return "Joined"
        case .pending: return "Invited"
        case .removed: return "Removed"
        default: return ""
        }
    }
}
