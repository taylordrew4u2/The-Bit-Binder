# Joke View / Editing refactor — design

**Source:** `thebitbinder/bitnet/Joke View Editing Audit.html`
**Targets:** `thebitbinder/Views/JokeDetailView.swift`, `thebitbinder/Views/JokeComponents.swift`
**New files:** `DownstageTrayView.swift`, `FloatingJokeActionBar.swift`, `JokeSwipePager.swift`, `JokeKeyboardAccessory.swift`, `JokeMetaStrip.swift`

## Problem
`JokeDetailView` buries the bit body inside form chrome, makes reading and editing look identical, hides alt punches behind a low-signal disclosure, and offers no navigation between jokes. The audit calls out five competing interaction grammars for metadata and a nav-bar save indicator that reads as a nag.

## Design

### 1. Body as prose, not a form
- Title: tap-to-edit. At rest, render as `Text` (title2, semibold). On tap, swap to `TextField` with a 1.5× caret-position spring (150ms). No field border.
- Bit body: `TextEditor` with `.scrollContentBackground(.hidden)`, no fill, 18pt / 1.55 line-height. Above it, a two-character "BIT" eyebrow label (`caption2.weight(.bold)`, secondary color, tracking +1).
- Source/confidence glyph (if present) renders as an SF Symbol at the right edge of the BIT eyebrow line — not a separate disclosure.

### 2. Unified meta strip (`JokeMetaStrip`)
Single `HStack` above the action bar: `"Apr 10 · 6 words · Saved just now"` using `footnote` + secondary color. Centralizes date, word count, and save state so nothing else has to display them.

### 3. Segmented chip row replaces three pill grammars
Merge Hit / Open Mic / Folder into one `HStack` of three chips rendered with `Capsule().fill(.quaternary)` at rest, tint when active. Folder chip opens an inline `.popover` (iPad) / `.sheet(presentationDetents: [.medium])` (iPhone) with the folder picker. Delete the existing "Details" disclosure entirely — modified date moves to the meta strip; any other fields move into the More menu on the action bar.

### 4. Downstage tray (`DownstageTrayView`)
Always-visible card below the bit body. Three labeled sections:
- **Alt punches** — list of variants, each a row with text preview + star button. Exactly one alt can be starred as "current" (mutually exclusive; tapping another star moves the star).
- **Setup variants** — same row pattern, no star.
- **Stage notes** — plain text lines.

Each section shows a count pill in its header and an inline "+ add" button. Empty sections render a one-line hint, not an empty card.

### 5. Floating action bar (`FloatingJokeActionBar`)
Bottom-anchored `HStack` inside an `.ultraThinMaterial` capsule, safe-area padded. Five actions:
- **Edit** — toggles edit mode (focuses the bit body).
- **Punch up** — invokes `BitBuddyService` with joke context.
- **Record** — navigates to `StandaloneRecordingView` with the joke pre-linked.
- **Add to set** — opens `AddJokesToSetListView` scoped to this joke.
- **More** — menu: Duplicate / Export / Move to trash.

### 6. Prev/next pager (`JokeSwipePager`)
Swipe horizontally between jokes in the current filter (respects the list that navigated here). Thin strip above the action bar reads `"prev · 12 of 47 · next"` with tappable sides. Implementation: wrap the detail body in a `TabView(.page)` with a bound index into the filter result.

### 7. Editing state
When the body or title is focused:
- Nav bar collapses to `Close · Autosaving · Done`.
- Downstage tray hides behind the keyboard (it's not editable here).
- Save indicator appears only while a save is in flight; fades 800ms after idle. Errors surface in place with red tint.

### 8. Keyboard accessory (`JokeKeyboardAccessory`)
Replace the existing bar. Layout, left-to-right:
`B · I · List · Dash  |  AI · Mic  |  Done`
Remove field-jump arrows — swiping between jokes replaces them.

## Data / state
No schema changes. Joke model already has `altPunches`, `setupVariants`, `notes`, `starredAltIndex` — verify; if `starredAltIndex` is missing, add as `Int?` default nil.

## Testing
- Snapshot tests for reading vs editing states (dark + light).
- Unit test: star mutual-exclusion (only one alt can be starred).
- Unit test: save-indicator debounce (appears < 100ms after dirty, fades 800ms after idle).
- Manual: swipe pager respects current filter; prev/next respects boundaries.

## Deferred (out of scope)
- Beat-tagging strip above keyboard.
- "≈ 8 sec on stage" reading-time estimate.
- Cursor-position restore on reopen.

## Rollback
Each new file can be deleted; the two edited files can be reverted in git. No storage migration.
