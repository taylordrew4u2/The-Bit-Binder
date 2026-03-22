# 🔧 BitBinder — Comprehensive Debug Workflow

> **App Version:** v9.4  
> **Architecture:** SwiftUI + SwiftData + CloudKit (iCloud.666bit)  
> **AI Backend:** Foundation Models (local) → Local Fallback → Gemini 2.0 Flash (import only)  
> **Last Updated:** 2026-03-22

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Startup & Initialization Debug](#2-startup--initialization-debug)
3. [SwiftData / ModelContainer Debug](#3-swiftdata--modelcontainer-debug)
4. [CloudKit & iCloud Sync Debug](#4-cloudkit--icloud-sync-debug)
5. [Import Pipeline Debug](#5-import-pipeline-debug)
6. [BitBuddy AI Chat Debug](#6-bitbuddy-ai-chat-debug)
7. [Audio Recording & Transcription Debug](#7-audio-recording--transcription-debug)
8. [Roast Mode Debug](#8-roast-mode-debug)
9. [Data Protection & Migration Debug](#9-data-protection--migration-debug)
10. [Memory & Performance Debug](#10-memory--performance-debug)
11. [Background Tasks Debug](#11-background-tasks-debug)
12. [UI / Navigation Debug](#12-ui--navigation-debug)
13. [Common Error Patterns & Fixes](#13-common-error-patterns--fixes)
14. [Log Tags Quick Reference](#14-log-tags-quick-reference)
15. [Nuclear Options](#15-nuclear-options)

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                     thebitbinderApp                           │
│  @main → ModelContainer (4-tier fallback) → ContentView      │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐   ┌──────────────────┐                 │
│  │  AppDelegate     │   │ AppStartupCoord  │                 │
│  │  • Audio session │   │ • DataProtection │                 │
│  │  • BGTasks       │   │ • DataValidation │                 │
│  │  • CloudKit push │   │ • DataMigration  │                 │
│  │  • iCloud Drive  │   │ • SchemaDeploymt │                 │
│  └─────────────────┘   └──────────────────┘                 │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              ContentView (MainTabView)                │    │
│  │  Screens: Notepad | Brainstorm | Jokes | SetLists    │    │
│  │           Recordings | Notebook | Settings           │    │
│  │  Roast Mode: Jokes | Settings (only)                 │    │
│  │  Side Menu → BitBuddy Chat (sheet)                   │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                 Data Layer                            │    │
│  │  SwiftData Models:                                    │    │
│  │    Joke, JokeFolder, Recording, SetList,             │    │
│  │    RoastTarget, RoastJoke, BrainstormIdea,           │    │
│  │    NotebookPhotoRecord, ImportBatch,                  │    │
│  │    ImportedJokeMetadata, UnresolvedImportFragment,    │    │
│  │    ChatMessage                                        │    │
│  │                                                      │    │
│  │  Storage: default.store (SQLite)                      │    │
│  │  Sync:    CloudKit private DB (iCloud.666bit)         │    │
│  │  KV:      iCloudKeyValueStore (NSUbiquitousKVStore)   │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │               External Services                       │    │
│  │  • Gemini 2.0 Flash (joke extraction, 1k/day limit)  │    │
│  │  • Apple Speech Framework (transcription)             │    │
│  │  • Vision Framework (OCR)                             │    │
│  │  • PDFKit (text extraction)                           │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### Key Singletons (all `@MainActor` unless noted)

| Service | Access | Thread Safety |
|---------|--------|---------------|
| `AppStartupCoordinator` | `@StateObject` in App | `@MainActor` |
| `iCloudSyncService` | `.shared` | `@MainActor` |
| `DataProtectionService` | `.shared` | `@MainActor` |
| `DataValidationService` | `.shared` | `@MainActor` |
| `DataMigrationService` | `.shared` | `@MainActor` |
| `DataOperationLogger` | `.shared` | DispatchQueue (file I/O) |
| `BitBuddyService` | `.shared` | `@MainActor` |
| `AuthService` | `.shared` | `@MainActor` |
| `ImportPipelineCoordinator` | `.shared` | Not actor-isolated |
| `GeminiJokeExtractor` | `.shared` | Not actor-isolated |
| `AudioRecordingService` | Per-view `@StateObject` | Main thread |
| `AudioTranscriptionService` | `.shared` | Not actor-isolated |
| `MemoryManager` | `.shared` | NSLock-protected |
| `SchemaDeploymentService` | `.shared` | `@unchecked Sendable` |

---

## 2. Startup & Initialization Debug

### Boot Sequence (in order)

```
1. AppDelegate.didFinishLaunchingWithOptions
   ├── MemoryManager.shared initialized
   ├── iCloudKeyValueStore.shared initialized
   ├── Audio session configured (.playAndRecord)
   ├── Notification scheduling
   ├── Register for remote notifications (CloudKit push)
   ├── Register background tasks (666bit.refresh, 666bit.sync)
   ├── iCloud Drive ubiquity container init (background thread)
   └── CloudKit account status check (async Task)

2. thebitbinderApp.sharedModelContainer (computed once, lazy)
   ├── Schema with all 12 model types
   ├── Emergency backup of existing store
   ├── Tier 1: Persistent + CloudKit (.private "iCloud.666bit")
   ├── Tier 2: Persistent, no CloudKit (same file)
   ├── Tier 3: Wipe corrupted files + fresh store
   └── Tier 4: In-memory container (CATASTROPHIC)

3. thebitbinderApp.body .task
   ├── performAggressiveCloudKitCleanup() ← one-time zone repair
   ├── Wire modelContext into iCloudSyncService
   ├── Register for remote push notifications
   ├── CloudKitResetUtility.logContainerInfo() (DEBUG only)
   ├── AppStartupCoordinator.start()
   │   ├── DataProtectionService.checkVersionAndBackupIfNeeded()
   │   └── Brief 0.25s sleep
   └── AppStartupCoordinator.completeDataProtectionWithContext()
       ├── cleanupCorruptedCloudKitRecords() ← one-time
       ├── DataValidationService.validateDataIntegrity()
       ├── DataMigrationService.handleSchemaChanges()
       ├── SchemaDeploymentService.logSchemaFields()
       ├── SchemaDeploymentService.ensureSchemaDeployed()
       └── DataMigrationService.performSafeMigration()
```

### 🔴 What to look for in console at startup

| Log Prefix | Meaning | Severity |
|-----------|---------|----------|
| `✅ [ModelContainer] Persistent + CloudKit ready` | Normal boot | OK |
| `⚠️ [ModelContainer] CloudKit failed … local-only fallback` | CloudKit unavailable | Warning |
| `❌ [ModelContainer] Local store failed` | Store corruption | Critical |
| `🆘 [ModelContainer] EMERGENCY: Created in-memory container` | All data will be lost | CATASTROPHIC |
| `🚨 [AppStartup] CRITICAL: Significant data loss detected!` | Entity counts dropped | Critical |
| `✅ [CloudKit] Schema cleanup already completed` | Normal (already fixed) | OK |
| `🔧 [CloudKit] Running one-time schema-mismatch repair…` | Zone delete happening | Info |
| `❌ [Audio] Failed to configure audio session` | Recording won't work | Error |

### Debug Steps: App won't start / stuck on launch screen

1. **Check `AppStartupCoordinator.isReady`** — UI shows `LaunchScreenView` until this is `true`
2. Check console for `[ModelContainer]` messages — if you see `CATASTROPHIC FAILURE`, the store file is corrupted
3. Check console for `[AppStartup]` — if `start()` hangs, it's likely the data protection sequence
4. Check console for `[CloudKit]` — zone repair can take 5-10s on slow networks
5. **Quick fix:** Delete app data and reinstall. CloudKit will re-sync from cloud if available.

---

## 3. SwiftData / ModelContainer Debug

### Store Location
```
~/Library/Application Support/default.store
~/Library/Application Support/default.store-shm
~/Library/Application Support/default.store-wal
```

### Schema (12 model types)
```swift
Joke, JokeFolder, Recording, SetList,
NotebookPhotoRecord, RoastTarget, RoastJoke,
BrainstormIdea, ImportBatch, ImportedJokeMetadata,
UnresolvedImportFragment, ChatMessage
```

### Key Relationships (CloudKit REFERENCE fields)
- `Joke.folder → JokeFolder` (optional)
- `ImportedJokeMetadata.batch → ImportBatch`
- `UnresolvedImportFragment.batch → ImportBatch`
- `RoastJoke → RoastTarget` (inverse relationship)

### 🔴 Common SwiftData Issues

#### 1. STRING vs REFERENCE Mismatch
**Symptom:** CloudKit sync error loop:
```
"invalid attempt to set value type STRING for field 'CD_folder'
 for type 'CD_Joke', defined to be: REFERENCE"
```
**Fix:** `CloudKitResetUtility.repairCorruptedZone()` deletes the CloudKit zone, forcing CoreData to re-export with correct types. This runs automatically on first launch after the fix is deployed.

**Manual fix:** Set `UserDefaults.standard.set(false, forKey: "cloudkit_schema_cleanup_v2")` to force re-run.

#### 2. Model Context Not Saved
**Symptom:** Data disappears after app restart
**Debug:**
- Search console for `CONTEXT_SAVE` logs (if using `saveWithLogging()`)
- Check `.onChange(of: scenePhase)` — saves happen when app goes to background/active
- SmartImportReviewView calls `modelContext.save()` explicitly after import

#### 3. Emergency Backups ~~Filling Disk~~ (Auto-Cleaned)
**Location:** `~/Library/Application Support/emergency_backup_*.store`
**Status:** ✅ Fixed — `DataProtectionService.cleanupEmergencyBackups()` now runs on every launch.
- Keeps only the **3 most recent** emergency backups
- Deletes any older than **7 days**
- Also cleans `corrupted_store_backup_*.store` files
- Logs freed space: `🧹 [DataProtection] Cleaned up N emergency backup(s), freed X`

#### 4. Data Validation Failures
**Check:** `DataOperationLogger.shared.getCurrentLog()` or look for `[DataValidation]` in console.

**Validation checks:**
- Empty joke content
- Missing dates
- Orphaned relationships
- Entity count drops (significant data loss detection)

---

## 4. CloudKit & iCloud Sync Debug

### Container: `iCloud.666bit`
### Zone: `com.apple.coredata.cloudkit.zone` (private database)

### Sync Flow
```
Local write → SwiftData auto-export → CloudKit private DB
                                           ↓
                                     Silent push notification
                                           ↓
AppDelegate.didReceiveRemoteNotification → .NSPersistentStoreRemoteChange
                                           ↓
iCloudSyncService.handleRemoteChange → 2s debounce → processRemoteChange
                                           ↓
                                     Post "iCloudDataDidChange"
```

### 🔴 Sync Debug Steps

#### 1. Check iCloud Account Status
Console should show: `✅ [CloudKit] iCloud account available — sync enabled`

If not:
- `⚠️ [CloudKit] No iCloud account` → User not signed into iCloud
- `⚠️ [CloudKit] iCloud restricted` → Parental controls / MDM
- `⚠️ [CloudKit] iCloud temporarily unavailable` → Apple servers down

#### 2. Check Remote Notification Registration
- `✅ [CloudKit] Registered for remote notifications` → Good
- `⚠️ [CloudKit] Failed to register` → Push entitlement missing or simulator

#### 3. Verify Sync is Enabled
```swift
iCloudSyncService.shared.isSyncEnabled  // must be true
iCloudSyncService.shared.syncStatus     // .idle, .syncing, .success, .error
iCloudSyncService.shared.lastSyncDate   // when last sync happened
```

#### 4. Force Sync Trigger
```swift
await iCloudSyncService.shared.performFullSync()
```

#### 5. CloudKit Dashboard
Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/) → Container: `iCloud.666bit` → Private Database → Zone: `com.apple.coredata.cloudkit.zone`

Check for:
- Record types matching `CD_Joke`, `CD_JokeFolder`, etc.
- Field types (REFERENCE vs STRING on relationship fields)
- Record count vs local count

#### 6. Common Sync Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Zone corrupted | Permanent error loop in console | `CloudKitResetUtility.repairCorruptedZone()` |
| Schema mismatch | `invalid attempt to set value type` | Delete zone, let CoreData re-export |
| Rate limiting | `CKError.requestRateLimited` | Wait, retry with exponential backoff |
| Network issues | `CKError.networkFailure` | Check connectivity |
| Quota exceeded | `CKError.quotaExceeded` | User's iCloud storage full |
| Merge conflicts | Data different on two devices | SwiftData uses last-writer-wins |

### iCloudKeyValueStore Synced Keys
```swift
SyncedKeys.iCloudSyncEnabled     // bool
SyncedKeys.lastSyncDate          // timestamp
SyncedKeys.termsAccepted         // bool
SyncedKeys.userId                // UUID string
SyncedKeys.notepadText           // string (Notepad content)
```

---

## 5. Import Pipeline Debug

### Pipeline Stages
```
File URL → Stage 1: File Type Detection
         → Stage 2: Text Extraction (PDFKit / Vision OCR / Document Text)
         → Stage 3: Line Normalization (merge fragments, clean headers/footers)
         → Stage 4: Full Text Assembly (merge all pages)
         → Stage 5: Gemini 2.0 Flash Extraction (AI joke detection)
         → Stage 6: Map to ImportedJoke objects
         → ImportPipelineResult (autoSaved + reviewQueue + rejected)
         → SmartImportReviewView (user review)
         → Save to SwiftData
```

### Entry Points
1. **ModernImportView** → file picker → `FileImportService.importWithPipeline(from:)`
2. **AudioImportView** → audio file → `AudioTranscriptionService.transcribe()` → text → import
3. **DocumentPickerView** → manual file selection
4. **DocumentScannerView** → camera OCR → text → import

### Gemini Rate Limiting
```
Daily limit: 1,000 requests (free tier)
Tracking: UserDefaults keys: gemini_daily_request_count, gemini_last_request_date
Reset: Midnight (based on Calendar day components)
```

### 🔴 Import Debug Steps

#### 1. File Not Importing
```
Console search: "[ImportPipeline]" or "Stage 1" or "Stage 2"
```
Check:
- File type detection result
- Extraction method selected
- Number of pages/lines extracted

#### 2. Gemini Rate Limit Hit
**Symptom:** Orange banner in SmartImportReviewView: "Daily Gemini request limit reached"
**Console:** `⚠️ Gemini error: Daily Gemini request limit reached`
**Fix:** Wait until tomorrow, or increase `DailyRequestTracker.dailyLimit` for testing

#### 3. Gemini API Key Missing
**Symptom:** `GeminiRateLimitError.keyNotConfigured`
**Fix:** Add `GEMINI_API_KEY` to `Secrets.plist`
```xml
<key>GEMINI_API_KEY</key>
<string>YOUR_API_KEY_HERE</string>
```

#### 4. No Jokes Detected
**Symptom:** Empty review screen
**Debug:**
- Check Gemini response in console: `"Gemini returned 0 joke(s)"`
- Check extracted text quality: `"Sending X chars to Gemini 2.0 Flash"`
- If 0 chars → text extraction failed (check OCR confidence, PDF text layer)
- Try the file in a PDF viewer to see if it has a text layer

#### 5. Review Screen Issues
**SmartImportReviewView** depends on `ImportReviewViewModel`:
- `loadAllItems(from:)` loads both auto-saved and review-queue jokes
- Swipe gesture threshold: 100pt
- Card animation: 0.3s ease-out
- Save triggers `modelContext.save()` + 0.5s CloudKit delay

#### 6. Pipeline Stats
```swift
result.pipelineStats.totalPagesProcessed
result.pipelineStats.totalLinesExtracted
result.pipelineStats.totalBlocksCreated
result.pipelineStats.autoSavedCount
result.pipelineStats.reviewQueueCount
result.pipelineStats.processingTimeSeconds
result.pipelineStats.averageConfidence
```

---

## 6. BitBuddy AI Chat Debug

### Backend Selection Order
```
1. FoundationModelsBitBuddyService (Apple on-device)
   → Currently returns isAvailable = false (iOS 18+ stub)
2. LocalFallbackBitBuddyService (rule-based, always available)
```

### Response Format
BitBuddy expects JSON responses:
```json
{
  "response": "Display text",
  "action": { "type": "add_joke", "joke": "joke text" }
}
```

### 🔴 Chat Debug Steps

#### 1. BitBuddy Not Responding
- Check `BitBuddyService.shared.isConnected` — should be `true` after first message
- Check `BitBuddyService.shared.isLoading` — stuck `true` means backend hung
- Check backend: `BitBuddyService.shared.backendName` — should be "Local Fallback" or "Foundation Models"

#### 2. Auth Issues
`AuthService` is a stub — `ensureAuthenticated()` always succeeds. If somehow failing:
```swift
AuthService.shared.isAuthenticated  // should always be true
AuthService.shared.authError        // should be nil
```

#### 3. Conversation Limits
- Max turns: 16 per conversation
- Conversation stored in-memory (`turnsByConversation` dictionary)
- `startNewConversation()` clears turns

#### 4. Action Not Executing
BitBuddy can trigger `add_joke` actions from JSON responses. Check:
- `handleBitBuddyResponse()` parsing in `BitBuddyService`
- JSON format must be exact (no extra text before/after)

---

## 7. Audio Recording & Transcription Debug

### Audio Session Configuration
```swift
Category: .playAndRecord
Mode: .default
Options: .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP,
         .allowAirPlay, .mixWithOthers
```

### Recording Format
```swift
Format: AAC (kAudioFormatMPEG4AAC)
Sample Rate: 44100 Hz
Channels: 2 (stereo)
Quality: .high
File Extension: .m4a
Location: Documents directory
```

### Transcription
```
Engine: Apple Speech Framework (SFSpeechRecognizer)
Locale: en-US
Supported formats: m4a, wav, mp3, aac, caf, aiff, aif
```

### 🔴 Audio Debug Steps

#### 1. Recording Won't Start
- Check console for `❌ [Audio] Failed to configure audio session`
- Check microphone permission: `AVAudioSession.sharedInstance().recordPermission`
- Check if another app holds the audio session exclusively

#### 2. Recording Cuts Out
- Check for memory warnings during recording: `⚠️ Memory warning during recording`
- Check `AudioRecordingService.isPaused` — might have auto-paused
- Check timer: `recordingTimer` fires every 0.1s — if nil, timer was invalidated

#### 3. Transcription Fails
- `authorizationDenied` → User denied speech recognition permission
- `noSpeechDetected` → Audio file has no recognizable speech
- `unsupportedFormat` → File extension not in `supportedExtensions`
- Check `AudioTranscriptionService.shared.isAvailable` → Speech recognizer not available

#### 4. File Not Found After Recording
- `AudioRecordingService.recordingURL` returns `lastRecordingURL` if available
- Check Documents directory for `.m4a` files
- The URL is only valid until `cleanup()` is called

---

## 8. Roast Mode Debug

### Roast Mode Toggle
```swift
@AppStorage("roastModeEnabled") private var roastMode = false
```

### Roast Mode Behavior
- **Visible screens:** `.jokes` and `.settings` only (via `AppScreen.roastScreens`)
- **Auto-navigation:** When toggled ON → screen jumps to `.jokes`
- **Auto-navigation:** When toggled OFF → screen jumps to `.notepad`
- **Theme:** Dark mode forced, ember/fire color palette
- **Screen names change:** "Jokes" → "Roasts", etc.

### 🔴 Roast Mode Debug

#### 1. Wrong Screen After Toggle
`handleRoastModeChange(isRoast:)` clears `screenHistory` and sets initial screen. If user ends up on wrong screen:
- Check `selectedScreen` value
- Check if `AppScreen.roastScreens.contains(selectedScreen)` returns expected value
- The `onAppear` guard also checks and redirects

#### 2. UI Colors Wrong in Roast Mode
All views check `@AppStorage("roastModeEnabled")` independently. If a view looks wrong:
- Check that it reads `roastMode` from `@AppStorage`
- Check `AppTheme.Colors.roastBackground`, `.roastSurface`, `.roastCard`, `.roastAccent`
- Check `.preferredColorScheme(roastMode ? .dark : .light)` on `ContentView`

#### 3. Roast Data Models
- `RoastTarget` — person being roasted (has `@Relationship` to `RoastJoke`)
- `RoastJoke` — individual roast joke (inverse relationship to target)
- These sync via CloudKit like all other models

---

## 9. Data Protection & Migration Debug

### Backup System
```
Location: ~/Library/Application Support/DataBackups/
Max backups: 10 (auto-cleanup of oldest)
Manifest: backup_manifest.json in each backup folder
```

### Backup Triggers
1. **App version change** → automatic update backup
2. **Pre-migration** → before any schema migration runs
3. **Emergency** → every app launch (store file copy)

### Migration System
```
Current migration version: 1
Tracking key: "DataMigration_LastVersion"
```

### 🔴 Data Loss Investigation

#### 1. Check Data Operation Logs
```swift
// Get current log
DataOperationLogger.shared.getCurrentLog()

// Get all logs (including rotated)
DataOperationLogger.shared.getAllLogs()

// Export for sharing
DataOperationLogger.shared.exportLogs()
```

Log file: `~/Library/Application Support/DataOperations.log`
Max size: 10MB per file, 5 rotated files

#### 2. Check Data Validation
```swift
let result = await DataValidationService.shared.validateDataIntegrity(context: modelContext)
print("Healthy: \(result.isHealthy)")
print("Issues: \(result.issues)")
print("Significant data loss: \(result.significantDataLoss)")
print("Jokes: \(result.jokesCount)")
print("Folders: \(result.foldersCount)")
print("Recordings: \(result.recordingsCount)")
```

#### 3. Recover from Backup
```swift
// List available backups
let backupDir = URL.applicationSupportDirectory.appending(path: "DataBackups")
let backups = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
```

Each backup contains:
- `SwiftData/default.store` — the SQLite database
- `UserDefaults.plist` — app preferences
- `AppFiles/` — recordings, photos, etc.
- `backup_manifest.json` — metadata

#### 4. Check Emergency Backups
```swift
let supportDir = URL.applicationSupportDirectory
let emergencyBackups = try FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("emergency_backup_") }
```

---

## 10. Memory & Performance Debug

### MemoryManager
- Observes `didReceiveMemoryWarningNotification`
- Observes `didEnterBackgroundNotification`
- Clears `ImageCache`, `URLCache` on warning
- Posts `.appMemoryWarning` notification for custom cleanup

### Known Memory Concerns

| Area | Risk | Mitigation |
|------|------|------------|
| Image loading | Large photos in Notebook | `CachedImageView` with `ImageCache` |
| Audio recording | Long recordings | Timer-based, no in-memory buffering |
| Import pipeline | Large PDFs | Page-by-page processing |
| Gemini responses | Large JSON | Parsed and discarded |
| Emergency backups | Disk bloat | ✅ Auto-cleaned (3 max, 7-day TTL) |
| Conversation history | Memory growth | Capped at 16 turns |
| DataOperationLogger | File I/O | Async dispatch queue, 10MB rotation |

### 🔴 Performance Debug

#### 1. App Sluggish
- Check for memory warnings: `⚠️ [MemoryManager] Memory warning received`
- Check `MemoryManager.shared.handleMemoryWarning()` was called
- Profile with Instruments → Allocations

#### 2. UI Freezes
- SwiftData fetches happen on `@MainActor` — large datasets can block
- `ImportPipelineCoordinator.processFile()` does heavy work — should be called from `Task`
- `SchemaDeploymentService.verifySchemaDeployment()` makes network calls in sequence

#### 3. Disk Space Issues
Check for:
- Emergency backups: `emergency_backup_*.store`
- Corrupted store backups: `corrupted_store_backup_*.store`
- DataBackups directory
- Recordings in Documents directory
- Log files: `DataOperations.log` + rotated

---

## 11. Background Tasks Debug

### Registered Tasks (Info.plist BGTaskSchedulerPermittedIdentifiers)

| Identifier | Type | Interval | Purpose |
|-----------|------|----------|---------|
| `666bit.refresh` | `BGAppRefreshTask` | 15 min | Refresh download status |
| `666bit.sync` | `BGProcessingTask` | 1 hour | iCloud sync merge |

### Debug Background Tasks (Xcode)
```bash
# Simulate background refresh
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"666bit.refresh"]

# Simulate background sync
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"666bit.sync"]
```

### 🔴 Background Task Issues

#### 1. Tasks Not Running
- Check Info.plist has `BGTaskSchedulerPermittedIdentifiers` with both identifiers
- Check console for `✅ [BGTask] Registered background tasks`
- Check scheduling: `📅 [BGTask] Scheduled background refresh`

#### 2. Task Expiring
- Refresh tasks have ~30s runtime
- Processing tasks have minutes but require network
- Expiration handler cancels the Task and marks `success: false`

#### 3. CloudKit Silent Push Not Working
- Must call `application.registerForRemoteNotifications()` at startup
- Check `didRegisterForRemoteNotificationsWithDeviceToken` vs `didFailToRegister`
- Simulator does NOT support remote notifications — test on device only
- Check `didReceiveRemoteNotification` is being called (log: `🔄 [CloudKit] Remote notification received`)

---

## 12. UI / Navigation Debug

### Navigation Architecture
- Custom side menu (not TabView or NavigationSplitView)
- `MainTabView` uses `@State selectedScreen: AppScreen` with manual navigation
- History stack: `screenHistory: [AppScreen]` for back button
- Floating action buttons (FABs) for menu and back

### Screen Flow
```
LaunchScreenView → ContentView → MainTabView
                                    ├── HomeView (Notepad)
                                    ├── BrainstormView
                                    ├── JokesView
                                    │   ├── JokeDetailView
                                    │   ├── AddJokeView
                                    │   ├── ModernImportView
                                    │   │   ├── SmartImportReviewView
                                    │   │   └── ImportBatchHistoryView
                                    │   └── AutoOrganizeView
                                    ├── SetListsView
                                    │   ├── SetListDetailView
                                    │   └── CreateSetListView
                                    ├── RecordingsView
                                    │   ├── RecordingView
                                    │   └── RecordingDetailView
                                    ├── NotebookView
                                    └── SettingsView
                                        ├── iCloudSyncSettingsView
                                        ├── DataSafetyView
                                        └── HelpFAQView

Side Menu → BitBuddyChatView (sheet)
```

### 🔴 Navigation Issues

#### 1. Screen Not Showing
- Check if `selectedScreen` matches expected `AppScreen` case
- In roast mode: only `.jokes` and `.settings` are reachable
- Check `navigate(to:)` — it guards against navigating to current screen

#### 2. Back Button Not Working
- `screenHistory` must not be empty for back button to show
- `goBack()` pops last entry — if empty, button is hidden
- `handleRoastModeChange` clears history entirely

#### 3. Sheet Not Appearing
- BitBuddy chat: `showAIChat` state with 0.25s delay after menu close
- Edit sheet in SmartImportReview: `showingEditSheet` state
- Import sheet: Check `interactiveDismissDisabled()` — can't swipe away

#### 4. Keyboard Not Dismissing
Global `dismissKeyboard()` function sends `resignFirstResponder` action:
```swift
UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
```

---

## 13. Common Error Patterns & Fixes

### Pattern 1: CloudKit Sync Loop
**Symptoms:** Constant `CKError` in console, battery drain
**Cause:** Corrupted CloudKit records with wrong field types
**Fix:** 
```swift
// Reset the cleanup flag to force re-run
UserDefaults.standard.set(false, forKey: "cloudkit_schema_cleanup_v2")
// Restart app — zone will be deleted and re-exported
```

### Pattern 2: Data Disappears After Update
**Symptoms:** Jokes/recordings gone after app update
**Cause:** ModelContainer switched to new store file or in-memory
**Debug:**
1. Check for `⚠️ [ModelContainer]` messages
2. Check `emergency_backup_*` files — data may be in the backup
3. Check `DataBackups/` for pre-update backups
**Fix:** Restore from backup by copying `default.store` back

### Pattern 3: Import Hangs
**Symptoms:** Import progress never completes
**Cause:** Gemini API timeout or rate limit
**Debug:**
1. Check `gemini_daily_request_count` in UserDefaults
2. Check network connectivity
3. Check `Secrets.plist` for valid `GEMINI_API_KEY`
**Fix:** Reset daily counter: `UserDefaults.standard.set(0, forKey: "gemini_daily_request_count")`

### Pattern 4: Audio Session Conflict
**Symptoms:** Recording starts but no audio captured
**Cause:** Another app or system sound holds the audio session
**Debug:**
1. Check `❌ [Audio] Failed to configure audio session`
2. Check `AVAudioSession.sharedInstance().isOtherAudioPlaying`
**Fix:** Call `setupAudioSession()` again or restart app

### Pattern 5: SmartImportReview Save Fails
**Symptoms:** "Import Complete" alert never shows
**Cause:** `modelContext.save()` throws
**Debug:**
1. Check console for `❌ [ImportReview] Failed to save`
2. Check NSError domain and code
3. Check for SwiftData schema mismatches
**Fix:** Ensure all model properties match the schema

### Pattern 6: Memory Pressure During Import
**Symptoms:** App crashes during large PDF import
**Cause:** Large PDFs load all pages into memory
**Debug:**
1. Check for `⚠️ [MemoryManager] Memory warning received`
2. Check Instruments → Allocations during import
**Fix:** Process files in smaller chunks, or reduce image resolution for OCR

---

## 14. Log Tags Quick Reference

### Console Filter Strings

| Filter | Shows |
|--------|-------|
| `[ModelContainer]` | Store creation, fallback tiers |
| `[AppStartup]` | Boot sequence, data protection |
| `[CloudKit]` | Sync, zone repair, account status |
| `[iCloud]` | Remote change notifications, KV sync |
| `[iCloud Drive]` | Ubiquity container initialization |
| `[DataProtection]` | Backup creation, version tracking |
| `[DataValidation]` | Integrity checks, entity counts |
| `[DataMigration]` | Schema migrations |
| `[DataLog]` | DataOperationLogger entries (DEBUG) |
| `[BGTask]` | Background task registration/execution |
| `[Audio]` | Audio session configuration |
| `[Schema]` | CloudKit schema verification |
| `[ImportPipeline]` | File import processing |
| `[ImportReview]` | Review screen save results |
| `[MemoryManager]` | Memory warnings, cache clearing |
| `Gemini` | Gemini API calls, rate limiting |

### Emoji Quick Scan

| Emoji | Meaning |
|-------|---------|
| ✅ | Success |
| ⚠️ | Warning (recoverable) |
| ❌ | Error (may need intervention) |
| 🚨 | Critical (data loss risk) |
| 🆘 | Emergency (catastrophic) |
| 🔧 | Repair/fix in progress |
| 🔄 | Sync/migration in progress |
| 📦 | Data protection operation |
| 🔍 | Validation check |
| 📋 | Schema operation |
| 📅 | Background task scheduling |
| 📊 | Import statistics |
| 🛡️ | Data protection guard |
| 🗂️ | Data operation log entry |
| 💾 | Backup operation |

---

## 15. Nuclear Options

### Reset Everything (Complete App Reset)

```swift
// 1. Delete all SwiftData stores
let supportDir = URL.applicationSupportDirectory
let files = try FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)
for file in files {
    try FileManager.default.removeItem(at: file)
}

// 2. Clear all UserDefaults
if let bundleID = Bundle.main.bundleIdentifier {
    UserDefaults.standard.removePersistentDomain(forName: bundleID)
}

// 3. Clear iCloud KV Store
NSUbiquitousKeyValueStore.default.dictionaryRepresentation.keys.forEach {
    NSUbiquitousKeyValueStore.default.removeObject(forKey: $0)
}

// 4. Delete CloudKit zone (requires async)
let container = CKContainer(identifier: "iCloud.666bit")
let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
```

### Force CloudKit Zone Reset Only
```swift
UserDefaults.standard.set(false, forKey: "cloudkit_schema_cleanup_v2")
// Restart app
```

### Force Re-Run Data Migration
```swift
UserDefaults.standard.set(0, forKey: "DataMigration_LastVersion")
// Restart app
```

### Force Re-Run Version Backup
```swift
UserDefaults.standard.removeObject(forKey: "DataProtection_PreviousAppVersion")
// Restart app
```

### Reset Gemini Daily Counter
```swift
UserDefaults.standard.set(0, forKey: "gemini_daily_request_count")
```

### Export All Logs for Support
```swift
if let logURL = DataOperationLogger.shared.exportLogs() {
    // Share via UIActivityViewController
    let activity = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
    // Present it...
}
```

---

## Quick Debug Checklist

When something goes wrong, check in this order:

- [ ] **Console logs** — filter by relevant `[Tag]`
- [ ] **ModelContainer tier** — which tier did it boot into?
- [ ] **CloudKit status** — is the account available?
- [ ] **Data validation** — run `validateDataIntegrity()`
- [ ] **Backup availability** — are there recent backups?
- [ ] **Network** — is the device online (for Gemini/CloudKit)?
- [ ] **Permissions** — microphone, speech recognition, notifications
- [ ] **Disk space** — emergency backups can fill storage
- [ ] **Memory** — check for memory warnings in logs
- [ ] **Roast mode** — is the UI in the wrong mode?
- [ ] **Secrets.plist** — is `GEMINI_API_KEY` present and valid?
- [ ] **Entitlements** — iCloud, push notifications, background modes

---

*Generated from full codebase analysis of BitBinder v9.4*
