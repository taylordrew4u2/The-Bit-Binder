//
//  SettingsView.swift
//  thebitbinder
//
//  Settings screen using standard iOS Settings patterns.
//

import SwiftUI
import SwiftData
import MessageUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var jokes: [Joke]
    @EnvironmentObject private var userPreferences: UserPreferences

    @StateObject private var syncService = iCloudSyncService.shared
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("appTextSize") private var appTextSizeRawValue = AppTextSize.standard.rawValue
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @FocusState private var nameFieldFocused: Bool

    private var appTextSize: Binding<AppTextSize> {
        Binding(
            get: { AppTextSize(rawValue: appTextSizeRawValue) ?? .standard },
            set: { appTextSizeRawValue = $0.rawValue }
        )
    }
    
    var body: some View {
        List {
            // MARK: - Profile
            Section {
                HStack {
                    if isEditingName {
                        TextField("Your name", text: $editingNameText)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.plain)
                            .focused($nameFieldFocused)
                            .onSubmit { saveName() }
                            .submitLabel(.done)
                        Button("Done") { saveName() }
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(userPreferences.userName.isEmpty ? "Set Your Name" : userPreferences.userName)
                            .font(.body.weight(.semibold))
                            .foregroundColor(userPreferences.userName.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button {
                            editingNameText = userPreferences.userName
                            isEditingName = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                guard scenePhase == .active else { return }
                                nameFieldFocused = true
                            }
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit display name")
                    }
                }
            } header: {
                Text("Name")
            }
            
            // MARK: - Mode Section
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $roastMode) {
                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .font(.body)
                                .foregroundColor(roastMode ? FirePalette.core : .secondary)
                                .frame(width: 24, height: 24)
                            Text("Roast Mode")
                                .font(.body.weight(.medium))
                        }
                    }
                    .tint(FirePalette.core)

                    if roastMode {
                        Text("Organize material by roast target. Ember palette active.")
                            .font(.caption)
                            .foregroundColor(FirePalette.ember)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            } footer: {
                Text("Organize material by roast target instead of folder.")
            }
            
            // MARK: - Buddy Section
            Section {
                Toggle(isOn: $userPreferences.bitBuddyEnabled) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(userPreferences.bitBuddyEnabled ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(userPreferences.bitBuddyEnabled ? .accentColor : .secondary)
                        }
                        Text("Buddy")
                            .font(.body.weight(.medium))
                    }
                }
                .tint(.accentColor)

            } footer: {
                Text(userPreferences.bitBuddyEnabled
                    ? "Your on-device writing partner for punch-ups and smarter joke extraction."
                    : "Turn on to get a writing partner for punch-ups and smarter joke extraction from files.")
            }

            // MARK: - Data Section
            Section {
                NavigationLink {
                    iCloudSyncSettingsView()
                } label: {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud")
                        Spacer()
                        syncStatusBadge
                    }
                }

                NavigationLink {
                    ShareLibraryView()
                } label: {
                    HStack {
                        Label("Share Library", systemImage: "person.2.crop.square.stack")
                        Spacer()
                        if let summary = ShareLibraryView.currentStatusSummary() {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                NavigationLink {
                    DataSafetyView()
                } label: {
                    Label("Privacy & Data Safety", systemImage: "shield.checkered")
                }
                
                NavigationLink {
                    TrashView()
                } label: {
                    HStack {
                        Label("Trash", systemImage: "trash")
                        Spacer()
                        let trashedCount = jokes.filter { $0.isTrashed }.count
                        if trashedCount > 0 {
                            Text("\(trashedCount)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Data")
            }
            
            
            // MARK: - Notifications Section
            DailyNotificationSection()
            
            // MARK: - Customize Section
            Section {
                Picker("Text Size", selection: appTextSize) {
                    ForEach(AppTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }

                NavigationLink {
                    AppSetupView(isFirstLaunch: false)
                        .environmentObject(userPreferences)
                } label: {
                    Label("Customize App", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("Customize")
            } footer: {
                Text("Change your text size, tabs, joke layout, and display preferences.")
            }

            // MARK: - Support Section
            Section {
                NavigationLink {
                    ShowMeAroundView()
                } label: {
                    Label("Show Me Around", systemImage: "figure.walk")
                }

                NavigationLink {
                    HelpFAQView()
                } label: {
                    Label("Help & FAQ", systemImage: "questionmark.circle")
                }
            } header: {
                Text("Support")
            }
            
            // MARK: - About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .listStyle(.insetGrouped)
        .readableWidth()
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused && isEditingName {
                saveName()
            }
        }
    }
    
    private func saveName() {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userPreferences.userName = trimmed
        }
        isEditingName = false
        nameFieldFocused = false
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "Unknown"
        }
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        if case .syncing = syncService.syncStatus {
            ProgressView()
                .scaleEffect(0.7)
        } else if case .error = syncService.syncStatus {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        } else if let lastSync = syncService.lastSyncDate {
            Text(Self.relativeDateFormatter.localizedString(for: lastSync, relativeTo: Date()))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail Composer

#if !targetEnvironment(macCatalyst)
struct MailComposerView: UIViewControllerRepresentable {
    let subject: String
    let attachmentURL: URL
    @Binding var isPresented: Bool
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody("Exported from BitBinder.", isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            let ext = attachmentURL.pathExtension.lowercased()
            let mimeType = ext == "pdf" ? "application/pdf" : ext == "zip" ? "application/zip" : "application/octet-stream"
            vc.addAttachmentData(data, mimeType: mimeType, fileName: attachmentURL.lastPathComponent)
        }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isPresented = false
        }
    }
}
#else
struct MailComposerView: View {
    let subject: String
    let attachmentURL: URL
    @Binding var isPresented: Bool
    var body: some View { EmptyView() }
}
#endif

// MARK: - Daily Notification Settings

struct DailyNotificationSection: View {
    @ObservedObject private var manager = NotificationManager.shared

    private var startDate: Binding<Date> {
        Binding(
            get: { dateFromMinutes(manager.startMinute) },
            set: { manager.startMinute = minutesFromDate($0) }
        )
    }
    private var endDate: Binding<Date> {
        Binding(
            get: { dateFromMinutes(manager.endMinute) },
            set: { manager.endMinute = minutesFromDate($0) }
        )
    }

    var body: some View {
        Section {
            Toggle(isOn: $manager.isEnabled) {
                Label("Daily Reminder", systemImage: "bell")
            }

            if manager.isEnabled {
                DatePicker("Between", selection: startDate, displayedComponents: .hourAndMinute)
                DatePicker("And", selection: endDate, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Notifications")
        }
    }

    private func dateFromMinutes(_ mins: Int) -> Date {
        Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .navigationTitle("Settings")
    }
    .modelContainer(for: [Joke.self, Recording.self], inMemory: true)
}
