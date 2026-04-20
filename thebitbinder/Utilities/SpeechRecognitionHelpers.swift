//
//  SpeechRecognitionHelpers.swift
//  thebitbinder
//
//  Shared reliability helpers for every SFSpeechRecognizer-backed feature
//  (Talk-to-Text → Joke, Talk-to-Text → Roast, Brainstorm voice notes, and
//  audio-file transcription). Centralising this means one place to fix
//  locale fallback, error messaging, and restart pacing — rather than three
//  drifting copies.
//
//  What this file provides:
//   • `SpeechReliability` — tuning constants (restart cap, backoff,
//     retry delay) that every speech feature should respect so behaviour
//     feels consistent.
//   • `SpeechErrorCode` — the magic kAFAssistantErrorDomain codes we
//     special-case across the app (cancelled / "no speech" timeout).
//   • `SFSpeechRecognizer.preferred(...)` — resolve a working recognizer,
//     preferring en-US, falling back to the user's current locale, and
//     finally any supported locale. Prevents the "recognizer is nil" dead
//     end that can happen when en-US models aren't downloaded.
//   • `SpeechErrorMapper.userMessage(for:)` — translate the most common
//     recognition errors into short, human copy that fits in the UI.
//

import Foundation
import Speech

// MARK: - Reliability Constants

/// App-wide tuning for speech recognition restart / retry behaviour.
/// Every Talk-to-Text style feature should pull values from here so the
/// UX feels consistent (and so we can tune them in one place).
enum SpeechReliability {
    /// Max consecutive auto-restarts that happen without any new text being
    /// recognised. After this many empty restarts in a row we stop so we
    /// don't burn battery on a broken session.
    static let maxConsecutiveEmptyRestarts: Int = 5

    /// Delay before the next auto-restart kicks off after iOS's ~60s
    /// recognition window or an `isFinal` result. Short enough to feel
    /// continuous, long enough to avoid hammering the speech service.
    static let restartDelay: TimeInterval = 0.3

    /// Additional backoff added per consecutive empty restart so repeated
    /// failures don't thrash the audio stack.
    static let restartBackoffStep: TimeInterval = 0.25

    /// Delay before retrying audio-session activation after a transient
    /// failure (e.g. another app briefly held the category).
    static let audioSessionRetryDelay: TimeInterval = 0.3

    /// Max wall-clock wait for an offline file transcription before we
    /// give up — SFSpeechRecognizer has been observed to hang on some
    /// inputs.
    static let fileTranscriptionTimeout: TimeInterval = 60
}

// MARK: - Error Codes

/// Magic numbers from Apple's speech framework that we special-case. Pulled
/// out of `kAFAssistantErrorDomain` NSError instances and compared across
/// every recognition task callback in the app.
enum SpeechErrorCode {
    /// `kAFAssistantErrorDomain` — used by SFSpeechRecognizer internals.
    static let domain = "kAFAssistantErrorDomain"

    /// User (or our code) cancelled the recognition task. Silent — no UI.
    static let cancelled = 216

    /// "No speech detected" / session timeout. Treat as an auto-restart
    /// trigger, not a user-facing error.
    static let noSpeechTimeout = 1110

    /// True if the error is the "task was cancelled" code — we should
    /// swallow it and not show an error to the user.
    static func isCancelled(_ error: NSError) -> Bool {
        error.domain == domain && error.code == cancelled
    }

    /// True if the error is the silence/timeout code — we should auto-restart
    /// rather than surface the error.
    static func isNoSpeechTimeout(_ error: NSError) -> Bool {
        error.domain == domain && error.code == noSpeechTimeout
    }
}

// MARK: - Recognizer Resolution

extension SFSpeechRecognizer {
    /// Resolve the best available speech recognizer with graceful locale
    /// fallback. Order of preference:
    ///   1. The requested locale (default `en_US`) if its model is installed
    ///      and the recognizer reports `isAvailable`.
    ///   2. The user's current device locale.
    ///   3. Any locale in `SFSpeechRecognizer.supportedLocales()` that
    ///      returns an available recognizer.
    ///
    /// Returns `nil` only if the device has no supported recognizer at all
    /// (very rare — usually means speech recognition is fully unavailable).
    ///
    /// This exists so every feature that needs speech input degrades
    /// gracefully instead of dead-ending at "speech recognition is not
    /// available" just because en-US models weren't downloaded.
    static func preferred(
        primary primaryLocale: Locale = Locale(identifier: "en-US")
    ) -> SFSpeechRecognizer? {
        // Try the primary locale first.
        if let r = SFSpeechRecognizer(locale: primaryLocale), r.isAvailable {
            return r
        }

        // Fall back to the current device locale (only if different).
        let current = Locale.current
        if current.identifier != primaryLocale.identifier,
           let r = SFSpeechRecognizer(locale: current), r.isAvailable {
            return r
        }

        // Last resort: scan supported locales and pick the first available.
        for locale in SFSpeechRecognizer.supportedLocales() {
            if locale.identifier == primaryLocale.identifier { continue }
            if locale.identifier == current.identifier { continue }
            if let r = SFSpeechRecognizer(locale: locale), r.isAvailable {
                return r
            }
        }

        // No working recognizer on this device.
        return nil
    }
}

// MARK: - Error Messaging

/// Translates recognition errors into short, user-friendly copy that fits
/// in a tiny label under the transcription area. Don't show raw
/// `error.localizedDescription` in the UI — it's often developer-speak
/// (e.g. "The operation couldn't be completed. (kAFAssistantErrorDomain
/// error 1700.)").
enum SpeechErrorMapper {
    /// Human-readable message for recognition errors, with sensible
    /// fallbacks. Returns nil for errors we want to silently swallow
    /// (e.g. cancelled / "no speech" — those are handled elsewhere via
    /// auto-restart).
    static func userMessage(for error: Error) -> String? {
        let ns = error as NSError

        // Cancelled — swallow. Caller already knows.
        if SpeechErrorCode.isCancelled(ns) { return nil }

        // Silence timeout — swallow; caller auto-restarts.
        if SpeechErrorCode.isNoSpeechTimeout(ns) { return nil }

        // Known kAFAssistantErrorDomain codes worth surfacing cleanly.
        if ns.domain == SpeechErrorCode.domain {
            switch ns.code {
            case 1700, 1701:
                return "Speech service is busy. We'll try again in a moment."
            case 203:
                return "No internet connection for speech recognition. Reconnect and try again."
            case 1107, 1109:
                return "The microphone was interrupted. Tap Start Recording to try again."
            default:
                return "Recognition paused. Tap Start Recording to continue."
            }
        }

        // Anything else — keep it short but informative.
        return "Recognition paused. Tap Start Recording to continue."
    }
}
