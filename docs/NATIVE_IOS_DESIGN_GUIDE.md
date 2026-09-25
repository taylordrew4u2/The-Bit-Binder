# Native iOS design guide

Updated 2026-09-25 after the UI and design audits. This describes implemented conventions, not a claim that every screen has passed device visual testing.

## Direction

BitBinder is a calm writing workspace with comedy personality. Prioritize the user's words, a clear next action, and access to saved work. Standard mode uses native grouped surfaces and blue accents. Roast Mode keeps its warmer identity while following the same hierarchy and typography rules.

## Screen hierarchy

- **Home:** short greeting → New Joke with secondary Dictate/Record actions → Continue Writing → optional compact Activity → Library links. Show a writing action for an empty library; avoid repeated counts.
- **Jokes:** source-based Import Jokes menu, separate creation menu, visible scope and filter summary. All Jokes clears every filter and search. Library rows/cards provide previews, not a promise of full text.
- **Sets:** Arrange exposes Add/Reorder and numbered expandable material. Rehearse opens complete text with Next Joke progression. Idle recording is compact during arrangement; an active recording always exposes Stop.
- **Settings:** direct grouped preferences, not a repeat onboarding sequence. Keep first-launch privacy/name setup separate from returning-user customization.
- **BitBuddy:** one consistent name and descriptive controls. The existing floating launcher and editor punch-up action remain available; they should support writing without obscuring its primary controls.

## Typography and layout

Use semantic SwiftUI text styles for content. Honor system accessibility sizes even when the app's Text Size preference is overridden. Do not impose a root text-size ceiling. Fixed decorative artwork can remain fixed; content-bearing avatars and controls should scale when needed.

At accessibility sizes, allow text to wrap and switch dense horizontal layouts to vertical layouts. Scroll long empty states and forms. Use safe-area insets for editor actions so longer labels and keyboard changes do not cover the material. Full set text must not be capped to a preview line.

## Color and controls

`ActionColors.blue` (#0050B8) and `.ember` (#B83A12) are opaque fills for custom controls with `.foreground` (opaque white). The measured sRGB contrast is 7.40:1 and 5.75:1 respectively. Brand accents remain separate for links, selection and decoration. Do not reduce opacity on small filled-button labels.

Use system controls and semantic surfaces where practical. Existing `DS`, `FirePalette`, `ColdPalette`, and shared components remain in use; they are not empty legacy stubs. Native lists/forms, grouping and spacing provide the primary structure. A primary task action can use a fill; supporting actions use plain or bordered controls. Avoid adding gradients or glass solely for decoration.

## Labels and outcomes

- **Dictate / Stop Dictation:** speech becomes text; state clearly when audio is not saved.
- **Record:** audio is captured and can be saved.
- **Import Jokes:** choose Files, Photos, Camera or Audio. GagGrabber is optional secondary branding inside the review flow.
- **Show Previews:** library excerpts. Set reading is independent of this preference.
- **All Jokes / Clear All:** complete reset of library scope, tags, status and search.

Preserve stored raw preference values when changing display labels. Never change save, delete or import behavior as a side effect of a cosmetic refactor.

## Verification

Run `Tests/run-regressions.sh` and the repository SwiftLint/iOS simulator build workflows. The color regression resolves the actual SwiftUI color tokens under light, dark and increased-contrast macOS appearances; it does not measure a rendered iOS control.

Before visual sign-off, test current builds on small iPhone and iPad in light/dark and standard/roast modes, with normal and accessibility text sizes. Include long/multiline material, empty states, active filters, keyboard-visible editing and recording. Verify VoiceOver labels and focus, importing/review, filter reset, Arrange reorder, full rehearsal text, Next Joke, and Stop/save after scrolling. No current-device screenshots were available for this implementation pass.

See [design audit](DESIGN_AUDIT_2026-09-25.md) and [earlier UI audit](UI_UX_AUDIT_2026-09-25.md) for evidence and limitations.
