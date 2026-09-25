# Design audit — 2026-09-25

## Assessment

BitBinder has a useful native foundation, but the interface gives too much prominence to management controls, repeated statistics, and helper features relative to the user's writing and rehearsal. The most valuable design change is to make the material itself the focus: resume a draft, write a joke, arrange a set, and read it comfortably.

This is a design audit, not an implemented redesign. Findings concern the source at `b5123f0`, after the seven earlier UI fixes. Those fixes remain in place.

## Evidence and limits

Reviewed current SwiftUI screen composition, labels, component styles, color assets, app icon, and key action paths. Also inspected the [published App Store screenshots](https://apps.apple.com/us/app/the-bitbinder/id6756085897) for visual context. Their asset filenames reference April/May 2026, and their Home/Settings composition differs from current source; they are not proof of the current build's appearance.

No current-build simulator screenshots were available on this Mac. Screen ordering, strings, explicit colors, and code behavior below are source-confirmed. Perceived density, exact clipping, resolved system colors, and usability impacts require rendered or user validation. Contrast figures are calculated from source sRGB values, not sampled from screenshots.

Applied SwiftUI Expert/native SwiftUI guidance. The commerce-focused choice-architecture skill was reviewed but not applied because its upsell and conversion framework does not fit this task.

## Fix first

### 1. Make set lists usable for reading and rehearsal

**Evidence:** [SetListDetailView](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/SetListDetailView.swift#L96) displays regular jokes as plain rows with no navigation or expansion. [JokeRowView](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/JokeComponents.swift#L128) reduces each body to its first line, and line 169 caps that preview to one line. The menu still offers “Show Full Content.”

**Impact:** The interface promises readable material but delivers a library preview. A comedian cannot read the full regular joke from this set screen. This is a behavior/design-contract issue, not merely a styling preference.

**Change:** Give set lists their own numbered row with full-text expansion. Offer clear Arrange and Rehearse states. Arrange should prioritize Add Jokes and Reorder; Rehearse should prioritize readable joke text, progression and optional recording. Rename library-only settings to “Show previews” where that is the actual behavior.

The [recording panel](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/SetListDetailView.swift#L57) currently precedes the material even for empty sets, while Edit Order is inside overflow. Collapse recording to a compact action during preparation and expand it when active.

**Acceptance:** A multiline joke can be read and rehearsed in full without leaving its set; recording controls do not dominate preparation.

### 2. Distinguish dictation from saved audio

**Evidence:** [Editor action bar](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/JokeDetailView.swift#L357) says “Record,” but [its stop handler](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/JokeDetailView.swift#L514) appends transcribed text to the joke. The set screen's recording action instead saves an audio Recording.

**Impact:** Identical language creates different expectations about whether audio will be available later.

**Change:** Use “Dictate” and “Stop dictation” in the editor, with “Adds speech to this joke.” Reserve “Record” for audio that is saved. Standardize “Talk-to-Text,” “Capture Idea,” and related labels around the actual outcome: Dictate Idea, Write Joke, Record Set.

**Acceptance:** Before starting capture, users can tell whether they will receive text, audio, or both.

### 3. Strengthen primary-action contrast and finish local text scaling

**Evidence:** [EmberCTAButton](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/RoastButtons.swift#L30) uses fixed 15-point bold white labels over [the ember gradient](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Utilities/FirePalette.swift#L66). The source endpoint pairs calculate to **2.85:1 and 3.96:1**. Both are below a conservative 4.5:1 normal-text target; the brighter end also falls below 3:1.

The source blue/white pairs in the accent asset calculate to **4.02:1 in light appearance and 3.64:1 in dark appearance**. These are additional candidates for rendered verification in the Home primary tile and Setup buttons, not a blanket judgment about all native blue controls.

**Change:** Separate the brand accent from the filled-button background token. Use a darker solid fill or a gradient whose entire label region meets contrast targets. For illustration, white on sRGB #B83A12 calculates to 5.75:1; validate the complete component before adopting it. Remove opacity reductions from small button subtitles.

The root now honors accessibility text sizes, but [Roast target names/notes/counts](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/RoastHomeComponents.swift#L209) and the shared roast buttons still use fixed-size fonts. Replace content fonts with semantic styles and scale supporting geometry. This is separate from the earlier root-setting fix.

**Acceptance:** Verify actual labels in both appearances and increased contrast, plus every accessibility text size. Use the [WCAG contrast method](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) as a measurement aid; this audit is not a compliance certification.

## Simplify next

### 4. Put resumable work ahead of Home statistics

**Evidence:** [Home](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/HomeView.swift#L111) orders the greeting, quick actions, four statistic cards, and then Recent. The greeting subtitle and header pills already repeat weekly activity and joke counts. All Home sections are enabled by default.

**Impact:** The dashboard repeats information while the material someone came back to work on appears later. This is a hierarchy judgment; exact scrolling distance has not been measured.

**Change:** Use this order: short greeting → New Joke with secondary Dictate/Record actions → Continue Writing / Recent → optional compact activity summary. Keep one instance of each count. Show a useful first-joke action for an empty library instead of making zero-value statistics prominent.

**Acceptance:** Returning users can recognize their latest draft before interacting with statistics. Validate on a small iPhone and with large text.

### 5. Unify import around the source, not the internal feature name

**Evidence:** [Jokes import menu](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/JokesView.swift#L961) presents GagGrabber (Extract Jokes), Import from Files, Scan with Camera, Import from Photos and Import from Voice Memos. The app shell also supplies a separate unlabeled visual GagGrabber glyph. [GagGrabber's own screen](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Services/HybridGagGrabber.swift#L296) explains file import and offers another file picker after instructional content.

**Impact:** People must understand the difference between two file/extraction routes before completing the same task. A mascot glyph is less discoverable than a descriptive import label for a first-time user.

**Change:** One entry labeled “Import Jokes,” followed by Files, Photos, Camera and Audio. Retain GagGrabber as optional personality inside the flow. Put the source picker before formatting advice; make that advice a disclosure.

**Acceptance:** Given a PDF or photo, a first-time user can choose the source without knowing what GagGrabber means.

### 6. Clarify library scope and active filters

**Evidence:** The [All chip](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/JokesView.swift#L201) clears folder/status choices but leaves the active tag untouched. [Tag filtering](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/JokesView.swift#L399) composes with that scope. The screen does include a removable tag chip; the issue is the meaning of “All,” not a total absence of filter feedback.

**Impact:** “All” can be selected while the user is looking at a subset. This risks making material feel missing.

**Change:** Separate the scope row from applied filters. Use “All Jokes” as an unambiguous reset, or “All Folders” if the tag is intentionally retained. Show a compact result summary and a clear reset action whenever filtering is active.

**Acceptance:** A user can explain why a joke is hidden and return to the complete library in one action.

### 7. Make customization direct and helper branding consistent

**Evidence:** [Customize App](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/AppSetupView.swift#L43) opens a six-page sequence containing privacy, name, tabs, Home, joke layout and a ready page. Settings also provides a direct name editor. The helper is called “Buddy” in [Settings](https://github.com/taylordrew4u2/The-Bit-Binder/blob/b5123f0617f5d6c77e6cf9387072aaec6d9e99f4/thebitbinder/Views/SettingsView.swift#L117) and “BitBuddy” in its launcher/chat.

**Impact:** Changing one display preference requires navigating a setup flow, and inconsistent naming makes a secondary feature harder to recognize.

**Change:** Replace repeat onboarding with a normal preferences list: Appearance, Navigation, Home, Writing, Privacy. Use “BitBuddy” consistently, with plain language describing its role. Keep the mascot recognizable but give it less visual weight than writing actions; consider a contextual assistant control in the editor instead of relying on an always-floating puck.

**Acceptance:** A returning user can change tabs or layout directly, and identify the assistant by the same name throughout.

## Visual direction

**A calm writing workspace with comedy personality.** Preserve semantic system surfaces, readable native type, and a restrained blue accent. Let the user's words occupy the strongest area of each screen. Keep roast warmth as a deliberate alternate palette, with the same action hierarchy, typography roles and spacing rules.

| Element | Proposed rule |
| --- | --- |
| Primary action | One clear filled action per task state |
| Secondary actions | Plain or bordered; descriptive labels before brand names |
| Material | Strong readable text, then status, then metadata |
| Statistics | Compact supporting information, never a duplicate hero |
| Mascot/assistant | Contextual help, visually subordinate to writing |
| Surfaces | A documented family of cards and panels by role |
| Color | Separate brand, interactive, recording, destructive and status roles |

The app already has native lists/forms, semantic colors, clearer action labels in many places, and recently improved Dynamic Type and assistant layout behavior. Preserve those strengths. Do not add ornamental glass, gradients or animations merely to make the app appear more “designed.”

Apple recommends [consistent color meaning](https://developer.apple.com/design/human-interface-guidelines/color) and [labels that explain context and actions](https://developer.apple.com/design/human-interface-guidelines/labels). These support the recommendations; predicted usability improvements still need testing.

## Implementation sequence

1. Correct set reading and capture labels; define accessible filled-action colors.
2. Simplify Home, import and filter hierarchy.
3. Replace the customization wizard and standardize helper terminology.
4. Capture current-build screens, then refine spacing, radii and visual balance.

The existing native-design guide describes a historical design state and conflicts with current tokens/components. Update it when the visual rules are agreed, rather than treating it as an accurate specification.

## Validation required before visual sign-off

Capture current-build iPhone and iPad screens with realistic long jokes and set lists, including empty/populated/search/filter states, keyboard-visible editing, active recording, standard/roast appearances and accessibility text sizes. Then test: resume a draft, dictate a line, import a PDF, clear filters, reorder a set, and read it in full. Check contrast on actual rendered controls and ask users what each capture action will save.

No implementation changes or tests were needed for this documentation-only audit.
