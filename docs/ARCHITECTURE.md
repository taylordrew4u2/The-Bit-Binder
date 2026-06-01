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

The persistent domain is a set of SwiftData `@Model` types, including: `Joke`,
`JokeFolder`, `SetList`, `Recording`, `BrainstormIdea`, `RoastTarget`,
`RoastJoke`, `NotebookFolder`, `NotebookPhotoRecord`, `ImportBatch`,
`ChatMessage`, plus supporting value types (`CategorizationResult`,
`ExtractionHints`). These are CloudKit-compatible and mirror to the user's
private database.

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
  The guiding principle (see `.github/copilot-instructions.md`) is that user
  data is high-stakes: no silent deletes, no assumed-successful saves.

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

1. Open `thebitbinder.xcodeproj` in Xcode 16+.
2. Swift Package Manager resolves dependencies from the tracked
   `Package.resolved` (the `.swiftpm/` working directory is intentionally
   ignored and regenerated locally).
3. Select the `thebitbinder` scheme and run on an iOS 17+ simulator or device.

CloudKit and OpenAI features require the corresponding entitlements / API key;
the app falls back to local-only behavior when they are absent.
