# Siri and Shortcuts

BitBinder provides three App Shortcuts on iOS 18 and later:

| Say to Siri | Behavior |
| --- | --- |
| “Save a joke in BitBinder” | Siri asks for the joke and saves it to the library. |
| “Find jokes in BitBinder” | Siri asks for search text and opens matching active jokes. |
| “Open my sets in BitBinder” | Opens the existing set-list screen. |

Open the installed app once and complete or skip setup. Enable Siri in device settings. All three actions require authentication to access the user's writing. They are also available in the Shortcuts app, including as actions in custom shortcuts. Settings → Siri & Shortcuts explains the commands in the app.

## Data and navigation behavior

- Saving uses the app's registered SwiftData container and a separate context. It does not save or roll back an editor's pending changes.
- Only a successful persistent save produces a success dialog. Blank input, temporary/read-only storage, pending restores, and save failures return errors.
- Repeating the same text creates another joke; intentional repetitions are not silently discarded.
- Search matches title and content, excludes Trash, and leaves library filters and tab preferences unchanged.
- Foreground commands wait for setup and an active scene. They open above existing presentations so a draft remains underneath. Dismissing the Siri screen consumes that request and advances any later commands.

## Automated checks

Run `Tests/run-regressions.sh` for capture normalization, storage validation, and save/rollback sequencing alongside existing regressions.

Run the `thebitbinderTests/SiriIntegrationTests` suite on an iOS Simulator using the shared `thebitbinder` scheme. It uses temporary stores with the real models to test durable reloads, invalid storage/input, repeated captures, isolation from pending editor edits, and foreground routing. Keep normal ad-hoc simulator signing enabled: the app host initializes CloudKit and needs its entitlements even when individual test stores disable CloudKit.

## Device release check

Simulator tests and extracted App Intents metadata do not prove Siri's speech recognition or device indexing. Before release, install the signed app on a physical iPhone and verify:

1. All three actions appear in Shortcuts under BitBinder.
2. Ask Siri to save a joke, supply the text, and check the library after restarting the app.
3. Ask Siri to find a distinctive phrase and open a matching joke.
4. Ask Siri to open sets, then dismiss back to the previous screen.
5. Repeat Find Jokes and Open Sets while a new-joke draft is open; confirm the draft remains intact afterward.
6. Invoke from a locked device, confirm authentication, and test both a cold and warm app launch.

These changes add development-build support; an App Store release is a separate step.
