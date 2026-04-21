# BitBuddy + Roast Mode patch

Three drop-in changes. Apply in order — each phase is independent; stop
after any phase if you want to ship it alone.

---

## Phase 1 — New BitBuddy icon & avatar

**Goal:** the new blue-tile BitBuddy mark replaces the placeholder in
three image assets + the app icon.

**Files in `patch/Assets.xcassets/`:**
- `BitBuddyIcon.imageset/` — full blue-tile icon (80pt @ 1x/2x/3x).
  Shown on the launch screen, in `BitBuddyChatView`'s header, and
  anywhere `Image("BitBuddyIcon")` is used.
- `BitBuddyGlyph.imageset/` — white glyph on transparent, template-
  rendered so iOS recolors it with the current tint. Used for toolbar
  buttons and anywhere the glyph should inherit accent color.
- `BotAvatar.imageset/` — same template glyph, kept under the existing
  `AssetNames.botAvatar` constant.
- `AppIcon.appiconset/Appicon.png` — 1024×1024 home-screen icon.

**To apply:**
1. In Xcode → Project Navigator → Assets.xcassets, delete these four
   imagesets (`BitBuddyIcon`, `BitBuddyGlyph`, `BotAvatar`, and the
   `Appicon.png` inside `AppIcon`).
2. Drag the replacement folders from `patch/Assets.xcassets/` into the
   same location in Xcode. Choose "Copy items if needed" when prompted.
3. Clean build folder (⌘⇧K) — avoids asset-cache mismatches.
4. Run. Verify launch screen, the floating puck, and in-chat header all
   show the new mark.

Nothing in Swift needs to change — the asset names are preserved.

---

## Phase 2 — Compact floating BitBuddy window

**Goal:** tapping the draggable BitBuddy puck opens a 300×380 floating
chat window pinned to a corner. An expand button in its header
promotes it to the existing full-screen drawer.

**New file:** `patch/Views/BitBuddyCompactWindow.swift` → copy into
`ITSBITNERYBIT/thebitbinder/Views/`.

**Edits to existing files:**

### `ContentView.swift`

Add near the other `@StateObject`s in `MainTabView`:

```swift
@StateObject private var bitBuddyPresenter = BitBuddyPresentationController()
```

Change the puck's tap action (search for `bitBuddyDrawer.open()` inside
the `TapGesture` at line ~281):

```swift
// before
bitBuddyDrawer.open()
// after
bitBuddyPresenter.openCompact()
```

At the bottom of `MainTabView.body`, right after `.bitBuddyDrawer(...)`
(line ~292), add:

```swift
.bitBuddyCompactWindow(presenter: bitBuddyPresenter, roastMode: roastMode)
.onChange(of: bitBuddyPresenter.mode) { _, mode in
    // Keep the full-drawer controller in sync with the presenter so
    // existing call sites that open .full still route correctly.
    bitBuddyDrawer.isOpen = (mode == .full)
}
```

Replace the `.opacity(bitBuddyDrawer.isOpen ? 0 : 1)` and
`.allowsHitTesting(!bitBuddyDrawer.isOpen)` on the puck with:

```swift
.opacity(bitBuddyPresenter.mode == .closed ? 1 : 0)
.allowsHitTesting(bitBuddyPresenter.mode == .closed)
```

so the puck hides the moment the compact window opens.

### Result
- Tap puck → compact window springs from nearest corner.
- Drag window header → it snaps to the closest corner on release
  (position persists across launches via `bitBuddyCompactCorner`).
- ⤢ button → promotes to full drawer (unchanged behavior).
- ✕ button → back to puck.
- Long tool-use responses still get the full drawer automatically
  because the expand action is one tap away.

---

## Phase 3 — Roast Mode refinement

**Goal:** Roast Mode reads as its own product, not a dark-mode toggle.
Ember-warm canvas, refined amber/gold accents, per-target heat meter.

**Replace in place:** `ITSBITNERYBIT/thebitbinder/Utilities/FirePalette.swift`
with `patch/Utilities/FirePalette.swift`. API is backward-compatible
(same static members + new ones) — nothing else needs to change to
benefit from the softer accents.

**New file:** `patch/Utilities/HeatMeter.swift` → copy into
`ITSBITNERYBIT/thebitbinder/Utilities/`.

**Suggested integrations (optional, hand-tune in Xcode):**

1. **`RoastTargetDetailView`** — add a `HeatMeter` below the target
   name with `value: min(1.0, Double(target.jokes.count) / 10.0)` or a
   recency-weighted score. Use `glowWhenHot: true` on the hero card.

2. **Roast-target list rows** — compact variant:
   ```swift
   HeatMeter(value: score, segments: 5, segmentHeight: 6, glowWhenHot: false)
       .frame(width: 60)
   ```

3. **`SettingsView` Roast Mode toggle card** — wrap the existing
   section in a card with `.background(FirePalette.ambient)` and the
   flame icon filled with `FirePalette.flame` (LinearGradient mask).

4. **Any full-screen Roast surface** — swap flat black backgrounds for
   `FirePalette.ambient` ignoring safe area.

Nothing in Phase 3 is load-bearing — existing `.fireCore`, `.fireEmber`,
`.flame` references keep working unchanged.

---

## Rollback

Each phase is file-scoped and reversible:

- Phase 1: restore the old imagesets from Git.
- Phase 2: `git rm BitBuddyCompactWindow.swift`, revert
  `ContentView.swift`. The controller, drawer, and chat view are
  untouched.
- Phase 3: revert `FirePalette.swift`, `git rm HeatMeter.swift`. No
  other files are modified.
