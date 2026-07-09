# BitBinder

**A native SwiftUI app that takes stand-up comedy material from a rough thought to a stage-ready set — capture, organize, record, transcribe, import, and refine, all in one place.**

[![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-0A84FF)](https://apps.apple.com/us/app/the-bitbinder/id6756085897)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)](https://developer.apple.com/xcode/swiftui/)
[![Data](https://img.shields.io/badge/data-SwiftData%20%2B%20CloudKit-34C759)](https://developer.apple.com/xcode/swiftdata/)
[![SwiftLint](https://github.com/taylordrew4u2/The-Bit-Binder/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/taylordrew4u2/The-Bit-Binder/actions/workflows/swiftlint.yml)
[![App Store](https://img.shields.io/badge/App%20Store-Download-000000?logo=apple&logoColor=white)](https://apps.apple.com/us/app/the-bitbinder/id6756085897)

BitBinder is a shipped, production iOS app — [live on the App Store](https://apps.apple.com/us/app/the-bitbinder/id6756085897) — and this repository holds the full native codebase behind it: SwiftData models, CloudKit sync and sharing, on-device and cloud AI, an audio recording and transcription stack, a multi-format import pipeline, and fastlane release automation. It is built for a working comedian who needs material to move from rough capture to structured performance notes without ever losing context.

> **Screenshots and the full feature tour live on the [App Store listing](https://apps.apple.com/us/app/the-bitbinder/id6756085897).**

---

## At a Glance

| | |
|---|---|
| **Platform** | iOS 18+, iPhone and iPad |
| **Language** | Swift 5 |
| **UI** | SwiftUI (adaptive layouts, readable-width iPad support) |
| **Persistence** | SwiftData with CloudKit private-database sync |
| **Collaboration** | Cross-iCloud library sharing via CloudKit shared workspaces |
| **AI** | Pluggable assistant with on-device (Apple Intelligence, MLX, Transformers) and cloud (OpenAI) backends |
| **Codebase** | ~54,000 lines of Swift across 151 source files |
| **Structure** | 13 SwiftData models · 49 services · 59 SwiftUI view files · 20 utility modules |
| **CI / Release** | SwiftLint via GitHub Actions · fastlane TestFlight & App Store lanes |
| **Distribution** | Native App Store release (current version 12.0) |

---

## The Problem

Comedy material scatters. A premise gets typed into a notes app, the tag lands in a voice memo, a notebook page becomes a photo, an old set is a PDF, and the live version only exists as a recording. When it comes time to build a tight set, that fragmentation makes it hard to find older bits, compare the written joke against how it actually landed, recover an idea you talked yourself out of, or assemble a polished set from scattered drafts.

## The Solution

BitBinder unifies capture, organization, recording, transcription, import, and review in one native app. A comic can write or dictate jokes, group them into folders and set lists, record a practice or live set, transcribe that audio through Apple speech recognition, and pull in written material from text, PDFs, images, scanned pages, or audio — with an AI assistant and a review-before-save import pipeline keeping the library trustworthy along the way.

---

## Engineering Highlights

- **Shipped and maintain a production iOS app** built entirely on Apple-native frameworks: SwiftUI, SwiftData, CloudKit, AVFoundation, Speech, Vision/VisionKit, PDFKit, BackgroundTasks, and the Keychain.
- **Designed a 13-model comedy-writing data layer** — jokes, folders, set lists, recordings, brainstorm ideas, roast targets, roast jokes, notebook photos, import batches, categorization results, extraction hints, and chat messages — modeled for CloudKit constraints and safe schema evolution.
- **Built a resilient recording + transcription stack** that preserves in-progress audio across navigation, resolves stale sandbox file paths, and exposes an app-wide indicator to stop and save a recording from anywhere in the app.
- **Engineered a multi-format import pipeline** that routes files by type, extracts text from PDFs, images (OCR), scanned documents, and audio, normalizes and splits candidates, and sends uncertain results to a human review queue instead of writing them blindly.
- **Abstracted AI behind clean provider/backend boundaries**, letting the same assistant run on Apple Intelligence on-device, MLX, Hugging Face Transformers, or OpenAI — with a local fallback so the feature degrades gracefully rather than failing.
- **Delivered cross-iCloud library sharing** on top of CloudKit shared workspaces, backed by a purpose-built SwiftData-to-Core Data migrator and dedicated collaborator views.
- **Owned the release path end to end** with fastlane TestFlight and App Store lanes and SwiftLint enforced in CI.

---

## Features

**Writing & organization**
- Joke library with titles, body text, notes, folders, tags, hit/open-mic flags, import metadata, and soft-delete recovery.
- Brainstorm board for rough ideas — color-coded cards, attached voice notes, notes, one-tap promotion to full jokes, and trash recovery.
- Set lists with joke and roast-joke ordering, estimated runtime, venue/date fields, finalization, and a distraction-free live performance mode.
- Notebook for photo-based source material with folders, image import, on-device document scanning, and trash recovery.
- Roast mode with roast targets, target traits and photos, roast jokes, relatability scoring, custom ordering, and roast set support.

**Recording & transcription**
- Audio recording with playback, detail views, set-list recording, and trash recovery.
- App-wide in-progress recording indicator that can stop and save from outside the recording screen.
- Transcription through Apple speech recognition, including for imported audio in m4a, wav, mp3, aac, caf, aiff, and aif.

**Import & AI**
- Import pipeline for text, PDFs, OCR/images, scanned documents, and audio — with review queues, unresolved-fragment handling, and import batch history.
- BitBuddy assistant with local fallback, Apple Intelligence on-device, MLX, Hugging Face Transformers, and OpenAI backends, plus app-specific intent routing.
- Auto-organization, duplicate detection, categorization metadata, private on-device search, and PDF export.

**Sync, sharing & safety**
- Cross-iCloud library sharing through CloudKit shared workspaces, with collaborator views for jokes, brainstorm ideas, set lists, roast targets, and roast jokes.
- SwiftData persistence with CloudKit sync, iCloud key-value preferences, data validation, migration, backups, diagnostics, and CloudKit reset utilities.
- Soft-delete/trash-and-restore across every major content type so high-value material is never lost to a mistaken tap.
- Background task registration for refresh/sync and a dedicated background asset downloader extension.

---

## Architecture

BitBinder is a native Xcode project layered into models, views, and services, with distinct subsystems for CloudKit sharing and shared utilities.

```
thebitbinder/
├── Models/         13 SwiftData models (jokes, set lists, recordings, roast, imports, chat…)
├── Views/          59 SwiftUI screens and reusable components across every feature area
├── Services/       49 services (recording, transcription, import, AI, sync, validation…)
│   └── BitBuddyBackends/   Specialized assistant backends (e.g. Socratic guide)
├── CloudKit/       Sharing service, persistence controller, error classifier,
│                   and a SwiftData→Core Data migrator backing shared workspaces
├── Utilities/      Design tokens, logging, speech helpers, memory monitoring, iCloud KVS…
└── Assets.xcassets App icons, colors, and catalog resources
bit/                Background asset downloader app extension
docs/               Architecture, native-design, and sync-troubleshooting guides
fastlane/           TestFlight and App Store build/upload lanes
.github/workflows/  SwiftLint CI
```

**Data flow**

```
Capture / import  →  Services normalize · transcribe · extract · categorize · validate
                  →  SwiftData persists locally, syncs through CloudKit when available
                  →  SwiftUI views update the library, brainstorm, recordings,
                     set lists, notebook, import review, or BitBuddy interface
```

For a deeper walkthrough of the layering, AI-backend abstractions, and import pipeline, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Contribution and build conventions live in [CONTRIBUTING.md](CONTRIBUTING.md).

---

## The AI Assistant (BitBuddy)

BitBuddy is intentionally provider-agnostic. Rather than wiring a single vendor into the views, the assistant sits behind a backend protocol and a factory that selects an implementation at runtime:

- **Apple Intelligence** — on-device generation where the platform supports it.
- **MLX** — local model inference through `mlx-swift-lm`, with a shared runtime to manage memory pressure.
- **Hugging Face Transformers** — on-device model support via `swift-transformers`.
- **OpenAI** — cloud generation, with the API key stored in the iOS Keychain.
- **Local fallback** — deterministic behavior so the feature still works with no model and no network.

An intent router maps user requests to the right in-app action, and a user style profile lets responses adapt to the writer. Isolating all of this behind service boundaries means a new backend can be added, or the default swapped, without touching UI code.

---

## Tech Stack

- **Language & UI:** Swift 5, SwiftUI, SwiftData.
- **Persistence:** SwiftData with a CloudKit private-database configuration, plus a Core Data bridge that backs CloudKit shared workspaces for cross-iCloud sharing.
- **Apple frameworks:** AVFoundation, Speech, Vision/VisionKit, PDFKit, CloudKit, BackgroundTasks, UserNotifications, Security/Keychain, CoreTransferable, and UniformTypeIdentifiers.
- **AI / models:** MLXLLM (`mlx-swift-lm`), Hugging Face `swift-transformers`, Apple Intelligence on-device generation, and the OpenAI API.
- **Auth:** No external account system. `AuthService` keeps the app authenticated locally and persists a generated user identifier through iCloud key-value storage.
- **Extension target:** A background asset downloader (`bit`) for fetching model assets outside the main app lifecycle.
- **Tooling & release:** Xcode, SwiftLint (enforced in GitHub Actions CI), and fastlane lanes for TestFlight and App Store upload.
- **Transitive packages:** MLX Swift, yyjson, Swift Crypto, Swift Collections, Swift ASN.1, Swift Numerics, and Swift Jinja are resolved through the referenced Swift packages.

---

## Running Locally

**Requirements**

- macOS with a current Xcode.
- An Apple developer account with signing set up for CloudKit, iCloud, speech recognition, and background modes.
- An iOS 18+ simulator or device.

**Setup**

```bash
git clone git@github.com:taylordrew4u2/The-Bit-Binder.git
cd The-Bit-Binder
open thebitbinder.xcodeproj
```

Then in Xcode:

1. Select the `thebitbinder` app scheme.
2. Choose an iOS 18+ simulator or a connected device.
3. Confirm the signing team and bundle identifier are valid for your Apple developer account.
4. Build and run.

**Release builds** are automated with fastlane (these require App Store Connect credentials and local signing, which are not committed):

```bash
bundle exec fastlane beta      # TestFlight
bundle exec fastlane release   # App Store
```

No `.env` file or checked-in environment variables are needed. Optional provider credentials — such as the OpenAI API key — are entered in-app and stored in the iOS Keychain through `OpenAIKeychainStore`, never on disk in plaintext.

---

## Using the App

1. Grant microphone, speech, camera, photo, or document permissions as features request them.
2. Add jokes, organize them into folders, and tag them with hits, notes, and open-mic status.
3. Capture rough ideas in Brainstorm and promote the strong ones into full jokes.
4. Build set lists, add jokes or roast jokes, reorder, estimate runtime, and finalize for performance.
5. Record practice or live sets, then play back and transcribe them.
6. Import files, images, scans, PDFs, or audio and review extracted candidates before they hit the library.
7. Use notebook and roast workflows for visual notes and roast-specific writing.
8. Manage iCloud sync, sharing, backups, and trash from settings and the data-safety screens.

---

## Key Technical Decisions

- **SwiftUI end to end** keeps the app native and touch-first across many feature areas without a separate web frontend to maintain.
- **SwiftData for local persistence, CloudKit for sync** lets the same model graph work offline and sync through Apple infrastructure when iCloud is available.
- **CloudKit-shaped modeling** — optional relationships, serialized ordered identifiers, external storage for image data, and explicit migration/validation — trades some purity for data that survives schema changes and sync.
- **Soft deletion everywhere** (`isTrashed` + `deletedDate`) means a mistaken swipe never destroys writing that took real effort to produce.
- **Transcription as a shared service** lets the recording UI, import flow, and recording detail views reuse one implementation.
- **AI behind provider/backend types** keeps vendor and model logic out of the views and makes the assistant swappable and testable.
- **A staged import pipeline** (route → extract → normalize → split → AI-extract → review → persist) makes ambiguous input inspectable before anything is saved.

---

## Engineering Challenges

### Reliable recording and transcription
Recording touches AVFoundation, permission state, audio route changes, file URLs, and navigation all at once. BitBinder isolates recording and transcription into dedicated services, resolves stale sandbox paths back to the Documents directory, and surfaces a global stop-and-save indicator — so audio is never lost just because the user navigated away or came back later.

### CloudKit-compatible data modeling
SwiftData and CloudKit constrain relationships, arrays, binary data, and schema evolution. The models lean on optional relationships, serialized identifiers for ordering, external storage for images, and explicit migration and validation utilities — because the app stores high-value writing that must survive schema changes and sync conflicts intact.

### Trustworthy multi-format import
Material arrives as typed text, PDFs, scanned pages, photos, or audio, each needing different preprocessing. The pipeline routes by type, extracts through the right service, normalizes and splits candidates, and routes anything uncertain to a review queue — so messy source material never silently becomes incorrect joke records.

---

## Security & Privacy

- OpenAI API keys are stored in the iOS Keychain via `OpenAIKeychainStore`; legacy keys found in `UserDefaults` are migrated into the Keychain automatically.
- App Transport Security disables arbitrary network loads and defines explicit TLS exceptions only for configured AI provider domains.
- User data syncs through the app's CloudKit **private** database.
- Private search and on-device AI paths keep sensitive material processing local where possible.
- Permission prompts are configured for microphone, speech recognition, camera, photo library, document access, background audio, and iCloud documents.

---

## Accessibility

The UI is built from native SwiftUI controls with SF Symbol labeling and explicit accessibility labels and hints in the performance and assistant areas. Ongoing work continues to broaden VoiceOver, Dynamic Type, contrast, focus order, and tap-target coverage across long-form editing flows.

---

## Testing & Quality

SwiftLint runs on every push through GitHub Actions, and validation is backed by Xcode builds and structured manual QA across the primary flows:

- Core capture, organization, and navigation.
- Recording start → navigate away → stop/save → playback → transcription.
- Imported-audio transcription across supported formats.
- Import review for text, PDF, OCR/image, scanned-document, and audio inputs.
- CloudKit sync on fresh install, with existing data, offline, and across devices.
- Trash, restore, and permanent-delete behavior.
- Adaptive layout across iPhone and iPad orientations.

---

## Roadmap

- Automated regression coverage for the models, import pipeline, and data-safety paths.
- UI automation for the capture, import, recording, and set-list flows.
- Deeper accessibility coverage across VoiceOver, Dynamic Type, focus order, and contrast.
- Hardened error handling around AI provider availability, transcription failures, and CloudKit conflicts.

---

## Project Status

**Active and shipping.** BitBinder is on the App Store at version 12.0 and under continued development, with a native iOS implementation, CloudKit-backed persistence and sharing, recording/transcription workflows, a multi-format import pipeline, multi-backend AI, and automated releases.

---

## License

Copyright © Taylor Drew. All rights reserved unless otherwise specified.
