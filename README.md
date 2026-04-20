# thebitbinder

iOS comedy notebook for standup comics: record sets, capture bits, and extract jokes with AI.

## Layout

- `thebitbinder/` — app source (SwiftUI)
  - `Views/` — screens and reusable UI
  - `Services/` — audio, iCloud sync, AI providers, scheduling
  - `Models/` — persisted types and CloudKit schemas
  - `Utilities/` — shared helpers
- `thebitbinder.xcodeproj` — Xcode project
- `docs/archive/` — historical design and refactor notes (superseded; kept for reference)

## Build

Open `thebitbinder.xcodeproj` in Xcode 15+ and build the `thebitbinder` scheme. API keys are loaded from (in order): Keychain, per-provider `*-Secrets.plist`, `Secrets.plist`, environment. None are committed.

## Docs

Historical and deep-dive documents live in `docs/archive/`. Start with `docs/archive/DOCUMENTATION_INDEX.md` for the older index.
