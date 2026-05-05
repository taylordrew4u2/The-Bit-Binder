# BitBinder

BitBinder is a full-featured iOS app for stand-up comics. It covers the entire comedy writing workflow: capturing raw ideas, recording live sets, organizing material into folders and set lists, importing jokes from files and images, roast writing, daily journaling, and an on-device AI assistant called BitBuddy that can analyze, improve, and generate comedy material.

Built in SwiftUI with SwiftData persistence, CloudKit sync, background processing, speech recognition, and multiple AI provider integrations.

**Current version:** 11.2 (build 12)

---

## Table of Contents

- [What the App Does](#what-the-app-does)
- [Core Features](#core-features)
  - [Jokes](#jokes)
  - [Brainstorm](#brainstorm)
  - [Set Lists](#set-lists)
  - [Live Performance Mode](#live-performance-mode)
  - [Recordings](#recordings)
  - [Roast Mode](#roast-mode)
  - [Notebook](#notebook)
  - [Daily Journal](#daily-journal)
  - [Import Pipeline (GagGrabber)](#import-pipeline-gaggrabber)
  - [BitBuddy AI Assistant](#bitbuddy-ai-assistant)
  - [Auto-Organize](#auto-organize)
  - [Settings and Data Safety](#settings-and-data-safety)
- [Data Models](#data-models)
- [Services Architecture](#services-architecture)
  - [BitBuddy Backends](#bitbuddy-backends)
  - [Joke Extraction Providers](#joke-extraction-providers)
  - [Import Pipeline Services](#import-pipeline-services)
  - [Audio and Speech](#audio-and-speech)
  - [Data Management](#data-management)
  - [Sync and CloudKit](#sync-and-cloudkit)
- [Views](#views)
- [Utilities](#utilities)
- [Background Extension](#background-extension-bit)
- [Architecture and Design Patterns](#architecture-and-design-patterns)
- [Dependencies](#dependencies)
- [App Capabilities and Permissions](#app-capabilities-and-permissions)
- [Entitlements](#entitlements)
- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [Building and Running](#building-and-running)
- [Configuration and Secrets](#configuration-and-secrets)
- [CloudKit and iCloud](#cloudkit-and-icloud)
- [Data Safety](#data-safety)
- [Known Environment-Specific Behavior](#known-environment-specific-behavior)
- [Development Notes](#development-notes)
- [Release Notes for Maintainers](#release-notes-for-maintainers)

---

## What the App Does

BitBinder is designed around the actual workflow of writing, refining, and performing comedy:

- Capture jokes with titles, tags, folders, and performance notes.
- Keep brainstorm fragments separate from polished material on a zoomable sticky-note board.
- Record live sets, transcribe them, clip moments, and attach recordings to set lists.
- Build and manage roast material with per-target profiles, burns, traits, and photos.
- Create set lists with drag-to-reorder, runtime estimation, shuffle, and a dedicated live performance view.
- Write daily journal entries with prompted comedy reflections and a calendar heatmap.
- Import text, PDFs, photos, audio, and scanned documents through a multi-stage AI extraction pipeline.
- Use OCR, speech recognition, and AI extraction to convert source material into structured joke records.
- Get writing help from BitBuddy, an on-device AI assistant that can analyze joke structure, suggest improvements, generate premises, and provide page-aware contextual help.
- Sync data across devices through CloudKit and iCloud key-value storage.
- Export material to PDF.

---

## Core Features

### Jokes

The primary content type. Each joke has a title, body content, tags (with inline autocomplete from existing tags), folder assignment, and performance metadata.

- **The Hits**: mark proven material as "Hits" for quick filtering.
- **Open Mic**: flag jokes for open mic testing.
- **Folders**: organize jokes into named folders with create, rename, move, and delete.
- **Tags**: comma-separated tags with chip-style display, autocomplete suggestions from existing corpus, and a dedicated tag filter sheet.
- **Search**: full-text search across titles and content.
- **Soft delete**: all deletions go to trash first with restore capability.
- **AI categorization**: topic, tone, format, and style metadata from import or manual analysis.
- **Word count and import tracking**: automatic metadata on every joke.

### Brainstorm

A separate space for raw ideas that aren't ready to be jokes yet.

- Zoomable sticky-note grid with color-coded cards and board positioning.
- List and board layout modes.
- Voice note capture (flags ideas as voice-originated).
- Promote any idea to a full joke with one tap.
- Free-form notes field on each idea.
- Soft delete with dedicated trash recovery view.

### Set Lists

Group jokes into performance-ready sequences.

- Create named set lists with optional venue, performance date, and notes.
- Add standard jokes and roast jokes to the same set.
- Drag-to-reorder lineup.
- Shuffle for fresh perspectives.
- Runtime estimation (1-2 minutes per joke rule of thumb).
- Opener and closer suggestions from BitBuddy.
- Finalize a set to lock it for performance (read-only after finalization).
- Soft delete with trash recovery.

### Live Performance Mode

A dedicated full-screen view for performing a finalized set list on stage.

- Ultra-clean display showing one joke at a time in large text.
- Tap left/right to navigate between jokes.
- Tap center for controls.
- Elapsed timer.
- Font scaling adjustment.
- Brightness control.
- Safe model access with faulting detection.

### Recordings

Capture live performances and practice sessions.

- Record with pause/resume using AVAudioRecorder.
- Memory monitoring during recording.
- Play back with standard audio controls.
- Transcribe recordings using on-device speech recognition.
- Search across all transcripts.
- Clip specific time ranges from recordings.
- Attach recordings to set lists for comparing written material to live delivery.
- Rename, delete, and recover from trash.
- Standalone recording view for quick capture.
- Roast set recording variant.

### Roast Mode

A dedicated workflow for insult comedy with its own visual identity.

- **Visual takeover**: full-screen animation when toggling roast mode, fire-themed color palette (FirePalette), dynamic accent colors, and heat meter UI component.
- **Roast Targets**: named profiles with notes, traits, photos (stored as image data), and all associated roast jokes.
- **Roast Jokes**: structured with setup, punchline, performance notes, relatability score, killer flag, tested flag, performance count, opening roast designation, and tags.
- **Multiple sort options**: custom order, newest first, by performance count, by relatability, killers only.
- **Roast sets**: build roast-specific set lists.
- **Talk-to-text roast capture**: dictate burns via speech recognition.
- **BitBuddy roast personality**: when roast mode is active, BitBuddy responds with a sharper voice while retaining all normal capabilities.

### Notebook

A photo and note scratch pad for visual source material.

- Camera capture, photo library import, and PDF import.
- Organize photos into named folders.
- Drag-to-reorder within folders.
- Notes field on each photo record.
- External storage for image data (efficient SwiftData handling).
- Soft delete with trash recovery.

### Daily Journal

Prompted daily reflections designed for comedy writers.

- Nine comedy-specific prompts: what made you laugh, what annoyed you, any new ideas, stage-worthy observations, what felt good/off on stage, what you performed, what bombed, and plans for tomorrow.
- Each prompt has a stable ID that survives copy edits.
- Per-prompt answers stored as JSON in a single field (CloudKit-compatible).
- Freeform journal section alongside prompted answers.
- Mood tracking.
- Completion tracking.
- Calendar heatmap showing writing streaks.
- Configurable daily reminders with time and frequency settings.
- Date uniqueness enforced via `dateKey` ("yyyy-MM-dd"), anchored at noon to avoid DST edge cases.

### Import Pipeline (GagGrabber)

A multi-stage pipeline for converting external material into structured joke records.

**Supported file types:** `.txt`, `.pdf`, `.rtf`, `.csv`, `.html`, images (via OCR), and audio files (via transcription).

**Pipeline stages:**

1. **File type detection** — `ImportRouter` identifies the source format.
2. **Text extraction** — `PDFTextExtractor` (PDFKit), `OCRTextExtractor` (Vision framework), or plain text reading.
3. **Line normalization** — `LineNormalizer` cleans line endings and whitespace.
4. **Smart splitting** — `SmartTextSplitter` segments text using user-provided `ExtractionHints` (separator style, bit length, document kind, language).
5. **AI extraction** — `AIJokeExtractionManager` coordinates providers to identify joke boundaries, assign titles, tags, confidence scores, and metadata.
6. **Review and approval** — `SmartImportReviewView` presents extracted jokes one-by-one for user confirmation. High-confidence material can auto-save; ambiguous fragments go to the review queue.

**Extraction providers (priority order):**
1. Apple On-Device (FoundationModels framework, iOS 26+)
2. OpenAI (user-provided API key)
3. NLEmbedding segmenter (always-available local fallback)

**Import batch tracking:** each import records source file, timestamp, segment counts, confidence distribution, extraction method, pipeline version, and processing time.

**Preflight hints:** users can specify separator style, expected bit length, document kind, and language before extraction for better results.

### BitBuddy AI Assistant

An on-device AI chatbot that lives in a sliding drawer accessible from any screen.

**Capabilities (93 intents across 11 app sections):**

- **Joke writing**: analyze joke structure, improve/punch up jokes, shorten or expand, generate premises, generate full jokes, suggest tags, rewrite in the user's style.
- **Comedy knowledge**: explain comedy theory, joke structure types (one-liner, setup-punchline, rule of three, anecdote), techniques, crowdwork tips.
- **Roast writing**: generate roast lines at configurable intensity (light/medium/savage), create targets, build roast sets.
- **Organization**: save jokes to folders, create/rename/delete folders, move jokes, tag management, search, filter by hits/folder/tag/recent.
- **Set lists**: create, rename, add/remove jokes, reorder, shuffle, estimate time, suggest openers and closers, present.
- **Brainstorm**: capture ideas, voice capture, edit, delete, promote to joke, search, group by topic.
- **Recordings**: start/stop recording, rename, delete, play, transcribe, search transcripts, clip, attach to sets, review set from recording.
- **Notebook**: open, save text, attach photos, search.
- **Import**: import files, check import status, review pending items.
- **Sync**: check iCloud status, manual sync, toggle sync.
- **Settings**: export library, clear cache.
- **Help**: explain any feature, FAQ navigation.

**Page-aware responses:** BitBuddy knows which tab the user is on and tailors help responses to the current screen context instead of dumping a generic menu.

**Roast mode personality:** when roast mode is active, BitBuddy uses a sharper voice and terse style while retaining full capability across all features.

**Conversation management:** 16-turn conversation window, multi-conversation memory, session snapshots.

### Auto-Organize

AI-powered categorization that suggests folder organization by topic, tone, format, or style. Available as both automatic and guided step-by-step flows.

### Settings and Data Safety

- User name and preferences.
- Text size adjustment.
- BitBuddy enable/disable.
- OpenAI API key management (Keychain-stored).
- iCloud sync toggle with last sync date and diagnostics.
- Data export to PDF.
- Cache clearing.
- Data safety and privacy information view.
- First-launch onboarding (AppSetupView) and guided tour (ShowMeAroundView).
- Help and FAQ with sections covering getting started, jokes and folders, brainstorm, recordings, roasting, and performance.

---

## Data Models

All models use SwiftData `@Model` with CloudKit sync support. Deletable models implement soft-delete via `isTrashed` + `deletedDate` fields.

| Model | Purpose | Key Properties | Relationships |
|-------|---------|----------------|---------------|
| **Joke** | Standard joke | content, title, tags, dateCreated, dateModified, isHit, isOpenMic, wordCount, importSource | Many-to-many with JokeFolder |
| **JokeFolder** | Folder for organizing jokes | name, dateCreated, isRecentlyAdded | One-to-many with Joke |
| **Recording** | Audio recording | title, duration, fileURL, transcription, isProcessed | None |
| **SetList** | Performance lineup | name, notes, jokeIDs, roastJokeIDs, isFinalized, estimatedMinutes, venueName, performanceDate | Stores joke IDs as serialized UUIDs |
| **BrainstormIdea** | Raw idea / sticky note | content, colorHex, boardPositionX/Y, isVoiceNote, notes | None |
| **RoastTarget** | Person being roasted | name, notes, traits, photoData, openingRoastCount | One-to-many with RoastJoke (cascade) |
| **RoastJoke** | Insult joke for a target | content, setup, punchline, performanceNotes, relatabilityScore, isKiller, isTested, performanceCount, displayOrder | Many-to-one with RoastTarget |
| **NotebookPhotoRecord** | Photo/scan with notes | imageData (external storage), notes, sortOrder | Optional folder (NotebookFolder) |
| **NotebookFolder** | Folder for notebook photos | name, sortOrder | One-to-many with NotebookPhotoRecord |
| **ImportBatch** | Import session record | sourceFileName, totalSegments, confidence counts, extractionMethod, pipelineVersion, processingTimeSeconds | One-to-many with ImportedJokeMetadata and UnresolvedImportFragment |
| **ImportedJokeMetadata** | Extracted joke metadata | jokeID, rawSourceText, confidence, sourcePage, extractionQuality, boundaryClarity, validationResult, needsReview | Many-to-one with ImportBatch |
| **UnresolvedImportFragment** | Ambiguous import fragment | For user review in the import pipeline | Many-to-one with ImportBatch |
| **ChatMessage** | Persisted chat message | text, isUser, timestamp, conversationId | None |
| **DailyJournalEntry** | Daily journal | dateKey, answersJSON, freeformJournal, mood, isComplete | None |
| **CategorizationResult** | AI categorization (struct) | category, confidence, reasoning, matchedKeywords, styleTags, emotionalTone, craftSignals, structureScore | N/A |
| **ExtractionHints** | Import preprocessing hints (struct) | separatorStyle, bitLength, documentKind, languageHints | N/A |

---

## Services Architecture

### BitBuddy Backends

The app selects the best available backend at runtime using `BitBuddyBackendFactory`:

| Priority | Service | Description |
|----------|---------|-------------|
| 1 | **AppleIntelligenceBitBuddyService** | iOS 26+ FoundationModels framework, zero download, fully on-device |
| 2 | **MLXBitBuddyService** | MLX Qwen 2.5 3B on-device inference via `MLXSharedRuntime` |
| 3 | **HuggingFaceTransformersBitBuddyService** | CoreML inference via swift-transformers |
| 4 | **OpenAIBitBuddyService** | Cloud API with user-provided key, optional fallback |
| 5 | **LocalFallbackBitBuddyService** | Rule-based engine with 93-intent router, always available |
| 6 | **NoBitBuddyBackend** | Graceful no-op when nothing is available |

**Supporting services:**
- **BitBuddyService** — main orchestrator (`@MainActor` singleton), manages conversation state, intent routing, action dispatch, page context, and backend delegation.
- **BitBuddyIntentRouter** — classifies user input into 93 structured intents across 11 app sections.
- **BitBuddyResources** — knowledge base containing filler words, vocabulary lists, comedy structure rules, roast techniques, roast examples at multiple intensity levels, joke pro techniques, and response templates.

### Joke Extraction Providers

Separate from BitBuddy chat. Token-gated (`AIExtractionToken`) to ensure extraction only runs during the import pipeline.

| Provider | Description |
|----------|-------------|
| **AppleOnDeviceJokeExtractionProvider** | FoundationModels-based extraction (iOS 26+) |
| **OpenAIJokeExtractionProvider** | Cloud extraction via OpenAI API |
| **EmbeddingSegmenterProvider** | NLEmbedding-based local fallback, always available |

**Coordinated by:**
- **AIJokeExtractionManager** — selects provider and manages extraction flow.
- **HybridGagGrabber** — top-level orchestrator for text-to-jokes conversion.

### Import Pipeline Services

| Service | Purpose |
|---------|---------|
| **ImportPipelineCoordinator** | Multi-stage coordinator from file detection through extraction and validation |
| **ImportRouter** | File type detection and routing (.txt, .pdf, .rtf, .csv, .html, images, audio) |
| **PDFTextExtractor** | PDF text extraction using PDFKit |
| **OCRTextExtractor** | Vision framework OCR for images |
| **TextRecognitionService** | Text recognition utilities, `JokeImportCandidate` struct |
| **SmartTextSplitter** | Intelligent text segmentation using extraction hints |
| **LineNormalizer** | Line-ending and whitespace normalization |
| **FileImportService** | File access and reading |
| **ImportPipelineModels** | Data types for the import workflow |
| **ImportReviewViewModel** | Review UI state management and logic |
| **DuplicateDetectionService** | Prevents duplicate joke imports |

### Audio and Speech

| Service | Purpose |
|---------|---------|
| **AudioRecordingService** | AVAudioRecorder wrapper with pause/resume, timer, and memory monitoring |
| **AudioTranscriptionService** | Speech-to-text transcription of recorded audio |
| **SpeechRecognitionManager** | Real-time speech recognition with auto-restart on iOS ~60s limit, consecutive empty-restart cap (10 max), interruption handling, route change observer, and fallback locale resolution |

### Data Management

| Service | Purpose |
|---------|---------|
| **DataProtectionService** | Version-aware backup creation, pre-migration backups, restore mechanisms |
| **DataValidationService** | Data integrity checks (count-based and deep entity scans) |
| **DataMigrationService** | Version-to-version schema migrations |
| **DataOperationLogger** | Centralized operation logging with severity levels |
| **SchemaDeploymentService** | Database schema deployment and verification |
| **AppStartupCoordinator** | App initialization sequence: data protection, validation, migration, deferred post-startup work |

### Sync and CloudKit

| Service | Purpose |
|---------|---------|
| **iCloudSyncService** | CloudKit sync orchestration with 3-second cooldown, status updates, remote change observers, and manual sync trigger |
| **iCloudSyncDiagnostics** | Sync debugging and troubleshooting utilities |
| **CloudKitResetUtility** | CloudKit reset and recovery operations |

### Other Services

| Service | Purpose |
|---------|---------|
| **AutoOrganizeService** | AI-powered joke categorization by topic, tone, format, or style |
| **JokeAnalyzer** | Joke structure detection (one-liner, setup-punchline, rule of three, anecdote), edit suggestions, and topic detection |
| **PDFExportService** | Export jokes to formatted PDF (8.5x11 layout with metadata) |
| **NotificationManager** | Push notification scheduling and delegate handling |
| **JournalReminderManager** | Daily journal reminder scheduling |
| **DailyJournalStore** | Journal entry persistence and retrieval |
| **AuthService** | Local user identity management |
| **UserPreferences** | User settings (name, BitBuddy toggle, text size, OpenAI key) |
| **UserStyleProfile** | Comedy style metadata derived from user's joke corpus |
| **OpenAIKeychainStore** | Secure API key storage in Keychain |
| **MLXSharedRuntime** | MLX inference runtime lifecycle management |

---

## Views

58 SwiftUI views organized by feature area.

### Core Navigation
- **ContentView** — top-level view with tab navigation, roast mode toggle, color scheme switching
- **MainTabView** — bottom tab bar with dynamic tabs (standard mode vs. roast mode)
- **HomeView** — dashboard with time-aware greeting, stats (Hits count, this-week jokes), and quick-action shortcuts
- **AppSetupView** — first-launch onboarding
- **ShowMeAroundView** — guided tour / tips
- **LaunchScreenView** — custom launch screen

### Jokes
- **JokesView** — list/grid display with folder filtering, tag filtering, Hits filter, search, and roast mode toggle
- **JokeDetailView** — full editor with title, content, tags, folder, notes, and speech-to-text
- **AddJokeView** — new joke canvas with auto-save draft, inline tag chips, and autocomplete suggestions
- **JokeComponents** — reusable components: TheHitsChip, OpenMicChip, TagFilterChip, TagFilterSheet, JokesViewMode
- **JokesViewModifiers** — styling and behavior consistency modifiers
- **MoveJokeToFolderSheet** — bulk move jokes between folders
- **TrashView** — central trash with restore for jokes and folders

### Brainstorm
- **BrainstormView** — zoomable sticky-note grid with list/board layout modes and voice capture
- **BrainstormDetailView** — edit and expand a single idea
- **AddBrainstormIdeaSheet** — quick idea entry
- **BrainstormTrashView** — recover soft-deleted ideas

### Set Lists
- **SetListsView** — searchable list of all sets with create and trash actions
- **SetListDetailView** — full set editor with add jokes, reorder, finalize, and runtime estimation
- **CreateSetListView** — new set creation
- **AddJokesToSetListView** — multi-select jokes to add
- **AddRoastJokesToSetListView** — multi-select roast jokes to add
- **SetListTrashView** — recover soft-deleted sets
- **LivePerformanceView** — full-screen performance mode with large text, tap navigation, timer, font scaling, and brightness control

### Recordings
- **RecordingsView** — list of recorded performances
- **RecordingDetailView** — play, edit, and manage a single recording
- **StandaloneRecordingView** — quick-capture recording UI
- **RecordRoastSetView** — record roast performances
- **RecordingTrashView** — recover deleted recordings

### Roast Mode
- **RoastTargetDetailView** — target profile with all associated burns, multiple sort options
- **AddRoastTargetView** — create new target with name, photo, traits
- **AddRoastJokeView** — write new burn for a target
- **TalkToTextRoastView** — dictate roast jokes via speech
- **RoastJokeTrashView** — recover deleted roast jokes
- **GagGrabberFace** — animated mascot with idle/working/happy/confused moods

### Notebook
- **NotebookView** — photo/PDF gallery with folder organization, camera, photo picker, PDF import, drag-to-reorder
- **NotebookTrashView** — recover soft-deleted photos
- **CreateFolderView** — new notebook folder

### Journal
- **JournalHomeView** — dashboard with today's status, calendar heatmap, and reminder shortcuts
- **JournalEntriesListView** — list of past journal entries
- **JournalEntryEditorView** — edit daily entry with prompted questions and freeform section
- **JournalReminderSettingsView** — configure reminder times and frequency

### Import
- **DocumentPickerView** — file selection (.txt, .pdf, .rtf, .csv, .html)
- **DocumentScannerView** — camera-based document scanning
- **AudioImportView** — audio file import for transcription and extraction
- **ExtractionHintsForm** — user-supplied hints for import preprocessing
- **ExtractionHintsPreflightSheet** — quick preflight before extraction
- **ExtractionProviderBadge** — display which AI provider handled extraction
- **SmartImportReviewView** — review extracted jokes one-by-one before saving
- **ImportBatchHistoryView** — view past imports with metrics

### BitBuddy
- **BitBuddyChatView** — sliding drawer chat interface with context-aware responses
- **BitBuddyDrawer** — slide-in container for BitBuddyChatView
- **BitBuddyCompactWindow** — floating window variant

### Speech
- **TalkToTextView** — speech recognition interface for transcribing to jokes or brainstorm ideas

### Settings
- **SettingsView** — app preferences (user name, text size, BitBuddy, data safety, iCloud, export)
- **iCloudSyncSettingsView** — iCloud sync toggle, last sync date, diagnostics
- **HelpFAQView** — in-app FAQ with 6 sections
- **DataSafetyView** — privacy and data handling information
- **AutoOrganizeView** — AI-powered folder organization
- **GuidedOrganizeView** — step-by-step organization walkthrough

---

## Utilities

| Utility | Purpose |
|---------|---------|
| **DesignSystem** | Canonical design tokens: `AppTextSize`, `DS.Spacing`, `DS.Opacity`, `DS.CornerRadius`, `DS.ShadowStyle`, semantic colors |
| **BitBinderComponents** | Reusable UI: `BitBinderEmptyState`, `BitBinderBadge` (neutral, success, warning, error, gold, info), badge sizes |
| **FirePalette** | Roast mode colors: core orange, bright amber, glow, spark, surfaces, flame gradient, radial gradients |
| **HeatMeter** | Segmented heat bar that scales color with value (grey to amber to orange to ember) with optional glow |
| **EffortlessUX** | UX patterns: auto-focus, auto-save, gesture helpers |
| **DebugLog** | Production print() silencing (no-op in Release builds) |
| **DailyJournalPrompts** | 9 comedy-specific journal prompts with stable IDs |
| **KeywordTitleGenerator** | Auto-generate titles from joke content with stop-words filter |
| **SpeechRecognitionHelpers** | `SpeechReliability` (restart caps, backoff), `SpeechErrorCode`, `SFSpeechRecognizer.preferred()`, `SpeechErrorMapper` |
| **FAQData** | `FAQSectionModel` and `FAQItem` for 6 help sections |
| **RoastModeTint** | Roast mode color and accent overrides |
| **RoastTargetPhotoHelper** | Load and save photos for roast targets |
| **MemoryManager** | Memory pressure monitoring and warnings |
| **QuickCaptureReliability** | Error handling and retry logic for quick capture |
| **iCloudKeyValueStore** | Wrapper around `NSUbiquitousKeyValueStore` for synced preferences |
| **ColorExtensions** | Hex color parsing and opacity adjustments |
| **UIImage+Normalization** | Image rotation correction and size normalization |
| **BitBuddyNotification** | BitBuddy alert and toast notification display |

---

## Background Extension (bit)

A Background Assets (`BADownloaderExtension`) extension for downloading models and assets in the background.

| File | Purpose |
|------|---------|
| **BackgroundDownloadHandler.swift** | `@main struct DownloaderExtension: BADownloaderExtension` — handles download completion, failure, and stores results in shared app group UserDefaults |
| **bit.entitlements** | App group access (`group.The-BitBinder.thebitbinder`) and network client capability |
| **Info.plist** | XPC service configuration with `com.apple.background-asset-downloader-extension` extension point |

The main app coordinates with the extension via `BackgroundDownloadScheduler`, which checks download status and manages `BADownloadManager` scheduling.

---

## Architecture and Design Patterns

### Soft-Delete Throughout
All deletable models have `isTrashed: Bool` and `deletedDate: Date?`. Queries filter with `!$0.isTrashed`. Every feature section has a dedicated trash recovery view.

### SwiftData + CloudKit Sync
ModelContainer with CloudKit configuration and persistent history tracking. iCloud ubiquity container for file-level sync. Remote change notifications trigger context refresh with a 3-second cooldown to avoid churn.

### Multi-Backend AI Architecture
`BitBuddyBackend` protocol with runtime selection via `BitBuddyBackendFactory`. Priority: Apple Intelligence > MLX > Hugging Face > OpenAI > Local fallback > None. Joke extraction providers are separate from chat and token-gated (`AIExtractionToken`) to ensure extraction only runs during import.

### Intent-Driven Chat
`BitBuddyIntentRouter` maps user input to 93 structured intents. Page-context awareness informs responses so "help me here" resolves to the current screen. Structured JSON actions for data mutations only from validated sources.

### Multi-Stage Import Pipeline
Six stages from file detection through AI extraction to user review. Each stage is a separate service with clear boundaries. Import batches track full metrics.

### Speech Recognition Resilience
Auto-restart on iOS ~60s limit. Consecutive empty-restart cap (10 max). Interruption and route-change handling. Fallback locale resolution (en-US > current locale > any available).

### Roast Mode Visual Takeover
Full-screen overlay animation on toggle. Dynamic color scheme (FirePalette). Heat meter for engagement. Separate navigation structure (single NavigationStack vs. TabView).

### Journal with Prompt Persistence
Stable prompt IDs survive copy edits. Answers stored as JSON in a single string field for CloudKit compatibility. Daily uniqueness via `dateKey` ("yyyy-MM-dd"), date anchored at noon to avoid DST edge cases.

### Performance Mode Finalization
SetList locks when finalized. Clean big-text tap-navigation design. Elapsed timer, font scaling, brightness control. Safe model access with faulting detection.

### App Startup Sequence
`AppStartupCoordinator` runs data protection checks, validation, and migration in order. Post-startup work defers until the app is active. Background task registration happens before app finishes launching.

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| **OpenAI** (MacPaw) | 0.4.9 | OpenAI API client for chat and extraction |
| **MLX Swift** | 0.29.1 | On-device ML inference runtime |
| **MLX Swift LM** | 2.29.3 | Language model support for MLX |
| **swift-transformers** (Hugging Face) | 1.1.9 | CoreML inference via Hugging Face models |
| **swift-jinja** (Hugging Face) | 2.3.5 | Template rendering for model prompts |
| **generative-ai-swift** (Google) | 0.5.6 | Google Generative AI SDK |
| **swift-algorithms** (Apple) | 1.2.1 | Collection algorithms |
| **swift-collections** (Apple) | 1.4.1 | Additional collection types |
| **swift-numerics** (Apple) | 1.1.1 | Numeric protocols and types |
| **swift-crypto** (Apple) | 4.5.0 | Cryptographic operations |
| **swift-http-types** (Apple) | 1.5.1 | HTTP type definitions |
| **swift-openapi-runtime** (Apple) | 1.11.0 | OpenAPI runtime support |
| **swift-asn1** (Apple) | 1.7.0 | ASN.1 parsing |
| **yyjson** | 0.12.0 | High-performance JSON parsing |

---

## App Capabilities and Permissions

### Background Modes
- `audio` — recording and playback
- `fetch` — background app refresh
- `processing` — background processing tasks
- `remote-notification` — CloudKit silent push notifications for cross-device sync

### Background Tasks
- `The-BitBinder.thebitbinder.refresh` — lightweight periodic check (15-minute interval, 30s runtime)
- `The-BitBinder.thebitbinder.sync` — heavier CloudKit sync work (1-hour interval, requires network)

### Privacy Permissions
- **Camera** — notebook scanning and photo capture
- **Microphone** — recording performances and BitBuddy voice input
- **Speech Recognition** — transcription and Talk-to-Text
- **Photo Library** — import and save images
- **Documents Folder** — export PDFs and recordings

### Network Security
- TLS 1.2+ enforced
- Allowed domains: `api.openai.com`, `api.arcee.ai`, `openrouter.ai`
- No arbitrary loads

### File Sharing
- `UIFileSharingEnabled`: apps can access documents via Files app
- `LSSupportsOpeningDocumentsInPlace`: in-place document editing
- `UISupportsDocumentBrowser`: document browser integration
- Custom UTI: `com.thebitbinder.joke`

### CloudKit
- Schema version: 2.5.0
- Public key algorithm: ECDSA P-256
- Schema verification enabled

### Background Assets
- Manifest URL for model downloads
- Max install size: 50 MB
- Essential max: 10 MB
- Initial download allowance: 10 MB

### Device Requirements
- arm64
- Portrait and landscape orientations (iPad supports all four)

---

## Entitlements

### Main App (thebitbinder)
- **CloudKit**: `com.apple.developer.icloud-services` (CloudKit + CloudDocuments)
- **iCloud Container**: `iCloud.The-BitBinder.thebitbinder`
- **iCloud Key-Value Store**: team-scoped KVS identifier
- **App Groups**: `group.The-BitBinder.thebitbinder` (shared with extension)
- **Network Client**: enabled
- **Push Notifications**: development environment

### Extension (bit)
- **App Groups**: `group.The-BitBinder.thebitbinder`
- **Network Client**: enabled

---

## Project Structure

```
thebitbinder/
  thebitbinderApp.swift          # App entry point, SwiftData schema, ModelContainer
  ContentView.swift              # Top-level navigation, roast mode takeover
  AppDelegate.swift              # Background tasks, audio, CloudKit, notifications
  BackgroundDownloadScheduler.swift  # BA download coordination
  Info.plist                     # Capabilities, permissions, CloudKit config
  thebitbinder.entitlements      # iCloud, app groups, push

  Models/                        # 14 SwiftData @Model types + supporting structs
  Services/                      # 48 services (AI, import, sync, audio, data)
  Views/                         # 58 SwiftUI views
  Utilities/                     # Design system, helpers, extensions
  Assets.xcassets/               # App icons, colors, images

bit/                             # Background asset downloader extension
  BackgroundDownloadHandler.swift
  bit.entitlements
  Info.plist

fastlane/                        # Fastlane metadata and automation
```

Additional documentation:
- `thebitbinder/NATIVE_IOS_DESIGN_GUIDE.md` — UI design audit and native iOS refactor notes
- `thebitbinder/SYNC_TROUBLESHOOTING.md` — sync-oriented troubleshooting and operational context

---

## Requirements

- Xcode 16 or later
- iOS 17+ SDK (iOS 26+ for Apple Intelligence features)
- Apple Developer signing configuration for device testing, push notifications, background modes, and CloudKit
- An iCloud-signed-in physical device is strongly recommended for realistic CloudKit testing

---

## Building and Running

1. Open `thebitbinder.xcodeproj` in Xcode.
2. Select the `thebitbinder` scheme.
3. Build and run on a device or simulator.

The project builds successfully in its current checked-in state.

---

## Configuration and Secrets

Secrets are not committed. The app sources credentials from:

- **Keychain** — OpenAI API key via `OpenAIKeychainStore`
- **Provider-specific plist files** — `*-Secrets.plist` or `Secrets.plist`
- **Environment variables** where supported

If you are wiring up AI-backed features (OpenAI chat or extraction), configure at least one supported provider before those flows work end-to-end. Apple Intelligence and local fallback backends require no configuration.

---

## CloudKit and iCloud

BitBinder uses CloudKit for structured app data (SwiftData models) and iCloud key-value storage for lightweight preferences.

**Container ID:** `iCloud.The-BitBinder.thebitbinder`

Important notes:

- The iOS Simulator is not reliable for CloudKit validation.
- CloudKit setup failures are expected when no iCloud account is signed in.
- Background task scheduling can fail or behave differently in Simulator.
- Schema cleanup or repair operations that require an authenticated iCloud account will fail cleanly when no account is available.
- CoreData CloudKit debug noise is suppressed via `-com.apple.CoreData.CloudKitDebug 0` launch argument.

For meaningful sync testing:

1. Use a signed-in physical device.
2. Confirm the correct iCloud container entitlement is present.
3. Verify notification permissions and background capabilities.
4. Test cross-device changes on the same Apple ID.

---

## Data Safety

The app contains several protection layers to reduce data-loss risk:

- Version-aware backup creation before migrations
- Pre-migration backups via `DataProtectionService`
- Validation passes during startup via `DataValidationService`
- Cleanup and recovery logic around sync and import
- Background-aware lifecycle handling to avoid unsafe work during app transitions
- Soft-delete on all user-facing content types with dedicated trash recovery views

This is especially important because the app mixes local persistence, CloudKit sync, import pipelines, and AI-assisted transformation of user content.

---

## Known Environment-Specific Behavior

Some console output is expected and does not indicate an app bug:

- CloudKit setup errors with `CKAccountStatusNoAccount` when no iCloud account is signed in
- `BGTaskScheduler` failures in Simulator
- `updateTaskRequest called for an already running/updated task` from CoreData CloudKit sync (benign framework noise)
- Various accessibility or simulator-only system framework warnings

Treat those separately from genuine app-level failures like build breaks, migration failures, persistent validation errors, or reproducible data corruption.

---

## Development Notes

- Prefer making changes with awareness of existing app lifecycle and sync safeguards.
- Be careful with new UI work during background transitions.
- Be careful with repeated `modelContext.save()` calls in lifecycle handlers.
- If you touch sync or migration code, test both signed-in and signed-out iCloud scenarios.
- If you touch import or AI flows, verify both happy-path imports and partial-review flows.
- BitBuddy chat uses the local fallback engine by default. AI backends are available but the local intent router handles the majority of interactions.
- GagGrabber (joke extraction) is completely separate from BitBuddy chat and is token-gated to prevent accidental invocation outside the import pipeline.
- Roast mode has its own navigation structure (single NavigationStack) separate from the standard TabView.

---

## Release Notes for Maintainers

When preparing a new App Store or TestFlight build:

- `CFBundleShortVersionString` must advance to a new marketing version when the previous train is closed.
- `CFBundleVersion` must also increase for each redistributed build.
- Update both the main app target and the `bit` extension target where applicable.
- Current values: version 11.2, build 12.

---

## License / Ownership

This repository is maintained as a private product codebase for BitBinder.
