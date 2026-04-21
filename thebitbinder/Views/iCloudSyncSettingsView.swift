//
//  iCloudSyncSettingsView.swift
//  thebitbinder
//
//  Created on 3/7/26.
//

import SwiftUI

struct iCloudSyncSettingsView: View {
    @StateObject private var syncService = iCloudSyncService.shared
    @StateObject private var diagnostics = iCloudSyncDiagnostics.shared
    @State private var showingSyncConfirmation = false
    @State private var isCheckingAvailability = false
    @State private var iCloudAvailable = true
    @State private var showingDetailedDiagnostics = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Status
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(syncStatusColor)
                                    .frame(width: 8, height: 8)
                                
                                Text(syncStatusText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        Spacer()
                        
                        if let lastSync = syncService.lastSyncDate {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Last Sync")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(UIColor.tertiaryLabel))
                                
                                Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                    
                    // Sync Status Message
                    if case .syncing = syncService.syncStatus {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8, anchor: .center)
                            Text("Syncing to iCloud...")
                                .font(.system(size: 13))
                                .foregroundColor(Color.bitbinderAccent)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bitbinderAccent.opacity(0.1)))
                    } else if case .success = syncService.syncStatus {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.bitbinderAccent)
                            Text("Sync complete")
                                .font(.system(size: 13))
                                .foregroundColor(Color.bitbinderAccent)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bitbinderAccent.opacity(0.1)))
                    } else if case .error(let message) = syncService.syncStatus {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    } else if let errorMessage = syncService.errorMessage, !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    }
                    
                    // Issues Found
                    if !diagnostics.syncIssuesFound.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color.bitbinderAccent)
                                Text("Issues Found")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.bitbinderAccent)
                            }
                            
                            ForEach(diagnostics.syncIssuesFound.prefix(3).indices, id: \.self) { index in
                                let issue = diagnostics.syncIssuesFound[index]
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.description)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(issue.suggestedFix)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 4)
                            }
                            
                            if diagnostics.syncIssuesFound.count > 3 {
                                Text("+ \(diagnostics.syncIssuesFound.count - 3) more issues")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bitbinderAccent.opacity(0.1)))
                    }
                }
                
                // Toggle & Actions
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable iCloud Sync")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            Text("Automatically backup your data")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { syncService.isSyncEnabled },
                            set: { newValue in
                                if newValue {
                                    Task { await syncService.enableiCloudSync() }
                                } else {
                                    syncService.disableiCloudSync()
                                }
                            }
                        ))
                        .tint(.accentColor)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            Task { await syncService.syncNow() }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Sync Now")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                            .foregroundColor(.white)
                        }
                        .disabled(syncService.syncStatus == .syncing || !syncService.isSyncEnabled)
                        .opacity(syncService.syncStatus == .syncing || !syncService.isSyncEnabled ? 0.6 : 1.0)
                        
                        Button(action: {
                            Task { await syncService.forceRefreshAllData() }
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Force Refresh")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bitbinderAccent))
                            .foregroundColor(.white)
                        }
                        .disabled(syncService.syncStatus == .syncing || !syncService.isSyncEnabled)
                        .opacity(syncService.syncStatus == .syncing || !syncService.isSyncEnabled ? 0.6 : 1.0)
                    }
                    
                    Button(action: {
                        Task { await diagnostics.forceKeyValueSync() }
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Force Settings Sync")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                        .foregroundColor(.primary)
                    }
                }
                
                // What Gets Synced
                VStack(alignment: .leading, spacing: 12) {
                    Text("What Gets Synced")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 10) {
                        SyncItemRow(icon: "lightbulb.fill", label: "Thoughts & Ideas", detail: "Your notepad content and quick thoughts")
                        SyncItemRow(icon: "text.quote", label: "Jokes", detail: "All your jokes, folders, and categories")
                        SyncItemRow(icon: "flame.fill", label: "Roast Targets & Jokes", detail: "All roast targets and their jokes")
                        SyncItemRow(icon: "list.bullet.rectangle", label: "Set Lists", detail: "Your comedy set lists")
                        SyncItemRow(icon: "waveform", label: "Voice Recordings", detail: "All voice memos and recordings")
                        SyncItemRow(icon: "photo.on.rectangle", label: "Photo Notebook", detail: "Scanned notebook pages")
                        SyncItemRow(icon: "brain.head.profile", label: "Brainstorm Ideas", detail: "Your brainstorming sessions")
                        SyncItemRow(icon: "bubble.left.and.bubble.right", label: "Chat Messages", detail: "BitBuddy conversation history")
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                
                // Info
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(Color.bitbinderAccent)
                                .font(.system(size: 13))
                            Text("Automatic Syncing")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Text("When enabled, your data syncs automatically when connected to WiFi or Cellular. Manual sync is also available.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(1.5)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.bitbinderAccent.opacity(0.08)))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(Color.bitbinderAccent)
                                .font(.system(size: 13))
                            Text("End-to-End Encrypted")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        Text("Your data is encrypted in transit and at rest. Only you can access your jokes.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(1.5)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.bitbinderAccent.opacity(0.08)))
                }
                
                // Diagnostics
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task {
                            await diagnostics.runComprehensiveDiagnostics()
                            showingDetailedDiagnostics = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Run Comprehensive Diagnostics")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemBackground)))
                        .foregroundColor(.primary)
                    }
                    .disabled(diagnostics.isRunningDiagnostics)
                    
                    if diagnostics.isRunningDiagnostics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Running diagnostics...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDetailedDiagnostics) {
            DiagnosticsDetailView()
        }
        .task {
            // .task cancels automatically when the view disappears — important
            // because checkiCloudAvailability() + runComprehensiveDiagnostics()
            // can take several seconds and the user may navigate away.
            iCloudAvailable = await syncService.checkiCloudAvailability()
            if !iCloudAvailable {
                syncService.errorMessage = "Sign in to iCloud in Settings to enable sync"
            }

            if diagnostics.diagnosticResults.isEmpty {
                await diagnostics.runComprehensiveDiagnostics()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .idle:
            return syncService.isSyncEnabled ? Color.accentColor : .gray
        case .syncing:
            return Color.accentColor
        case .success:
            return Color.accentColor
        case .error:
            return .red
        }
    }
    
    private var syncStatusText: String {
        switch syncService.syncStatus {
        case .idle:
            return syncService.isSyncEnabled ? "Ready" : "Disabled"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Up to date"
        case .error:
            return "Sync error"
        }
    }
}

struct SyncItemRow: View {
    let icon: String
    let label: String
    let detail: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.bitbinderAccent)
                .font(.system(size: 14))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemBackground)))
    }
}

private struct DiagnosticsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var diagnostics = iCloudSyncDiagnostics.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    LabeledContent("Status", value: statusText)
                    LabeledContent("Issues", value: "\(diagnostics.syncIssuesFound.count)")
                    LabeledContent("Checks Logged", value: "\(diagnostics.diagnosticResults.count)")
                }

                if diagnostics.syncIssuesFound.isEmpty {
                    Section("Issues") {
                        Text("No sync issues are currently flagged.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Issues") {
                        ForEach(Array(diagnostics.syncIssuesFound.enumerated()), id: \.offset) { _, issue in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(issue.description, systemImage: iconName(for: issue.severity))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(color(for: issue.severity))

                                Text(issue.suggestedFix)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Diagnostic Log") {
                    if diagnostics.diagnosticResults.isEmpty {
                        Text("No diagnostics have been run yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(diagnostics.diagnosticResults.enumerated()), id: \.offset) { _, result in
                            Text(result)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await diagnostics.runComprehensiveDiagnostics()
                        }
                    } label: {
                        if diagnostics.isRunningDiagnostics {
                            ProgressView()
                        } else {
                            Text("Run Again")
                        }
                    }
                    .disabled(diagnostics.isRunningDiagnostics)
                }
            }
        }
    }

    private var statusText: String {
        if diagnostics.isRunningDiagnostics {
            return "Running"
        }

        return diagnostics.syncIssuesFound.isEmpty ? "Healthy" : "Needs Attention"
    }

    private func color(for severity: iCloudSyncDiagnostics.SyncIssue.Severity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }

    private func iconName(for severity: iCloudSyncDiagnostics.SyncIssue.Severity) -> String {
        switch severity {
        case .critical:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }
}

#Preview {
    iCloudSyncSettingsView()
}
