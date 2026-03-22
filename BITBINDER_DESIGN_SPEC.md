# BitBinder - Complete App Design & Workflow Documentation
## Version 9.3 | Last Updated: March 2026

---

# TABLE OF CONTENTS

1. [App Overview](#app-overview)
2. [Visual Design System](#visual-design-system)
3. [Navigation Architecture](#navigation-architecture)
4. [Core Sections](#core-sections)
   - [Jokes](#jokes-section)
   - [Brainstorm](#brainstorm-section)
   - [Set Lists](#set-lists-section)
   - [Recordings](#recordings-section)
   - [BitBuddy](#bitbuddy-section)
   - [Notebook](#notebook-section)
5. [Roast Mode](#roast-mode)
6. [Import System (GagGrabber)](#import-system-gaggrabber)
7. [iCloud Sync](#icloud-sync)
8. [Settings](#settings)
9. [Data Models](#data-models)
10. [Services Architecture](#services-architecture)

---

# APP OVERVIEW

BitBinder is a SwiftUI + SwiftData app designed for stand-up comedians to:
- Write, organize, and refine jokes
- Brainstorm ideas with voice capture
- Build set lists for performances
- Record and transcribe sets
- Chat with BitBuddy (local comedy assistant)
- Import jokes from files (GagGrabber)
- Sync across devices via iCloud

**Target Platforms:** iOS 17+, iPadOS 17+
**Architecture:** SwiftUI, SwiftData, CloudKit

---

# VISUAL DESIGN SYSTEM

## Color Palette

### Standard Mode
```
paperCream:      #FDF8F3  (background)
paperAged:       #F5EDE3  (secondary background)
paperLine:       #E8DFD3  (dividers)
inkBlack:        #1A1A1A  (primary text)
inkBlue:         #2C5282  (accent, links)
surfaceElevated: #FFFFFF  (cards)
jokesAccent:     #4A7C59  (jokes section green)
```

### Roast Mode (Dark Theme)
```
roastBackground: #1A1A1A  (deep black)
roastSurface:    #2D2D2D  (elevated surfaces)
roastCard:       #3A3A3A  (card backgrounds)
roastLine:       #4A4A4A  (dividers)
roastAccent:     #FF6B35  (ember orange)
roastText:       #FFFFFF  (primary text)
roastTextDim:    #AAAAAA  (secondary text)
```

## Typography

```
Primary Font:    System (SF Pro)
Serif Accent:    .serif design variant
Monospace:       .monospaced (for code/transcripts)

Title:           .title2.bold()
Headline:        .headline
Body:            .body
Caption:         .caption
```

## Iconography

All icons use SF Symbols. Key icons:
```
Jokes:           theatermask.and.paintbrush.fill
Brainstorm:      lightbulb.fill
Set Lists:       list.bullet.rectangle.portrait.fill
Recordings:      waveform.circle.fill
BitBuddy:        bubble.left.and.bubble.right.fill
Notebook:        note.text
Settings:        gearshape.fill
Roast Mode:      flame.fill
Import:          square.and.arrow.down.fill
iCloud:          icloud.and.arrow.up.fill
```

## Spacing & Layout

```
Screen Padding:  20pt horizontal
Card Padding:    16pt
Section Spacing: 24pt
Item Spacing:    12pt
Corner Radius:   12pt (cards), 10pt (buttons), 8pt (chips)
```

---

# NAVIGATION ARCHITECTURE

## Main Navigation

The app uses a sidebar/menu pattern accessible via the book icon (top-right).

```
┌─────────────────────────────────────┐
│ [< Back]          [≡ Menu]          │
│                                     │
│         CONTENT AREA                │
│                                     │
└─────────────────────────────────────┘
```

## Menu Structure (Standard Mode)

```
┌─────────────────────────────────────┐
│          BITBINDER                  │
│   ─────────────────────────────     │
│   [icon] Jokes                      │
│   [icon] Brainstorm                 │
│   [icon] Set Lists                  │
│   [icon] Recordings                 │
│   [icon] BitBuddy                   │
│   [icon] Notebook                   │
│   ─────────────────────────────     │
│   [icon] Settings                   │
│   [icon] Help & FAQ                 │
└─────────────────────────────────────┘
```

## Menu Structure (Roast Mode)

```
┌─────────────────────────────────────┐
│          ROAST MODE                 │
│   ─────────────────────────────     │
│   [flame] Roasts                    │
│   [flame] Roast Sets                │
│   [flame] Burn Recordings           │
│   [flame] Fire Notebook             │
│   ─────────────────────────────     │
│   [icon] Settings                   │
│   [icon] Help & FAQ                 │
└─────────────────────────────────────┘
```

---

# CORE SECTIONS

## JOKES SECTION

### Purpose
Store, organize, and manage comedy material.

### Layout

```
┌─────────────────────────────────────┐
│ Jokes              [Grid] [+] [≡]   │
├─────────────────────────────────────┤
│ [All] [Recent] [Folder1] [Folder2]  │  <- Folder chips (horizontal scroll)
├─────────────────────────────────────┤
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │ Joke 1  │  │ Joke 2  │          │  <- Grid view (adjustable)
│  │ Preview │  │ Preview │          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │ Joke 3  │  │ Joke 4  │          │
│  │ Preview │  │ Preview │          │
│  └─────────┘  └─────────┘          │
│                                     │
└─────────────────────────────────────┘
```

### Features
- **View Modes:** Grid (adjustable size via slider) or List
- **Folder Chips:** Horizontal scrolling tabs for folders
- **The Hits:** Star button for perfected jokes
- **Quick Actions:** Swipe to delete, long-press for context menu
- **Search:** Filter jokes by title/content
- **Import:** Via + menu (files, camera, scanner)

### Joke Detail View

```
┌─────────────────────────────────────┐
│ [< Back]    Joke Title    [Edit]    │
├─────────────────────────────────────┤
│                                     │
│  [Full joke content displayed       │
│   with proper formatting]           │
│                                     │
├─────────────────────────────────────┤
│  Tags: [work] [observational]       │
│  Folder: My Best Bits               │
│  Created: Jan 15, 2026              │
│  Modified: Mar 20, 2026             │
├─────────────────────────────────────┤
│  [Mark as Hit]  [Share]  [Delete]   │
└─────────────────────────────────────┘
```

### Add/Edit Joke View

```
┌─────────────────────────────────────┐
│ [Cancel]    New Joke      [Save]    │
├─────────────────────────────────────┤
│  Title                              │
│  ┌─────────────────────────────┐    │
│  │ Enter joke title...         │    │
│  └─────────────────────────────┘    │
│                                     │
│  Content                            │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │ Write your joke here...     │    │
│  │                             │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  Folder: [Dropdown selector]        │
└─────────────────────────────────────┘
```

---

## BRAINSTORM SECTION

### Purpose
Quick idea capture with sticky-note style cards.

### Layout

```
┌─────────────────────────────────────┐
│ Brainstorm         [Zoom] [+] [Mic] │
├─────────────────────────────────────┤
│                                     │
│  ┌────────┐  ┌────────┐  ┌────────┐│
│  │ Idea 1 │  │ Idea 2 │  │ Idea 3 ││
│  │        │  │        │  │        ││
│  │ ...    │  │ ...    │  │ ...    ││
│  └────────┘  └────────┘  └────────┘│
│                                     │
│  ┌────────┐  ┌────────┐  ┌────────┐│
│  │ Idea 4 │  │ Idea 5 │  │ Idea 6 ││
│  │        │  │        │  │        ││
│  │ ...    │  │ ...    │  │ ...    ││
│  └────────┘  └────────┘  └────────┘│
│                                     │
└─────────────────────────────────────┘
```

### Features
- **Sticky Note Grid:** Variable columns based on zoom slider
- **Voice Capture:** Mic button for speech-to-text
- **Quick Add:** Tap + for text entry
- **Card Colors:** Subtle color variations
- **Promote to Joke:** Long-press option to convert idea to full joke

### Idea Card States

```
Normal:
┌────────────────┐
│ Idea content   │
│ preview here...│
│                │
│ [timestamp]    │
└────────────────┘

Selected/Editing:
┌────────────────┐
│ ████████████   │  <- Full content
│ ████████████   │
│ ████████████   │
│                │
│ [Edit] [Delete]│
└────────────────┘
```

---

## SET LISTS SECTION

### Purpose
Build ordered collections of jokes for performances.

### Layout

```
┌─────────────────────────────────────┐
│ Set Lists                     [+]   │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Open Mic Night - March 22   │    │
│  │ 8 jokes • 12 min estimated  │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Club Set - Weekend          │    │
│  │ 15 jokes • 25 min estimated │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ New Material Test           │    │
│  │ 5 jokes • 7 min estimated   │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### Set List Detail View

```
┌─────────────────────────────────────┐
│ [< Back]   Open Mic Night   [Edit]  │
├─────────────────────────────────────┤
│  Total: 8 jokes • ~12 minutes       │
├─────────────────────────────────────┤
│                                     │
│  1. ≡ Opener Joke Title             │
│  2. ≡ Second Joke                   │  <- Draggable handles
│  3. ≡ Third Joke                    │
│  4. ≡ Fourth Joke                   │
│  5. ≡ Fifth Joke                    │
│  6. ≡ Sixth Joke                    │
│  7. ≡ Seventh Joke                  │
│  8. ≡ Closer                        │
│                                     │
├─────────────────────────────────────┤
│  [Add Jokes]  [Shuffle]  [Present]  │
└─────────────────────────────────────┘
```

### Add Jokes to Set List

```
┌─────────────────────────────────────┐
│ [Cancel]    Add Jokes       [Done]  │
├─────────────────────────────────────┤
│  Search jokes...                    │
├─────────────────────────────────────┤
│                                     │
│  [ ] Joke Title 1                   │
│  [x] Joke Title 2  <- Selected      │
│  [x] Joke Title 3  <- Selected      │
│  [ ] Joke Title 4                   │
│  [ ] Joke Title 5                   │
│                                     │
└─────────────────────────────────────┘
```

---

## RECORDINGS SECTION

### Purpose
Record performances, transcribe, and review.

### Layout

```
┌─────────────────────────────────────┐
│ Recordings                    [+]   │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ [Play] Recording - Mar 22    │    │
│  │        12:34 duration        │    │
│  │        [Transcribe]          │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ [Play] Recording - Mar 15    │    │
│  │        8:22 duration         │    │
│  │        [Transcribed]         │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### Recording View

```
┌─────────────────────────────────────┐
│         RECORDING                   │
├─────────────────────────────────────┤
│                                     │
│           00:00:00                  │
│                                     │
│     ▂▃▅▇█▇▅▃▂▃▅▇█▇▅▃▂              │  <- Waveform
│                                     │
│                                     │
│           [  ●  ]                   │  <- Record button
│        Tap to start                 │
│                                     │
└─────────────────────────────────────┘
```

### Playback View

```
┌─────────────────────────────────────┐
│ [< Back]    Recording       [...]   │
├─────────────────────────────────────┤
│                                     │
│           02:34 / 12:34             │
│                                     │
│  ━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━  │  <- Scrubber
│                                     │
│        [<<]  [Play]  [>>]           │
│                                     │
├─────────────────────────────────────┤
│  TRANSCRIPT                         │
│  ─────────────────────────────      │
│  So I was at the store the other    │
│  day and this guy comes up to me... │
│                                     │
└─────────────────────────────────────┘
```

---

## BITBUDDY SECTION

### Purpose
Local comedy writing assistant for analysis, suggestions, and generation.

### Layout

```
┌─────────────────────────────────────┐
│ BitBuddy                   [Clear]  │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ USER: analyze: Why do       │    │
│  │ programmers prefer dark     │    │
│  │ mode? Light attracts bugs.  │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ BITBUDDY:                   │    │
│  │ Structure: one-liner.       │    │
│  │ Strengths: pun, tech topic. │    │
│  │ Edits: Try "use" instead    │    │
│  │ of "prefer" for punch.      │    │
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│  [analyze] [improve] [premise]      │  <- Quick action chips
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │ Type a message...       [>] │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### Available Commands

```
analyze: [joke]    - Structure, strengths, edit suggestions
improve: [joke]    - 2-3 concrete rewrites
premise [topic]    - Generate a premise
generate [topic]   - Create a joke in user's style
style              - User's writing style summary
suggest_topic      - Topic user hasn't explored much
```

### Response Style
- No personality/fluff
- Concise, actionable
- Bullet points for suggestions
- Based on user's own joke database (200 most recent)

---

## NOTEBOOK SECTION

### Purpose
Quick-capture notepad that opens ready to type.

### Layout

```
┌─────────────────────────────────────┐
│ Notebook                    [...]   │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │ Start typing your thoughts  │    │
│  │ here...                     │    │
│  │                             │    │
│  │ Auto-saves as you type.     │    │
│  │                             │    │
│  │                             │    │
│  │                             │    │
│  │                             │    │
│  │                             │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### Features
- Auto-focus on text field
- Auto-save
- Can attach photos
- Syncs via iCloud

---

# ROAST MODE

### Overview
Complete visual and functional transformation for roast comedy.

### Activation
Settings > Toggle "Roast Mode"

### Visual Changes
- Background: Deep black (#1A1A1A)
- Accent: Ember orange (#FF6B35)
- All cards get dark treatment
- Flame icons throughout

### Functional Changes
- Jokes section becomes "Roasts"
- Jokes organized by "Target" (person being roasted)
- Set Lists become "Roast Sets"
- Recordings become "Burn Recordings"

### Roast Target View

```
┌─────────────────────────────────────┐
│ Roasts                        [+]   │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ [Photo]  John Smith         │    │
│  │          12 roasts          │    │
│  │          Last: Mar 20       │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ [Photo]  Jane Doe           │    │
│  │          8 roasts           │    │
│  │          Last: Mar 18       │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

---

# IMPORT SYSTEM (GAGGRABBER)

### Overview
GagGrabber extracts jokes from files using Gemini 2.0 Flash.

### Supported Formats
- PDF (text and scanned)
- Images (JPEG, PNG, HEIC)
- Word documents (.doc, .docx)
- Plain text (.txt, .rtf)

### Rate Limiting
- 1,000 extractions per day (free tier)
- Resets at midnight
- Falls back to local extraction when limit reached

### Import Flow

```
┌─────────────────────────────────────┐
│         IMPORT JOKES                │
├─────────────────────────────────────┤
│                                     │
│       [doc.magnifyingglass]         │
│                                     │
│     Modern Import Pipeline          │
│                                     │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │ [flame] 987 grabs left      │    │  <- Rate limit status
│  │ GagGrabber is caffeinated!  │    │
│  └─────────────────────────────┘    │
├─────────────────────────────────────┤
│  Features:                          │
│  - Smart Splitting                  │
│  - Quality Validation               │
│  - Review Queue                     │
│  - On-Device Processing             │
├─────────────────────────────────────┤
│      [Select File to Import]        │
└─────────────────────────────────────┘
```

### Processing States

```
READY:       Show file picker
PROCESSING:  Progress bar + "GagGrabber is extracting..."
COMPLETED:   Show results (auto-saved, review queue, rejected)
ERROR:       Show error with retry option
```

### Separator Recognition
GagGrabber splits on 200+ patterns:
- Text: "NEXT JOKE", "NEW BIT", "---", "***"
- Numbers: "1.", "2.", "#1", "Joke 1:"
- Bullets: Dashes, dots, arrows
- Blank lines

### Review Queue

```
┌─────────────────────────────────────┐
│ Review Import               [Done]  │
├─────────────────────────────────────┤
│  3 jokes need review                │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Joke content here...        │    │
│  │                             │    │
│  │ [Approve] [Edit] [Reject]   │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Another joke...             │    │
│  │                             │    │
│  │ [Approve] [Edit] [Reject]   │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

---

# ICLOUD SYNC

### Overview
CloudKit-based sync for all user data.

### What Syncs
- Jokes and folders
- Roast targets and roast jokes
- Set lists
- Recordings (audio files)
- Brainstorm ideas
- Notebook content and photos

### Settings

```
┌─────────────────────────────────────┐
│ iCloud Sync                         │
├─────────────────────────────────────┤
│                                     │
│  Enable iCloud Sync         [ON]    │
│                                     │
│  Last Sync: Mar 22, 2026 3:45 PM    │
│                                     │
│  [Sync Now]                         │
│                                     │
│  ─────────────────────────────      │
│                                     │
│  Sync Status:                       │
│  - Jokes: Synced (142)              │
│  - Recordings: Synced (23)          │
│  - Set Lists: Synced (8)            │
│                                     │
└─────────────────────────────────────┘
```

---

# SETTINGS

### Layout

```
┌─────────────────────────────────────┐
│ Settings                            │
├─────────────────────────────────────┤
│                                     │
│  APPEARANCE                         │
│  ─────────────────────────────      │
│  Roast Mode                  [OFF]  │
│                                     │
│  SYNC                               │
│  ─────────────────────────────      │
│  iCloud Sync                   [>]  │
│                                     │
│  IMPORT                             │
│  ─────────────────────────────      │
│  Auto-Organize Imports       [ON]   │
│  Import History                [>]  │
│                                     │
│  EXPORT                             │
│  ─────────────────────────────      │
│  Export All Jokes              [>]  │
│  Export Recordings             [>]  │
│                                     │
│  DATA                               │
│  ─────────────────────────────      │
│  Data Safety                   [>]  │
│  Clear Cache                   [>]  │
│                                     │
│  ABOUT                              │
│  ─────────────────────────────      │
│  Help & FAQ                    [>]  │
│  Version 9.3                        │
│                                     │
└─────────────────────────────────────┘
```

---

# DATA MODELS

## Joke
```swift
@Model class Joke {
    var id: UUID
    var title: String
    var content: String
    var tags: [String]
    var folder: JokeFolder?
    var isHit: Bool
    var isDeleted: Bool
    var deletedDate: Date?
    var dateCreated: Date
    var dateModified: Date
    var wordCount: Int
    var importSource: String?
    var importConfidence: String?
}
```

## JokeFolder
```swift
@Model class JokeFolder {
    var id: UUID
    var name: String
    var dateCreated: Date
    var jokes: [Joke]
}
```

## BrainstormIdea
```swift
@Model class BrainstormIdea {
    var id: UUID
    var content: String
    var dateCreated: Date
}
```

## SetList
```swift
@Model class SetList {
    var id: UUID
    var name: String
    var jokes: [Joke]
    var dateCreated: Date
    var dateModified: Date
}
```

## Recording
```swift
@Model class Recording {
    var id: UUID
    var title: String
    var audioURL: URL
    var duration: TimeInterval
    var transcript: String?
    var dateCreated: Date
}
```

## RoastTarget
```swift
@Model class RoastTarget {
    var id: UUID
    var name: String
    var photoData: Data?
    var jokes: [RoastJoke]
    var dateCreated: Date
    var dateModified: Date
}
```

## RoastJoke
```swift
@Model class RoastJoke {
    var id: UUID
    var content: String
    var target: RoastTarget
    var dateCreated: Date
}
```

---

# SERVICES ARCHITECTURE

## Core Services

```
AppStartupCoordinator     - App initialization, migrations
AuthService               - User authentication
iCloudSyncService         - CloudKit sync operations
DataProtectionService     - Data validation, backup
DataMigrationService      - Schema migrations
```

## Import Services

```
ImportPipelineCoordinator - Main import orchestration
GeminiJokeExtractor       - GagGrabber (Gemini-powered extraction)
LocalJokeExtractor        - Fallback rule-based extraction
FileImportService         - File handling, format detection
ImportRouter              - File type routing
PDFTextExtractor          - PDF text extraction
OCRTextExtractor          - Image OCR via Vision
LineNormalizer            - Text cleanup and normalization
```

## BitBuddy Services

```
BitBuddyService           - Main chat orchestration
LocalFallbackBitBuddyService - Local-only analysis engine
FoundationModelsBitBuddyService - Apple Foundation Models (when available)
JokeAnalyzer              - Joke structure analysis
UserStyleProfile          - User writing style tracking
BitBuddyResources         - Topics, synonyms, templates
```

## Audio Services

```
AudioRecordingService     - Recording management
AudioTranscriptionService - Speech-to-text
```

## Utility Services

```
AutoOrganizeService       - Joke categorization
DataOperationLogger       - Debug logging
DataValidationService     - Data integrity checks
```

---

# FILE STRUCTURE

```
thebitbinder/
├── thebitbinderApp.swift       # App entry point
├── AppDelegate.swift           # App lifecycle
├── ContentView.swift           # Root view
├── Models/
│   ├── Joke.swift
│   ├── JokeFolder.swift
│   ├── BrainstormIdea.swift
│   ├── SetList.swift
│   ├── Recording.swift
│   ├── RoastTarget.swift
│   ├── RoastJoke.swift
│   └── ...
├── Views/
│   ├── JokesView.swift
│   ├── BrainstormView.swift
│   ├── SetListsView.swift
│   ├── RecordingsView.swift
│   ├── BitBuddyChatView.swift
│   ├── NotebookView.swift
│   ├── ModernImportView.swift
│   ├── HelpFAQView.swift
│   ├── SettingsView.swift
│   └── ...
├── Services/
│   ├── GeminiJokeExtractor.swift
│   ├── LocalJokeExtractor.swift
│   ├── ImportPipelineCoordinator.swift
│   ├── BitBuddyService.swift
│   ├── LocalFallbackBitBuddyService.swift
│   ├── iCloudSyncService.swift
│   └── ...
├── Utilities/
│   ├── AppTheme.swift
│   └── ...
└── Assets.xcassets/
```

---

# END OF DOCUMENT
