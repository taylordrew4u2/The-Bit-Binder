# BitBinder

BitBinder is an iOS app for stand-up comics to capture raw ideas, record sets, organize material, import notes from files and images, and use AI-assisted tooling to turn fragments into usable jokes.

The app is built in SwiftUI with SwiftData persistence, CloudKit sync, background processing, speech recognition, and multiple AI provider integrations.

## What the App Does

BitBinder is designed around the actual workflow of writing and refining material:

- Capture jokes, tags, titles, folders, and performance notes.
- Keep brainstorm fragments separate from polished jokes.
- Record live sets and attach transcripts.
- Manage roast-specific material, roast targets, and set lists.
- Import text, PDFs, photos, and recordings into a review pipeline.
- Use OCR, transcription, and AI extraction to convert source material into structured joke records.
- Sync supported data across devices through CloudKit and iCloud key-value storage.

## Core Features

### Writing and Organization

- `Jokes` for standard stand-up material.
- `Roast Jokes` and `Roast Targets` for insult-comedy workflows.
- `Brainstorm` for loose ideas and fragments.
- `Set Lists` for grouping material into performance-ready sequences.
- Notebook photo records for keeping image-based source material tied to the writing process.

### Capture and Import

- Manual joke entry and edit flows.
- Talk-to-text capture.
- Audio recording with transcription support.
- File and PDF import.
- OCR-based text extraction from images.
- AI-powered joke extraction and categorization review flows.

### AI and Analysis

- Multiple BitBuddy backends, including OpenAI and local/on-device options.
- Joke extraction providers for text and imported documents.
- Categorization, tagging, and import confidence scoring.
- Smart import review queue for unresolved or lower-confidence fragments.

### Sync, Safety, and Background Work

- SwiftData + CloudKit-backed persistence.
- iCloud key-value sync for lightweight preferences and settings.
- Background task registration for refresh and sync scheduling.
- Data protection backups before migrations and other high-risk operations.
- Validation and migration services to keep the local data model healthy.

## Project Structure

Primary app code lives in `thebitbinder/`.

- `Models/`
  - SwiftData model types such as `Joke`, `Recording`, `SetList`, `BrainstormIdea`, `ImportBatch`, and related review models.
- `Services/`
  - Application logic for sync, import, migration, validation, audio, transcription, AI providers, notifications, and startup coordination.
- `Views/`
  - SwiftUI screens and feature flows for writing, organizing, importing, settings, and BitBuddy.
- `Utilities/`
  - Shared helpers for design tokens, memory management, iCloud KVS, haptics, and app-specific convenience types.
- `bit/`
  - Background asset downloader extension target resources.

Additional documentation:

- `thebitbinder/NATIVE_IOS_DESIGN_GUIDE.md`
  - Historical UI design audit and native iOS refactor notes.
- `thebitbinder/SYNC_TROUBLESHOOTING.md`
  - Sync-oriented troubleshooting notes and operational context.
- `fastlane/`
  - Fastlane metadata and automation support files.

## Requirements

- Xcode 15 or later recommended.
- Current iOS SDK supported by the project.
- Apple Developer signing configuration for device testing, push notifications, background modes, and CloudKit.
- An iCloud-signed-in physical device is strongly recommended for realistic CloudKit testing.

## Opening and Building

1. Open the Xcode project for the app.
2. Select the main `thebitbinder` scheme.
3. Build and run in Xcode.

The project builds successfully in its current checked-in state.

## Configuration and Secrets

Secrets are not committed. The app is designed to source credentials from a few places depending on provider and environment.

Common sources include:

- Keychain
- Provider-specific `*-Secrets.plist` files
- A local `Secrets.plist`
- Environment variables where supported

If you are wiring up AI-backed features, expect to configure at least one supported provider before those flows work end-to-end.

## CloudKit and iCloud Notes

BitBinder uses CloudKit for structured app data and iCloud key-value storage for lighter preferences.

Important operational notes:

- The iOS Simulator is not a reliable environment for CloudKit validation.
- If no iCloud account is signed in, CloudKit setup failures are expected.
- Background task scheduling can also fail or behave differently in Simulator.
- Schema cleanup or repair operations that require an authenticated iCloud account will fail cleanly when no account is available.

For meaningful sync testing:

1. Use a signed-in physical device.
2. Confirm the correct iCloud container entitlement is present.
3. Verify notification permissions and background capabilities.
4. Test cross-device changes on the same Apple ID.

## Data Safety

The app contains several protection layers intended to reduce data-loss risk:

- Version-aware backup creation
- Pre-migration backups
- Validation passes during startup flows
- Cleanup and recovery logic around sync and import
- Background-aware lifecycle handling to avoid unsafe work during app transitions

This is especially important because the app mixes local persistence, CloudKit sync, import pipelines, and AI-assisted transformation of user content.

## AI and Import Pipeline Overview

BitBinder supports more than one AI path because reliability and device capability vary.

Examples in the codebase include:

- `OpenAIBitBuddyService`
- `LocalFallbackBitBuddyService`
- `AppleIntelligenceBitBuddyService`
- `MLXBitBuddyService`
- Joke extraction providers for OpenAI and on-device execution

The import path is intentionally staged:

1. Collect source material from text, PDF, image, or audio.
2. Normalize and extract text.
3. Segment and classify possible joke boundaries.
4. Save high-confidence material directly when appropriate.
5. Send ambiguous or unresolved fragments to review models for user confirmation.

## App Lifecycle and Reliability Work

Recent maintenance in this repository focused heavily on:

- safer app lifecycle transitions
- reducing unnecessary work during backgrounding
- coalescing remote sync noise
- reducing duplicate logging around iCloud and CloudKit
- making startup work defer or pause when the app is not active
- separating proactive cleanup from real OS memory-warning handling

That work is relevant if you are debugging background execution, sync timing, or startup diagnostics.

## Known Environment-Specific Behavior

Some console output is expected and does not always indicate an app bug.

Examples:

- CloudKit setup errors with `CKAccountStatusNoAccount` when no iCloud account is signed in
- `BGTaskScheduler` failures in Simulator
- various accessibility or simulator-only system framework warnings

Treat those separately from genuine app-level failures like build breaks, migration failures, persistent validation errors, or reproducible data corruption.

## Development Notes

- Prefer making changes with awareness of existing app lifecycle and sync safeguards.
- Be careful with new UI work during background transitions.
- Be careful with repeated `modelContext.save()` calls in lifecycle handlers.
- If you touch sync or migration code, test both signed-in and signed-out iCloud scenarios.
- If you touch import or AI flows, verify both happy-path imports and partial-review flows.

## Release Notes for Maintainers

When preparing a new App Store or TestFlight build:

- `CFBundleShortVersionString` must advance to a new marketing version when the previous train is closed.
- `CFBundleVersion` must also increase for each redistributed build.
- Update both the main app target and the `bit` extension target where applicable.

## Repository Status

This repository may occasionally have local in-progress work unrelated to the task at hand. If you are contributing changes, avoid assuming a clean worktree and commit only the files you intentionally changed.

## License / Ownership

This repository appears to be maintained as a private product codebase for BitBinder. Add formal licensing text here if the project is ever intended for broader distribution.
