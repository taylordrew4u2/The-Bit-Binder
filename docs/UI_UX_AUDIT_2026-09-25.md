# UI/UX and SwiftUI audit — 2026-09-25

## Scope and validation

Source audit of the app shell, setup/settings, Home, BitBuddy chat/compact/drawer, Notepad, and selected editor, import, recording, notebook, and set-list save/error paths. Applied Build iOS Apps (SwiftUI UI Patterns) and SwiftUI Expert guidance. This is not a rendered visual audit or full persistence/security review. No application source was changed.

Reviewed app tree: c74950d981801dc805b415cdae5070842a6c6c75 (unchanged by consolidation commit e6ff92c6fe31cf54aa7e6b6fa099f336ebacd048). Deployment target: iOS 18.0.

Passed: all four suites in `bash Tests/run-regressions.sh` — joke editor persistence, autosave, set-list identity, editable-row identity.

Not run: iOS build, simulator, screenshots, previews, VoiceOver, touch/keyboard interaction, contrast measurement, Instruments. This Mac has CommandLineTools selected and no Xcode installed. Regression suites test extracted logic, not rendered SwiftUI behavior.

## Repository consolidation

The initial local workspace was an empty Git repository with no commits or remote. Connected origin and checked out main.

All five remote feature-branch tips are now ancestors of main. The three outstanding tips were already integrated through squash merges:
- README refresh branch tree exactly matched main.
- README cleanup commit was patch-equivalent to its main counterpart.
- Persistence branch tree exactly matched the PR 44 squash commit (0f9c5ed).

Recorded their ancestry with a content-preserving merge. Verified zero file differences against the previous main. Retained remote branch names as references; there is only one local worktree and one local branch, main.

## Prioritized findings

### 1. P1 — App-wide text size overrides the user's accessibility setting

Evidence: `thebitbinder/thebitbinderApp.swift:190-209`; `thebitbinder/Utilities/DesignSystem.swift:13-38`; `thebitbinder/Views/SettingsView.swift:173-177`.

The root always sets a single DynamicTypeSize derived from four app preferences. Standard resolves to .large; even Extra Large only resolves to .xxLarge. System accessibility sizes cannot reach the SwiftUI hierarchy.

Reproduce: select an accessibility text size in iOS Settings, launch with the default app preference, and compare the library/settings labels to system UI.

Recommendation: default to inherited system sizing, offer an explicit System option, and ensure any app preference preserves access to accessibility sizes. Adapt dense layouts before claiming Larger Text support.

Acceptance: test default and custom preferences with every accessibility size; essential labels and actions must remain usable.

### 2. P2 — BitBuddy silently drops navigation to tabs excluded by customization

Evidence: `thebitbinder/ContentView.swift:383-389`; `thebitbinder/Views/BitBuddyChatView.swift:253-269`.

The chat clears pending navigation, posts a destination, and closes itself. The app shell acts only if the destination is in visibleTabs. Brainstorm and Recordings are absent from the default tab selection, so valid navigation to these sections can leave the user on the original screen after chat closes.

Reproduce: use the default tab set and trigger a BitBuddy navigation request for Brainstorm or Recordings.

Recommendation: route hidden destinations through a navigation path or temporary destination presentation, or report that navigation cannot be completed before closing chat.

Acceptance: every supported assistant destination opens under default and customized tab configurations.

### 3. P2 — Tab selection can fall back to a tab that does not exist

Evidence: `thebitbinder/ContentView.swift:290-301` and roast-mode change handling at `346-359`.

When a stored selection is invalid, the binding returns Home in standard mode. Home is optional. With Home removed, enter Roast Mode and then exit: the stored value can remain invalid for standard tabs and the binding can resolve to an absent Home tag. The on-change correction for setupSelectedTabs cannot fix a mode-only transition.

Recommendation: resolve fallback selection from visibleTabs.first, including first-launch and mode changes. Validate the raw stored selection before assigning it.

Acceptance: customize to Jokes/Sets/Settings only; switch modes and relaunch. Selection must always belong to visibleTabs. Exact rendering of an invalid selection still requires simulator confirmation.

### 4. P2 — Floating assistant launcher lacks button semantics and a meaningful action label

Evidence: `thebitbinder/ContentView.swift:405-438`; `thebitbinder/Views/BitBuddyChatView.swift:731-747`.

The launcher is an asset image with a DragGesture and TapGesture. It has no explicit Open BitBuddy label, button trait, or accessibility representation. It therefore lacks the semantics and keyboard activation behavior of a native Button; actual VoiceOver output requires device verification.

Recommendation: use a labeled Button for activation, preserve dragging separately, and hide decorative image content. Explicitly remove the inactive launcher from accessibility when chat is open.

Acceptance: VoiceOver announces Open BitBuddy as a button; activation works with VoiceOver, keyboard, and touch.

### 5. P2 — Compact chat has fixed geometry and a drag gesture covering the conversation

Evidence: `thebitbinder/Views/BitBuddyCompactWindow.swift:93-120,136-151,207-229`.

The panel is always 300 × 380 points with 14-point outer padding. Its GeometryProxy does not constrain the panel size. It ignores keyboard safe-area changes, and attaches the move gesture to the whole window instead of the header. In a container shorter than 408 points the panel cannot fit; scrolling/text-selection gesture competition and keyboard obstruction need runtime confirmation.

Recommendation: constrain size to usable container bounds, respect the keyboard, switch to a full presentation when compact space is insufficient, and attach repositioning only to a visible header/handle. Convert global drag locations into the same local coordinate space used by corner selection.

Acceptance: compose and scroll long conversations on small iPhone, landscape, and narrow iPad windows, with keyboard visible. Close/expand must remain reachable.

### 6. P2 — Notepad does not refresh text metrics when text-size preferences change

Evidence: `thebitbinder/Views/NotepadView.swift:59-106`.

The UIKit editor initializes font, rowHeight, and typing attributes once. updateUIView only replaces attributed text when text differs and updates focus. It does not consume SwiftUI dynamicTypeSize or refresh all text metrics. The SwiftUI placeholder uses .body while the UIKit text uses a preferred UIFont, so app text-size changes are not consistently applied.

Recommendation: explicitly bridge the chosen effective text size into the representable; update existing text attributes, typing attributes, font and ruled-line height together while preserving selection and marked text.

Acceptance: change app and system text size while the notepad remains mounted; placeholder, typed text, existing text and ruled lines should stay aligned.

### 7. P3 — Compact chat controls offer small touch targets

Evidence: `thebitbinder/Views/BitBuddyCompactWindow.swift:174-200`.

Close and Expand have plain 28 × 28-point rectangular targets, even though the header has 44 points of height. This makes frequent controls harder to hit.

Recommendation: expand the interactive frames to at least the 44 × 44-point default target, keeping the glyphs visually small.

Acceptance: inspect effective hit areas and verify adjacent actions do not overlap.

## Positive observations

- The root uses a NavigationStack per tab and iOS 18 Tab APIs.
- Home uses an enum-backed sheet selection, preventing competing sheet flags.
- Recent work extracted stable list identity and persistence helpers with passing regression coverage.
- Reviewed add-joke and create-set-list paths check save success before dismissing.
- Roast takeover animation already checks Reduce Motion.
- Several common rows and toolbar actions have explicit accessibility labels.

These strengths do not establish that every persistence or accessibility path is correct.

## Follow-up runtime checklist

- [ ] Build the iOS Simulator app with resolved dependencies.
- [ ] Verify launch/setup, each standard tab, customized tabs and Roast Mode transitions.
- [ ] Exercise assistant routing, launcher activation, compact/drawer keyboard layout and long-message scrolling.
- [ ] Test smallest supported iPhone layout, landscape, iPad split view, light/dark mode.
- [ ] Test accessibility text sizes, VoiceOver, keyboard navigation and Reduce Motion.
- [ ] Exercise write/edit/background/return, failed-save recovery, trash/restore, set ordering, recording stop/save and import review.
- [ ] Measure contrast from actual rendered surfaces; capture before/after screenshots for any fixes.

## Apple references

- [Dynamic Type modifier](https://developer.apple.com/documentation/swiftui/view/dynamictypesize(_:)): setting a concrete size controls the hierarchy's text size.
- [Larger Text evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria): test accessibility sizes and avoid ambiguous truncation.
- [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/): default touch target guidance.
