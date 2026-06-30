# BitBinder

BitBinder is a SwiftUI iOS app for capturing, organizing, recording, importing, and refining stand-up comedy material.

## Repository Status

BitBinder is available on the iOS App Store. This repository contains the native iOS codebase behind the app, including implemented SwiftData models, CloudKit integration, recording/transcription services, import pipeline, release automation, and SwiftUI feature screens.

For employer review, the important context is that this is a production-oriented iOS codebase with real app architecture, data modeling, platform integrations, release tooling, and end-to-end user workflows visible in the repository.

## App Store

BitBinder is distributed as a native iOS app through Apple's App Store:

[The BitBinder on the App Store](https://apps.apple.com/us/app/the-bitbinder/id6756085897)

## Screenshots

Current product screenshots are available on the App Store listing.

## Engineering Highlights

- Shipped native iOS app architecture using SwiftUI, SwiftData, CloudKit, AVFoundation, Speech, Vision/VisionKit, PDFKit, and BackgroundTasks.
- Built a persistent comedy-writing data model covering jokes, folders, set lists, recordings, brainstorm ideas, roast targets, roast jokes, notebook photos, import batches, and chat messages.
- Implemented audio recording and transcription workflows that preserve recordings across navigation and resolve sandbox file paths safely.
- Built an import pipeline that routes files by type, extracts text from PDFs/images/audio, normalizes content, creates review queues, and persists approved jokes.
- Integrated CloudKit sync, iCloud key-value preferences, migration, validation, backup, diagnostics, and data-safety utilities.
- Added cross-iCloud library sharing on top of CloudKit shared workspaces, backed by a SwiftData-to-Core Data migration path and dedicated collaborator views.
- Structured AI functionality behind service/provider boundaries for local fallback, OpenAI-backed behavior, MLX, Transformers, and app-specific intent routing.
- Configured App Store/TestFlight release automation through fastlane.

## Overview

BitBinder is a native iOS productivity app built for stand-up comics and comedy writers. It gives the user one place to store jokes, brainstorm rough ideas, assemble set lists, record performances, transcribe audio, organize roast material, and import written material from files or images.

The app is designed for a working writer who needs material to move from rough capture to structured performance notes without losing context. A user can write or dictate jokes, group them into folders and set lists, record a practice or live set, transcribe that recording, and keep supporting notes and source material alongside the writing.

## Problem

Comedy material often lives across notes apps, voice memos, photos of notebooks, PDFs, loose text files, and set list documents. That makes it hard to find older material, compare written jokes against live recordings, recover discarded ideas, or prepare a polished set from scattered drafts.

## Solution

BitBinder combines capture, organization, import, recording, transcription, and review workflows in one native app. The user can create jokes and brainstorm ideas, organize them with folders and tags, build set lists for performance, record audio, transcribe recordings through Apple speech recognition, and import material through a pipeline that handles text, PDFs, images, scanned documents, and audio.

## Features

- Joke library with titles, body text, notes, folders, tags, hit/open-mic flags, import metadata, and soft-delete recovery.
- Brainstorm board for rough ideas, including color-coded cards, voice-note tracking, notes, promotion to jokes, and trash recovery.
- Set lists with joke and roast-joke ordering, estimated runtime, venue/date fields, finalization, and live performance mode.
- Audio recording with playback, transcription, recording detail views, set-list recording, and trash recovery.
- App-wide in-progress recording indicator that can stop and save a recording from outside the recording screen.
- Audio import and transcription support for common audio formats including m4a, wav, mp3, aac, caf, aiff, and aif.
- Roast mode with roast targets, target traits/photos, roast jokes, relatability scores, custom ordering, and roast set support.
- Notebook area for photo-based source material, notes, folders, image import, document scanning, and trash recovery.
- Import pipeline for text, PDFs, OCR, images, scanned documents, audio transcription, review queues, unresolved fragments, and import batch history.
- BitBuddy assistant services with local fallback, OpenAI-backed service, MLX-backed service, Hugging Face Transformers integration, and app-specific intent routing.
- Auto-organization, duplicate detection, categorization metadata, private search, and PDF export services.
- Cross-iCloud library sharing through CloudKit shared workspaces, with collaborator-facing views for adding and managing jokes, brainstorm ideas, set lists, roast targets, and roast jokes.
- SwiftData persistence with CloudKit sync support, iCloud key-value preferences, data validation, migration, backups, diagnostics, and CloudKit reset utilities.
- Background task registration for refresh/sync and a background asset downloader extension target.

## Tech Stack

- Frontend: SwiftUI
- Backend: No standalone backend in this repository; the app uses Apple platform services and optional AI provider APIs.
- Database: SwiftData with CloudKit private database support, plus a Core Data bridge that backs CloudKit shared workspaces for cross-iCloud library sharing.
- Authentication: No external user-account authentication is required. `AuthService` keeps the app authenticated locally and stores a generated user identifier through iCloud key-value storage.
- Styling: SwiftUI views with custom design utilities, reusable components, color helpers, fire/roast palettes, and native SF Symbols.
- Hosting/deployment: Native iOS App Store distribution with `fastlane` lanes for TestFlight and App Store upload.
- APIs/libraries: AVFoundation, Speech, Vision/VisionKit, PDFKit, CloudKit, BackgroundTasks, UserNotifications, Security/Keychain, CoreTransferable, UniformTypeIdentifiers, MLXLLM, and Hugging Face Transformers.
- Language/framework: Swift, SwiftUI, SwiftData, ExtensionKit-style background asset downloader target.
- Package dependencies: `mlx-swift-lm` and `swift-transformers` are referenced by the Xcode project. Swift Package checkouts also include related transitive packages such as MLX Swift, yyjson, Swift Crypto, Swift Collections, Swift ASN.1, Swift Numerics, Swift Jinja, and OpenAI-related packages.

## Architecture

The project is organized as a native Xcode app:

- `thebitbinder/Models`: SwiftData models for jokes, folders, set lists, recordings, roast targets, roast jokes, brainstorm ideas, notebook photos, import batches, categorization results, extraction hints, and chat messages.
- `thebitbinder/Views`: SwiftUI screens and reusable view components for jokes, brainstorm, recordings, set lists, roast mode, notebook, imports, settings, data safety, and BitBuddy UI.
- `thebitbinder/Services`: App services for recording, transcription, speech recognition, imports, AI joke extraction, BitBuddy backends, CloudKit sync, validation, migration, backup, duplicate detection, PDF/OCR/text extraction, and user preferences.
- `thebitbinder/Services/BitBuddyBackends`: Specialized BitBuddy backend implementations.
- `thebitbinder/CloudKit`: Cross-iCloud library sharing, including the sharing service, shared-workspace views, a CloudKit error classifier, a persistence controller, and a SwiftData-to-Core Data migrator that backs collaborative sharing.
- `thebitbinder/Utilities`: Shared UI components, design tokens, logging, speech helpers, title generation, memory monitoring, iCloud key-value storage, and other app helpers.
- `thebitbinder/Assets.xcassets`: App icons, colors, and asset catalog resources.
- `bit`: Background asset downloader extension target.
- `docs`: Archived product and technical documentation.
- `fastlane`: TestFlight and App Store build/upload lanes.
- `.github`: Copilot and agent instruction files.

App flow:

User captures or imports material -> services normalize, transcribe, extract, categorize, or validate the content -> SwiftData models persist the result locally and sync through CloudKit when available -> SwiftUI views update the joke library, brainstorm board, recordings list, set lists, notebook, import review queue, or BitBuddy interface.

For an engineering deep-dive into the layering, AI-backend abstractions, and import pipeline, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Build and contribution conventions live in [CONTRIBUTING.md](CONTRIBUTING.md).

## How to Run Locally

Requirements:

- macOS with Xcode installed.
- An Apple developer account and valid signing setup for CloudKit, iCloud, speech recognition, background modes, and device testing.
- iOS simulator or physical iOS device.

Setup:

```bash
git clone git@github.com:taylordrew4u2/The-Bit-Binder.git
cd The-Bit-Binder
open thebitbinder.xcodeproj
```

In Xcode:

1. Select the `thebitbinder` app scheme.
2. Select an iOS simulator or connected device.
3. Confirm the signing team and bundle identifier are valid for your Apple developer account.
4. Build and run the app.

Fastlane lanes are present for release builds:

```bash
bundle exec fastlane beta
bundle exec fastlane release
```

These lanes require App Store Connect credentials and local signing access that are not included in the repository.

## Environment Variables

No checked-in environment variables are required to run the app.

Optional provider credentials are handled inside the app where implemented. For example, the OpenAI API key is stored through `OpenAIKeychainStore` using the iOS Keychain, not through a committed `.env` file.

## Usage

1. Launch the app and allow required permissions when using microphone, speech recognition, camera, photos, or document import features.
2. Add jokes manually, organize them into folders, and mark useful metadata such as tags, hits, notes, and open-mic status.
3. Capture rough ideas in Brainstorm and promote stronger ideas into full jokes.
4. Create set lists, add jokes or roast jokes, reorder material, estimate runtime, and finalize a set for performance.
5. Record practice sessions or live sets, then play back and transcribe recordings.
6. Import files, images, scanned documents, PDFs, or audio and review extracted joke candidates before saving them.
7. Use notebook and roast workflows for visual notes, roast targets, target traits, and roast-specific writing.
8. Use settings and data-safety screens to manage iCloud sync, backups, trash, and app preferences.

## What I Built

- Built a native SwiftUI app structure for a multi-section comedy-writing workflow.
- Implemented SwiftData models for jokes, folders, set lists, recordings, brainstorm ideas, notebook photos, import history, roast targets, and roast jokes.
- Connected CloudKit-backed persistence, iCloud key-value preferences, data validation, migration, backup, and recovery utilities.
- Built cross-iCloud library sharing using CloudKit shared workspaces and a SwiftData-to-Core Data bridge, with collaborator views for editing shared jokes, brainstorm ideas, set lists, and roast material.
- Built recording and transcription flows using AVFoundation and Apple Speech, including imported-audio transcription.
- Added import services for text extraction, PDF parsing, OCR, audio transcription, review queues, and import batch tracking.
- Implemented BitBuddy assistant service layers with local fallback, OpenAI, MLX, and Transformers-backed paths.
- Added native views for jokes, brainstorming, set lists, performance mode, recordings, roast mode, notebook, import review, settings, data safety, and app help.
- Added soft-delete/trash flows across major content types so users can recover deleted material.
- Configured iOS capabilities and release automation files for CloudKit, iCloud, speech recognition, microphone access, background modes, document import, and fastlane builds.

## Technical Decisions

- SwiftUI keeps the app native, touch-first, and maintainable across many app sections without introducing a separate web frontend.
- SwiftData models are used for local persistence, while CloudKit support allows the same data model to sync through Apple infrastructure when the user has iCloud available.
- Large or binary records such as notebook images use external storage where appropriate to reduce pressure on the main persistent store.
- User-facing deletion is modeled as soft deletion with `isTrashed` and `deletedDate` fields so important writing material can be restored.
- Set lists store ordered joke identifiers as serialized strings to avoid SwiftData array persistence issues and keep CloudKit-compatible data shapes.
- Audio transcription is separated into a dedicated service so recording UI, import UI, and recording detail views can share the same transcription behavior.
- AI-related functionality is isolated behind provider and backend service types so the app can use local fallback behavior, OpenAI-backed behavior, and on-device/model-backed behavior without putting provider logic directly in views.
- The import pipeline is split into routing, extraction, normalization, splitting, AI extraction, review, and persistence steps, which makes ambiguous imports easier to inspect before saving.
- `fastlane` is used for repeatable TestFlight and App Store build/upload flows, while local development remains centered on Xcode.

## Challenges Solved

### Reliable Recording and Transcription

Challenge: Recording and transcription touch AVFoundation, speech recognition permissions, route changes, file URLs, and navigation state.

Solution: Recording and transcription are handled through dedicated services, recordings resolve stale sandbox paths back to the Documents directory, and the app includes an in-progress recording indicator that can stop and save from outside the recording screen.

Why it matters: A recording app must not lose audio just because the user navigates away or returns to a recording later.

### CloudKit-Compatible Data Modeling

Challenge: SwiftData and CloudKit impose constraints on relationships, arrays, binary data, and schema evolution.

Solution: Models use optional relationships where needed, serialized strings for some ordered identifiers and metadata, external storage for image data, and explicit migration/validation utilities.

Why it matters: The app stores high-value writing material, so schema changes and sync behavior need to preserve data instead of creating fragile local-only records.

### Multi-Format Import

Challenge: Comedy material can arrive as typed text, PDFs, scanned pages, photos, or audio, and each source needs different preprocessing.

Solution: The import pipeline routes files by type, extracts text through the appropriate service, normalizes lines, splits material into candidate jokes, and sends uncertain results through review queues rather than blindly saving everything.

Why it matters: Import quality affects trust. Reviewable extraction prevents the app from turning messy source material into incorrect joke records without user approval.

## Testing

Current validation is handled through Xcode builds and manual QA across the app's primary flows.

Manual QA covers:

- Main user flow.
- Form validation.
- Error states.
- Mobile/responsive layout across supported iPhone and iPad orientations.
- Data persistence, if applicable.
- Recording start, navigation away from recording, stop/save, playback, and transcription.
- Imported audio transcription for supported formats.
- CloudKit sync on fresh install, existing data, offline use, and cross-device merge.
- Trash, restore, and permanent delete behavior.
- Import review behavior for text, PDF, OCR/image, scanned document, and audio inputs.

## Security

- OpenAI API keys are stored with the iOS Keychain through `OpenAIKeychainStore`.
- Legacy OpenAI API keys in `UserDefaults` are migrated into Keychain storage when found.
- App Transport Security disables arbitrary network loads and defines explicit TLS exceptions for configured AI provider domains.
- CloudKit uses the app's private database configuration for synced user data.
- iOS permission prompts are configured for microphone, speech recognition, camera, photo library, document folder access, background audio, and iCloud documents.

Security-sensitive functionality is handled through native iOS platform services such as Keychain, App Transport Security, permission prompts, and CloudKit private database sync.

## Accessibility

The SwiftUI code includes native controls, SF Symbol labels, and some explicit accessibility labels and hints, especially in performance and assistant UI areas.

Accessibility work should continue to cover VoiceOver, Dynamic Type, color contrast, focus order, tap target sizing, and long-form text editing flows.

## Platform Requirements and Operational Notes

- CloudKit, iCloud, speech recognition, background modes, and App Store distribution require Apple developer configuration outside the repository.
- AI provider behavior depends on local model availability or user-provided provider credentials.
- Speech transcription depends on Apple speech recognition availability, permissions, locale support, and audio quality.
- Release automation exists through fastlane, but credentials and signing files are not included.
- Documentation includes archived files that may not reflect the current app state.

## Development Focus

- Regression coverage for models, import pipeline behavior, audio/transcription edge cases, and critical data-safety paths.
- UI automation for the main capture, import, recording, and set-list flows.
- Accessibility coverage across VoiceOver, Dynamic Type, focus order, color contrast, and long-form text editing.
- Error handling around provider availability, transcription failures, and CloudKit sync conflicts.
- Clear separation between archived documentation and current product documentation.

## Status

Active.

The app is actively maintained and includes native iOS implementation, CloudKit-backed persistence, recording/transcription workflows, import tooling, AI service integrations, and release automation.

## License

Copyright © Taylor Drew. All rights reserved unless otherwise specified.
