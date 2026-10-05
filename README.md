# BitBinder

**A native SwiftUI app that takes stand-up comedy material from a rough thought to a stage-ready set: capture, organize, record, transcribe, import, and refine in one place.**

[![App Store](https://img.shields.io/badge/App%20Store-Download-000000?logo=apple&logoColor=white)](https://apps.apple.com/us/app/the-bitbinder/id6756085897)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%2018%2B%20%7C%20Mac%20Catalyst-0A84FF)](https://apps.apple.com/us/app/the-bitbinder/id6756085897)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)](https://developer.apple.com/xcode/swiftui/)
[![Data](https://img.shields.io/badge/data-SwiftData%20%2B%20CloudKit-34C759)](https://developer.apple.com/xcode/swiftdata/)
[![Swift build](https://github.com/taylordrew4u2/The-Bit-Binder/actions/workflows/swift-build.yml/badge.svg)](https://github.com/taylordrew4u2/The-Bit-Binder/actions/workflows/swift-build.yml)
[![SwiftLint](https://github.com/taylordrew4u2/The-Bit-Binder/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/taylordrew4u2/The-Bit-Binder/actions/workflows/swiftlint.yml)

BitBinder is a shipped production app, [live on the App Store](https://apps.apple.com/us/app/the-bitbinder/id6756085897) at version 12.0. This repository is the full native codebase behind it: SwiftData models, CloudKit sync and cross-account sharing, an on-device and cloud AI writing assistant, an audio recording and transcription stack, a multi-format import pipeline, Siri Shortcuts, and fastlane release automation.

> Screenshots and the full feature tour are on the [App Store listing](https://apps.apple.com/us/app/the-bitbinder/id6756085897).

---

## Why it exists

Comedy material scatters. A premise is typed into a notes app, the tag lands in a voice memo, a notebook page becomes a photo, an old set lives in a PDF, and the version that actually worked exists only as a recording. When it is time to build a tight set, that fragmentation makes it hard to find older bits, compare the written joke with how it landed, or assemble a set from scattered drafts.

BitBinder puts all of it in one library. A comic can write or dictate jokes, group them into folders and set lists, record a practice or live set, transcribe it with Apple speech recognition, and pull in material from text, PDFs, photos, scanned pages, or audio. Every import passes through a review step before anything is saved.

---

## At a glance

| | |
|---|---|
| **Platforms** | iPhone and iPad on iOS/iPadOS 18+; Mac Catalyst target for macOS 15+ (Apple silicon and Intel) |
| **Stack** | Swift 5, SwiftUI, SwiftData, CloudKit |
| **AI** | Pluggable assistant with on-device (Apple Intelligence, MLX, Transformers) and cloud (OpenAI) backends, plus a local fallback |
| **Codebase** | 168 Swift files across the app and extension: 13 SwiftData models, 51 services, 62 view files, 29 utility modules |
| **CI** | GitHub Actions: SwiftLint, Swift regression suites, iOS Simulator build, Siri integration tests, universal Mac Catalyst build |
| **Release** | fastlane lanes for TestFlight and the App Store |

---

## Features

**Writing and organization**
- Joke library with titles, body text, notes, folders, tags, hit and open-mic flags, import metadata, and trash recovery.
- Brainstorm board for rough ideas: color-coded cards, attached voice notes, and one-tap promotion to a full joke.
- Set lists with joke and roast-joke ordering, estimated runtime, venue and date, finalization, and a distraction-free performance mode.
- Notebook for photo-based source material, with folders, image import, and on-device document scanning.
- Roast mode with targets, traits and photos, roast jokes, relatability scoring, custom ordering, and roast sets.

**Recording and transcription**
- Audio recording with playback, set-list recording, and trash recovery.
- An app-wide recording indicator that stops and saves from any screen.
- Transcription through Apple speech recognition, including imported m4a, wav, mp3, aac, caf, aiff, and aif files.

**Import and assistant**
- Import pipeline for text, PDFs, images (OCR), scanned documents, and audio, with review queues, unresolved-fragment handling, and import history.
- BitBuddy writing assistant with app-specific intent routing and a per-writer style profile.
- Auto-organization, duplicate detection, private on-device search, and PDF export.

**Sync, sharing, and platform integration**
- SwiftData persistence with CloudKit private-database sync, iCloud key-value preferences, validation, migration, backups, and sync diagnostics.
- Cross-iCloud library sharing through CloudKit shared workspaces, with collaborator views for jokes, ideas, set lists, and roast material.
- Siri and Shortcuts actions to save a joke, find jokes, and open set lists.
- Mac Catalyst build with readable-width editors and keyboard shortcuts (⌘N new joke, ⌘S save, Escape cancel).
- Background task registration and a background asset downloader extension for model files.

---

## Engineering highlights

- **Apple-native end to end.** SwiftUI, SwiftData, CloudKit, AVFoundation, Speech, Vision/VisionKit, PDFKit, App Intents, BackgroundTasks, and the Keychain, with two third-party Swift packages (both for on-device models).
- **A 13-model data layer shaped for CloudKit.** Jokes, joke folders, set lists, recordings, brainstorm ideas, roast targets, roast jokes, notebook folders and photos, import batches, categorization results, extraction hints, and chat messages. Optional relationships, serialized ordering identifiers, external storage for images, and explicit migration and validation keep data intact across schema changes and sync.
- **Provider-agnostic AI.** The assistant sits behind a `BitBuddyBackend` protocol and a factory that picks an implementation at runtime, so a backend can be added or the default swapped without touching UI code. A deterministic local fallback means the feature still works with no model and no network.
- **Staged, reviewable import.** Route, extract, normalize, split, AI-extract, review, persist. Anything uncertain goes to a human review queue instead of silently becoming an incorrect joke record.
- **Resilient recording.** Recording and transcription live in shared services that preserve in-progress audio across navigation and resolve stale sandbox paths back to the Documents directory, so a recording is never lost because the user switched screens.
- **Cross-account sharing.** CloudKit shared workspaces backed by a purpose-built SwiftData-to-Core Data migrator.
- **Soft deletion everywhere.** `isTrashed` plus `deletedDate` across every major content type, so one mistaken swipe never destroys writing.
- **Owned release path.** CI on every push and pull request, and fastlane lanes for TestFlight and App Store uploads.

---

## BitBuddy assistant backends

| Backend | Where it runs | Notes |
|---|---|---|
| Apple Intelligence | On device | Used where the platform supports it |
| MLX | On device (iOS only) | Local inference via `mlx-swift-lm`, with a shared runtime to manage memory pressure |
| Hugging Face Transformers | On device | Via `swift-transformers` |
| OpenAI | Cloud | API key entered in-app and stored in the Keychain |
| Local fallback | On device | Deterministic; no model or network needed |

---

## Tech stack

- **Language and UI:** Swift 5, SwiftUI, SwiftData.
- **Persistence and sync:** SwiftData with a CloudKit private-database configuration, plus a Core Data bridge for CloudKit shared workspaces.
- **Apple frameworks:** AVFoundation, Speech, Vision/VisionKit, PDFKit, CloudKit, App Intents, BackgroundTasks, UserNotifications, Security, CoreTransferable, UniformTypeIdentifiers.
- **Swift packages:** [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm) and Hugging Face [`swift-transformers`](https://github.com/huggingface/swift-transformers).
- **Accounts:** No external account system. `AuthService` keeps a generated user identifier in iCloud key-value storage.
- **Tooling:** Xcode, SwiftLint, GitHub Actions, fastlane.

---

## Security and privacy

- OpenAI API keys are stored in the Keychain via `OpenAIKeychainStore`; legacy keys found in `UserDefaults` are migrated automatically.
- App Transport Security blocks arbitrary loads and allows TLS exceptions only for configured AI provider domains.
- User data syncs through the app's CloudKit **private** database.
- Search and the on-device assistant backends keep processing local where possible.

---

## Getting started

**Requirements**
- macOS with a current Xcode (CI uses Xcode 26.3).
- An Apple developer account with signing for iCloud/CloudKit, App Groups, speech recognition, and background modes.
- An iOS 18+ simulator or device.

```bash
git clone https://github.com/taylordrew4u2/The-Bit-Binder.git
cd The-Bit-Binder
open thebitbinder.xcodeproj
```

In Xcode, select the `thebitbinder` scheme, choose an iOS 18+ simulator or device (or **My Mac (Mac Catalyst)**), set your signing team and bundle identifier, then build and run.

No `.env` file is needed. Optional provider credentials, such as an OpenAI key, are entered in the app and stored in the Keychain.

Running on a Mac requires an Apple development certificate, since iCloud and App Groups cannot be ad-hoc signed. Siri and Mac support in this repository ship with the next signed App Store release.

**Release builds** (require App Store Connect credentials and local signing, which are not committed):

```bash
bundle exec fastlane beta      # TestFlight
bundle exec fastlane release   # App Store
```

---

## Testing

```bash
bash Tests/run-regressions.sh
```

This compiles and runs nine standalone Swift regression suites (joke-editor persistence, autosave, list ordering, editable rows, tab navigation, assistant layout, text size, action colors, and Siri capture). GitHub Actions runs the same suites, plus SwiftLint, an iOS Simulator build, the `SiriIntegrationTests` XCTest target, and a universal Mac Catalyst build. See [Tests/Siri.md](Tests/Siri.md) for Siri validation.

Device QA covers recording across navigation and playback, imported-audio transcription, import review for each input type, CloudKit sync (fresh install, offline, multi-device), trash and restore, and adaptive layout on iPhone and iPad.

---

## Project structure

```
thebitbinder/
├── Models/          13 SwiftData models
├── Views/           SwiftUI screens and reusable components
├── Services/        Recording, transcription, import, assistant, sync, validation
│   └── BitBuddyBackends/
├── CloudKit/        Sharing, persistence controller, error classifier, SwiftData→Core Data migrator
├── AppIntents/      Siri and Shortcuts actions
├── Utilities/       Design system, logging, speech helpers, memory monitoring, iCloud KVS
└── Assets.xcassets
bit/                 Background asset downloader extension
thebitbinderTests/   Siri integration tests (XCTest)
Tests/               Standalone regression suites and runner script
fastlane/            TestFlight and App Store lanes
site/                Static marketing site
docs/                Architecture, design, and sync-troubleshooting guides
```

For the layering, assistant abstractions, and import pipeline in more depth, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Build and contribution conventions are in [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Author and license

Built and maintained by **Taylor Drew** ([@taylordrew4u2](https://github.com/taylordrew4u2)).

Copyright © Taylor Drew. All rights reserved.
