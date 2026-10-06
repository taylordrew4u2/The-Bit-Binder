# Architecture

This document describes how BitBinder is structured for engineers reading the
codebase. It reflects the code as it exists in this repository.

## Overview

BitBinder is a native iOS app for stand-up comics: it captures jokes, organizes
them into folders and set lists, records and transcribes performances, imports
written material from files and images, and supports roast-writing workflows.

The app is built with **SwiftUI** for the UI, **SwiftData** for persistence,
and **CloudKit** for cross-device sync. AI features (chat assistant, joke
extraction) sit behind protocol boundaries so concrete backends — Apple
on-device intelligence, OpenAI, MLX, Transformers, and a local fallback — are
interchangeable.

## Tech stack

| Concern              | Framework / API                                   |
| -------------------- | ------------------------------------------------- |
| UI                   | SwiftUI                                            |
| Persistence          | SwiftData (`@Model`), CloudKit mirroring          |
| Preferences / sync   | `NSUbiquitousKeyValueStore` (iCloud KV)           |
| Audio                | AVFoundation, Speech                               |
| Text / OCR           | Vision, VisionKit, PDFKit                          |
| Background work      | BackgroundTasks                                    |
| Release automation   | fastlane (App Store / TestFlight)                  |
| Dependencies         | Swift Package Manager                              |

## Source layout

```
thebitbinder/
├── thebitbinderApp.swift     App entry point + ModelContainer construction
├── AppDelegate.swift         UIKit lifecycle bridging
├── ContentView.swift         Root navigation
├── Models/                   SwiftData @Model types (the domain)
├── Views/                    SwiftUI feature screens & components
├── Services/                 Business logic, integrations, AI backends
├── CloudKit/                 Error classifier + dormant Core Data stack (see below)
├── AppIntents/               Siri and Shortcuts actions
├── Utilities/                Cross-cutting helpers (logging, design system…)
└── Assets.xcassets/          Images, colors, app icon
bit/                          App extension (background download handling)
docs/                         Documentation (this file, guides, archive)
fastlane/                     Release automation
```

The Xcode project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16
synchronized groups), so files added to these folders are part of the build
target automatically — there is no manual `pbxproj` membership step.

## Domain model (`Models/`)

The persistent domain is 12 SwiftData `@Model` types, registered in the
`Schema` in `thebitbinderApp.swift`: `Joke`, `JokeFolder`, `SetList`,
`Recording`, `BrainstormIdea`, `RoastTarget`, `RoastJoke`, `NotebookFolder`,
`NotebookPhotoRecord`, `ImportBatch`, `ImportedJokeMetadata`, and
`UnresolvedImportFragment`. `Models/` also holds plain value types that are not
persisted as models: `ChatBubbleMessage` (in `ChatMessage.swift`),
`CategoryMatch` (in `CategorizationResult.swift`), and `ExtractionHints`.
The models are CloudKit-compatible and mirror to the user's private database.

## CloudKit folder (`CloudKit/`)

Sync in the shipping app is SwiftData's built-in CloudKit mirroring to the
**private** database (`iCloud.The-BitBinder.thebitbinder`). If CloudKit setup
fails, the app reopens the same store file without sync.

`CloudKit/` also contains a Core Data stack (`BitBinderModel`,
`PersistenceController`, `SwiftDataToCoreDataMigrator`) built as groundwork for
a future cutover. It is **dormant**: the controller is only initialized by
debug and verification code paths. Multi-user library sharing through the
CloudKit shared database has been removed; material moves between people by
exporting a file. `CloudErrorClassifier` is used for sync error handling.

## Services (`Services/`)

Business logic lives in services rather than views. Notable boundaries:

- **AI assistant ("BitBuddy").** `BitBuddyBackend` is the protocol; a
  `BitBuddyBackendFactory` selects a concrete implementation
  (`AppleIntelligenceBitBuddyService`, `OpenAIBitBuddyService`,
  `MLXBitBuddyService`, `HuggingFaceTransformersBitBuddyService`, or
  `LocalFallbackBitBuddyService`). `BitBuddyIntentRouter` classifies the user's
  request and routes it. This lets the app degrade gracefully when a given
  backend is unavailable.

- **Joke extraction.** `AIJokeExtractionProvider` is the abstraction for
  pulling jokes out of imported text, with on-device
  (`AppleOnDeviceJokeExtractionProvider`) and `OpenAIJokeExtractionProvider`
  implementations, coordinated by `AIJokeExtractionManager`.

- **Import pipeline.** `ImportRouter` dispatches an incoming file by type to the
  right extractor (`PDFTextExtractor`, `OCRTextExtractor` / `TextRecognitionService`,
  `AudioTranscriptionService`). `ImportPipelineCoordinator` normalizes content
  (`LineNormalizer`, `SmartTextSplitter`), detects duplicates
  (`DuplicateDetectionService`), and produces a review queue
  (`ImportReviewViewModel`) before anything is persisted.

- **Recording & transcription.** `AudioRecordingService` and
  `SpeechRecognitionManager` / `AudioTranscriptionService` handle capture and
  speech-to-text, with sandbox-safe file path resolution.

- **Data safety.** Create/update/delete/migrate/sync paths are guarded by
  `DataProtectionService`, `DataMigrationService`, `DataValidationService`,
  `DataOperationLogger`, and CloudKit utilities (`iCloudSyncService`,
  `iCloudSyncDiagnostics`, `SchemaDeploymentService`, `CloudKitResetUtility`).
  The guiding principle is that user data is high-stakes: no silent deletes, no assumed-successful saves.

## Cross-cutting utilities (`Utilities/`)

- **`DebugLog.swift`** shadows the standard-library `print(_:)` with a no-op in
  release builds, so the codebase's diagnostic `print` calls are active during
  development and compiled away in production.
- **`DesignSystem.swift`**, `ColorExtensions`, `FirePalette`, `RoastModeTint`,
  and `BitBinderComponents` centralize visual styling.
- Secrets are never stored in source: `OpenAIKeychainStore` keeps the OpenAI API
  key in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
  and migrates any legacy `UserDefaults` value out.

## Data flow: importing material

```
File / photo / audio
  → ImportRouter            (dispatch by type)
  → *TextExtractor          (PDFKit / Vision / Speech)
  → ImportPipelineCoordinator
      → LineNormalizer / SmartTextSplitter   (clean + segment)
      → AIJokeExtractionProvider             (identify jokes)
      → DuplicateDetectionService            (flag repeats)
  → ImportReviewViewModel   (user approves / edits)
  → SwiftData persist       (Joke + ImportBatch records)
```

Nothing is written to the store until the user approves the review queue.

## Build & run

1. Open `thebitbinder.xcodeproj` in a current Xcode (CI builds with Xcode 26.3).
2. Swift Package Manager resolves dependencies from the tracked
   `Package.resolved` under `project.xcworkspace/xcshareddata/swiftpm/` (the `.swiftpm/` working directory is intentionally
   ignored and regenerated locally).
3. Select the `thebitbinder` scheme and run on an iOS 18+ simulator or device
   (deployment target iOS 18.0; the Mac Catalyst target needs macOS 15.0).

CloudKit and OpenAI features require the corresponding entitlements / API key;
the app falls back to local-only behavior when they are absent.
