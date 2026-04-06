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
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppTheme.Colors.brand)
                    
                    Text("iCloud Sync")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor(AppTheme.Colors.inkBlack)
                    
                    Text("Back up and sync all your jokes, roasts, and recordings")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.Colors.surfaceElevated))
                
                // Status
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.Colors.textTertiary)
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(syncStatusColor)
                                    .frame(width: 8, height: 8)
                                
                                Text(syncStatusText)
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                    .foregroundColor(AppTheme.Colors.inkBlack)
                            }
                        }
                        
                        Spacer()
                        
                        if let lastSync = syncService.lastSyncDate {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Last Sync")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.Colors.textTertiary)
                                
                                Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.Colors.paperAged))
                    
                    // Sync Status Message
                    if case .syncing = syncService.syncStatus {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8, anchor: .center)
                            Text("Syncing to iCloud...")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.info)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.info.opacity(0.1)))
                    } else if case .success = syncService.syncStatus {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppTheme.Colors.success)
                            Text("Sync complete")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.success)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.success.opacity(0.1)))
                    } else if case .error(let message) = syncService.syncStatus {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(AppTheme.Colors.error)
                            Text(message)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.Colors.error)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.error.opacity(0.1)))
                    }
                    
                    // Issues Found
                    if !diagnostics.syncIssuesFound.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Issues Found")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            
                            ForEach(diagnostics.syncIssuesFound.prefix(3).indices, id: \.self) { index in
                                let issue = diagnostics.syncIssuesFound[index]
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(issue.description)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.Colors.inkBlack)
                                    Text(issue.suggestedFix)
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                }
                                .padding(.leading, 4)
                            }
                            
                            if diagnostics.syncIssuesFound.count > 3 {
                                Text("+ \(diagnostics.syncIssuesFound.count - 3) more issues")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                    }
                }
                
                // Toggle & Actions
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable iCloud Sync")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                                .foregroundColor(AppTheme.Colors.inkBlack)
                            
                            Text("Automatically backup your data")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(AppTheme.Colors.textSecondary)
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
                        .tint(AppTheme.Colors.brand)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.Colors.surfaceElevated))
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            Task { await syncService.syncNow() }
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Sync Now")
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.Colors.brand))
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
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.orange))
                            .foregroundColor(.white)
                        }
                        .disabled(syncService.syncStatus == .syncing || !syncService.isSyncEnabled)
                        .opacity(syncService.syncStatus == .syncing || !syncService.isSyncEnabled ? 0.6 : 1.0)
                    }
                    
                    Button(action: {
                        diagnostics.forceKeyValueSync()
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Force Settings Sync")
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.Colors.surfaceElevated))
                        .foregroundColor(AppTheme.Colors.inkBlack)
                    }
                }
                
                // What Gets Synced
                VStack(alignment: .leading, spacing: 12) {
                    Text("What Gets Synced")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundColor(AppTheme.Colors.inkBlack)
                    
                    VStack(spacing: 10) {
                        SyncItemRow(icon: "lightbulb.fill", label: "Thoughts & Ideas", detail: "Your notepad content and quick thoughts")
                        SyncItemRow(icon: "text.quote", label: "Jokes", detail: "All your jokes, folders, and categories")
                        SyncItemRow(icon: "flame.fill", label: "Roast Targets & Jokes", detail: "All roast targets and their jokes")
                        SyncItemRow(icon: "list.bullet.rectangle", label: "Set Lists", detail: "Your comedy set lists")
                        SyncItemRow(icon: "waveform", label: "Voice Recordings", detail: "All voice memos and recordings")
                        SyncItemRow(icon: "photo.on.rectangle", label: "Notebook Photos", detail: "Scanned notebook pages")
                        SyncItemRow(icon: "brain.head.profile", label: "Brainstorm Ideas", detail: "Your brainstorming sessions")
                        SyncItemRow(icon: "bubble.left.and.bubble.right", label: "Chat Messages", detail: "BitBuddy conversation history")
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.Colors.paperAged))
                
                // Info
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(AppTheme.Colors.info)
                                .font(.system(size: 13))
                            Text("Automatic Syncing")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.inkBlack)
                        }
                        Text("When enabled, your data syncs automatically when connected to WiFi or Cellular. Manual sync is also available.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineSpacing(1.5)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.info.opacity(0.08)))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(AppTheme.Colors.success)
                                .font(.system(size: 13))
                            Text("End-to-End Encrypted")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.inkBlack)
                        }
                        Text("Your data is encrypted in transit and at rest. Only you can access your jokes.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineSpacing(1.5)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.success.opacity(0.08)))
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
                                .font(.system(size: 15, weight: .semibold, design: .serif))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.Colors.surfaceElevated))
                        .foregroundColor(AppTheme.Colors.inkBlack)
                    }
                    .disabled(diagnostics.isRunningDiagnostics)
                    
                    if diagnostics.isRunningDiagnostics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Running diagnostics...")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.surfaceElevated))
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showingDetailedDiagnostics) {
            DiagnosticsDetailView()
        }
        .onAppear {
            Task {
                iCloudAvailable = await syncService.checkiCloudAvailability()
                if !iCloudAvailable {
                    syncService.errorMessage = "Sign in to iCloud in Settings to enable sync"
                }
                
                // Run initial diagnostics if not done yet
                if diagnostics.diagnosticResults.isEmpty {
                    await diagnostics.runComprehensiveDiagnostics()
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var syncStatusColor: Color {
        switch syncService.syncStatus {
        case .idle:
            return syncService.isSyncEnabled ? .blue : .gray
        case .syncing:
            return .blue
        case .success:
            return AppTheme.Colors.success
        case .error:
            return AppTheme.Colors.error
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
                .foregroundColor(AppTheme.Colors.brand)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.inkBlack)
                
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppTheme.Colors.success)
                .font(.system(size: 14))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.Colors.paperCream))
    }
}

#Preview {
    iCloudSyncSettingsView()
}
