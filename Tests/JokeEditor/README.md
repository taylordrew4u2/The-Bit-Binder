# Joke editor regression checks

From the repository root:

```sh
swiftc thebitbinder/Utilities/JokeEditorPersistence.swift Tests/JokeEditor/PersistenceRegression.swift -o /tmp/joke-editor-tests
/tmp/joke-editor-tests
```

These checks cover edit detection and success/failure behavior of the save-or-restore helper. They do not exercise SwiftData's disk store or microphone permissions.

On an iOS simulator/device:

1. Open an existing joke, read it, return to the list, then background/foreground the app. Its modification date and list position should stay unchanged.
2. Change the body, wait for autosave, leave, and reopen. Verify the body and word count; leaving after autosave should not change the modification date again.
3. On a device, dictate recognizable words, then navigate back without pressing Stop. Reopen the joke and verify the displayed transcript was appended exactly once. Repeat by backgrounding during recording.
4. Trash and restore a joke. Both successful operations should dismiss. With a forced save failure, the view should show Save Failed and retain the previous trash state, deletion date, modification date, and any pending body edits.

No model schema or migration changes are involved. Recording cleanup preserves the transcript already delivered by speech recognition; it cannot recover speech the recognizer has not transcribed.
