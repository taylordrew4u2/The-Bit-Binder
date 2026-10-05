# Roast Mode v2 behaviors — design

**Source:** `thebitbinder/bitnet/Roast Mode v2.html`
**Targets:** `thebitbinder/Views/RoastTargetDetailView.swift`, `thebitbinder/Views/SettingsView.swift`, `thebitbinder/Services/BitBuddyService.swift`, `thebitbinder/Utilities/RoastModeTint.swift`, and the current Roast target list entry point (no dedicated `RoastTargetListView.swift` exists — the implementation plan locates and edits whichever view currently presents the list, likely a section inside `HomeView.swift`)
**New files:** `thebitbinder/Services/RoastHeatService.swift`, `thebitbinder/Views/RoastColdStateView.swift`, `thebitbinder/Views/RoastBuddyChatView.swift`, `thebitbinder/Views/RoastIntensitySlider.swift`

## Problem
Phase 3 shipped the palette and `HeatMeter`, but Roast Mode still lacks the behavioral layer: no formula behind heat, no empty state when the user has no targets, no Roast Buddy persona or intensity control, and no safety rails at the prompt layer.

## Design

### 1. `RoastHeatService` (new)
Single source of truth for per-target heat.
```swift
struct HeatInputs {
    let bitCount: Int
    let recentPracticeDays: Int   // sessions in last 7 days
    let lastHitDaysAgo: Int       // days since last performance tagged "hit"
    let daysSinceUsed: Int        // days since any interaction
}
func heat(for target: RoastTarget) -> Double // 0..100
```
Formula:
```
heat = min(100, max(0, bitCount*4 + recentPracticeDays*8
                 + (lastHitDaysAgo <= 3 ? 20 : 0)
                 - daysSinceUsed*2))
```
Values are pure functions of `RoastTarget` snapshot data; no persistence. Cached in an `@Published` dictionary keyed by target ID, invalidated on any target or joke mutation.

### 2. Warming-threshold state machine
`RoastModeTint` (existing) gains:
```swift
enum WarmingState { case cold, warm, hot }
static func state(targetCount: Int, maxHeat: Double) -> WarmingState
```
- `cold` if `targetCount == 0`
- `warm` if `targetCount >= 1 && maxHeat < 60`
- `hot` if `maxHeat >= 60`

The Roast list view selects its background palette from this state: ashy `#161210` (cold) → amber-accented neutral (warm) → full `FirePalette.ambient` (hot).

### 3. `RoastColdStateView`
Shown by the roast list view when `state == .cold`.
- Background: `Color(hex: 0x161210)`.
- Content: SF Symbol `flame.slash` at 120pt, `Color.secondary`, plus copy `Nothing to burn yet` (title2) and a one-line explainer.
- Primary CTA: ember-gradient button "Light the first match" → opens existing add-target sheet.
- Secondary: `Button("or import from Contacts")` — Contacts import is not in scope; render disabled with caption `"coming soon"` and track as a follow-up task.

### 4. `RoastIntensitySlider`
Segmented control persisted as `UserDefaults` key `roastIntensity` (String: `"gentle" | "mean" | "brutal"`, default `"mean"`). Rendered in `SettingsView` and in the `RoastBuddyChatView` header. Changing intensity takes effect on the next assistant turn.

### 5. `RoastBuddyChatView`
Thin variant of `BitBuddyChatView`:
- Same transcript + composer structure.
- Palette forced to `FirePalette.*` regardless of system color scheme.
- Header shows an intensity pill ("GENTLE / MEAN / BRUTAL") and a prominent "Back to BitBuddy" button that exits Roast Mode entirely (calls existing exit path).
- When user lacks a charred glyph asset, reuse `BitBuddyGlyph` tinted `FirePalette.flame`. Charred glyph asset is out of scope.

### 6. Safety rails (`BitBuddyService`)
Extend the system prompt used for Roast Mode only:
```
Rules:
- Only roast subjects explicitly added by the user. Never invent or suggest real people.
- Refuse any request to mock protected classes (race, religion, disability, sexuality, gender identity, national origin, etc.). If asked, respond: "Not my style. Pick something about them, not what they are."
- Honor the intensity setting: Gentle (playful), Mean (sharp but personal), Brutal (uncensored, still no protected classes).
```
Routing: `BitBuddyService.sendRoastMessage(...)` appends these rules and the current `roastIntensity` string to the base prompt.

### 7. Header copy
The Roast list entry point's header switches to `"Who's getting roasted?"` with subtitle `"{hot} burning · {warm} warm."` driven by heat thresholds (`hot >= 85`, `warm >= 30`).

## Testing
- Unit: `heat(for:)` boundary cases (zero, all-positive, far-past target clamps to 0).
- Unit: `WarmingState.state(targetCount:maxHeat:)` transition table.
- Unit: protected-class refusal — snapshot the prompt additions.
- Manual: toggling intensity in Settings reflects in the header pill without restart.
- Manual: cold state shows with 0 targets; disappears after adding one.

## Deferred
- Ceremonial takeover transition (flame wipe + badge bloom). Tracked as follow-up skill-polish task.
- Charred RoastBuddy glyph asset (needs design file).
- Heat-aware color ramp on `HeatMeter` (current flat gradient acceptable).
- Whoosh sound on mode entry.
- Contacts import for "import from Contacts" secondary CTA.

## Rollback
- `RoastHeatService` is additive.
- `RoastBuddyChatView`/`RoastColdStateView`/`RoastIntensitySlider` are new files → `git rm`.
- `RoastModeTint` change is a single new type + static fn, revertable.
- Prompt additions in `BitBuddyService` live in one extension method, revertable.
No storage migration.
