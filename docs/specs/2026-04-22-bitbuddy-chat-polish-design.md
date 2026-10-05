# BitBuddy chat polish — design

**Source:** `thebitbinder/bitnet/BitBuddy Chat & Roast Mode.html` (BitBuddy half)
**Targets:** `thebitbinder/Views/BitBuddyCompactWindow.swift`, `thebitbinder/Views/BitBuddyChatView.swift`, `thebitbinder/Views/JokesView.swift`, `thebitbinder/ContentView.swift` (puck)

## Problem
BitBuddy's compact window ships but is missing four behaviors the design calls out: no unread badge on the puck, no double-tap-to-snap, no quick-reply chips, and no way to re-summon from a dismissed state.

## Design

### 1. Unread count on the mini puck
- Extend `BitBuddyPresentationController` with `@Published var unreadCount: Int = 0`.
- Increment whenever a new assistant message arrives while `mode == .closed`. Reset to 0 when `mode` transitions to `.compact` or `.full`.
- Render in `ContentView.swift` puck view: circular red badge top-right with the count (capped at "9+"). Hidden when 0.

### 2. Double-tap header to snap to nearest corner
- In `BitBuddyCompactWindow.swift`, add a `TapGesture(count: 2)` to the drag-handle region.
- On trigger, compute the nearest corner using current window center vs screen bounds, animate with `.spring(response: 0.35, dampingFraction: 0.75)`, persist the chosen corner via existing `bitBuddyCompactCorner` UserDefault.

### 3. Quick-reply chip row
- New subview `QuickReplyChipRow` rendered above the composer inside the expanded panel.
- Source: add `@Published var suggestedReplies: [String] = []` to `BitBuddyIntentRouter` (service currently has no such property). Populated with up to 3 replies on each assistant turn; default seed for all turns is `["Merge", "Keep both", "Show me"]` until smarter generation lands.
- Tap sends the chip text as a user message and clears suggestions.

### 4. Sparkle-chat toolbar icon for re-summon
- In `JokesView.swift`, add a toolbar item (trailing, principal area) using `Image("BitBuddyGlyph")` rendered as template at accent color.
- Tap calls `bitBuddyPresenter.openCompact()`. When `unreadCount > 0`, overlay the same red count badge.

### 5. Online-status dot (hardcoded green for now)
- Small `Circle().fill(.green)` 8pt dot in the compact window header next to "BitBuddy" label.
- No plumbing to `BitBuddyService` health state in this spec; `isOnline: Bool = true` constant. Documented as a follow-up hook.

## State model
```swift
// BitBuddyPresentationController
enum Mode { case closed, compact, full }
@Published var mode: Mode = .closed
@Published var unreadCount: Int = 0
```
No schema changes.

## Testing
- Unit test: unreadCount resets to 0 on mode transition out of `.closed`.
- Unit test: double-tap snap picks the correct corner given a window center.
- Manual: toolbar icon re-summons the compact window from dismissed state; badge appears when unread > 0.

## Deferred
- Real online/offline plumbing tied to `BitBuddyService` health.
- Full-sheet "pop out" button (full drawer already reachable via existing expand button).
- Quick-reply chip AI-generation beyond the static default set.

## Rollback
All changes additive. Revert the four touched files; the dismissed/compact/full state machine is unchanged shape.
