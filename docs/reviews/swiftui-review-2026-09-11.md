# SwiftUI review — September 11, 2026

Scope: source scan of all app and extension Swift files (156 files at the start of the final scan, including 60 view files), with focused review of editor state, persistence feedback, query invalidation, list identity, navigation, accessibility, and preview dependencies. The app retains its iOS 18 minimum and existing SwiftData schema.

## Changes

| Area | Problem addressed |
| --- | --- |
| Joke and brainstorm autosave | A shared debounce could replace another editor's pending save. Failed callbacks still produced Saved feedback, and Saved did not expire without another redraw. Each editor now owns a coordinator that records the callback result, cancels superseded work, and expires feedback. |
| Joke filters and Home counts | Count-only cache invalidation missed changes to hits, tags, folders, text, and dates. Derived values now read observable model properties. |
| Set lists | Opening a set removed locally unresolved references. Row gestures used raw storage offsets even when displayed rows differed. Opening is now non-mutating, and edits use displayed IDs while retaining unresolved references; failed writes restore only that action. |
| Roast target editing | Cancel could persist bound edits, and removing indexed fields could redirect a text binding. A draft is applied only on Save, and editable rows use persistent IDs for the lifetime of the editor. |
| Brainstorm promotion | Saving the joke and trashing the idea were separate writes with a silent second failure. Both changes are now saved together, with targeted restoration on failure. |
| Notebook notes | Done dismissed without confirming persistence. Notes now use debounced and lifecycle saves, and failed Done saves keep the sheet open with an error. |
| BitBuddy actions | Record-creation failures and lookup failures were hidden. Errors are visible, failed inserts are discarded, and failed lookups do not imply a missing folder. |
| Navigation and ownership | Modern iOS 18 tabs replace tabItem. Close callbacks are explicit inputs rather than custom environment closures. The drawer fits narrow windows, and backup list changes propagate to its owner. |
| Accessibility | Text editors have spoken labels; primary joke text scales with Dynamic Type; onboarding/import progress controls are buttons with larger hit areas; draggable cards have accessible activation actions. |
| Diagnostics and previews | Sync issue rows have stable identities. Root and chat previews receive missing dependencies and in-memory model containers. |

## Verification

Run `Tests/run-regressions.sh` on macOS. It compiles and executes Swift checks for debounce isolation, failed-save feedback, immediate-save cancellation, feedback expiry, visible-row reorder/delete behavior, duplicate row identity, and targeted save rollback. The new GitHub workflow also builds the unsigned arm64 simulator app using Xcode 26.3.

All app/extension sources were parsed locally, and the new editable-field view was type-checked against the iOS 18 simulator target. SwiftLint reported no errors; existing style warnings remain. Full local builds were blocked by disk space, so the PR's GitHub build is the full-build gate.

## Manual release checks

- Edit two documents, force a failed save, retry, and confirm the saved/unsaved indicator follows durable writes.
- Change a hit, tag, folder, or search-matching word without inserting a joke; confirm the list and Home counts refresh.
- Open a set while some referenced jokes are unavailable; confirm IDs remain intact. Reorder/delete visible rows and re-open after saving.
- Edit and cancel a roast target, including its photo. Remove the first of several identical detail rows while editing another.
- Dictate into a joke, navigate back or background, and confirm the transcript already delivered by speech recognition is appended once. Speech not yet transcribed cannot be recovered by editor cleanup.
- Exercise VoiceOver activation, the largest Dynamic Type sizes, narrow iPad windows, and keyboard focus. Check notebook-note and BitBuddy failure alerts using an injected store failure.

This source review does not establish measured performance, successful CloudKit sync, or a complete device accessibility audit. Existing immutable tutorial/diagnostic snapshots using positional enumeration were not converted into new persistence models. No Liquid Glass redesign or wholesale ObservableObject migration was applied.
