# Contributing

Thanks for taking a look at BitBinder. This guide covers how to build the
project and the conventions the codebase follows.

## Prerequisites

- macOS with **Xcode 16 or newer**
- An iOS 17+ simulator or a provisioned device
- [SwiftLint](https://github.com/realm/SwiftLint) (optional, for local linting):
  `brew install swiftlint`

## Getting started

1. Clone the repository.
2. Open `thebitbinder.xcodeproj`.
3. Let Swift Package Manager resolve dependencies (driven by the tracked
   `Package.resolved`). The `.swiftpm/` working directory is git-ignored and
   regenerated locally — don't commit it.
4. Build and run the `thebitbinder` scheme.

CloudKit sync and OpenAI-backed features need the matching entitlements and an
API key. Without them the app runs local-only, so you can develop most features
without additional setup.

## Project structure

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a full breakdown. In short:
`Models/` holds the SwiftData domain, `Views/` the SwiftUI screens, `Services/`
the business logic and integrations, and `Utilities/` the cross-cutting helpers.

## Conventions

- **Code style** is enforced by SwiftLint (`.swiftlint.yml`). CI runs it on
  every pull request; run `swiftlint` locally before pushing to catch issues
  early.
- **Logging** uses the project's `print(_:)`, which is compiled to a no-op in
  release builds via `Utilities/DebugLog.swift`. Prefer a tagged prefix, e.g.
  `print(" [CloudKit] …")`, to keep diagnostics greppable.
- **Secrets never go in source.** API keys belong in the Keychain (see
  `OpenAIKeychainStore`); `Secrets.plist` is git-ignored.
- **User data is high-stakes.** Per `.github/copilot-instructions.md`: no silent
  deletes, no assumed-successful saves. Audit create/update/save/delete/import/
  export/migration/sync paths before changing them, and prefer explicit,
  recoverable destructive actions.

## Pull requests

- Branch off `main` and keep changes focused.
- Make sure SwiftLint passes and the app builds.
- Describe what changed and why, and call out any data-migration or sync impact.
