//
//  AudioTranscriptionService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 1/4/26.
//

import Foundation
import Speech
@preconcurrency import AVFoundation

/// Result of transcribing an audio file
struct AudioTranscriptionResult {
    let transcription: String
    let confidence: Float
    let originalFilename: String
    let importDate: Date
    let duration: TimeInterval?
    
    var confidencePercentage: Double {
        Double(confidence) * 100
    }
}

/// Error types for audio transcription
enum AudioTranscriptionError: LocalizedError {
    case authorizationDenied
    case authorizationNotDetermined
    case fileNotFound
    case unsupportedFormat
    case audioExportFailed(String)
    case transcriptionFailed(String)
    case noSpeechDetected
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission was denied. Please enable it in Settings."
        case .authorizationNotDetermined:
            return "Speech recognition permission has not been requested."
        case .fileNotFound:
            return "The audio file could not be found."
        case .unsupportedFormat:
            return "The audio format is not supported."
        case .audioExportFailed(let message):
            return "Could not prepare audio for transcription: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .noSpeechDetected:
            return "No speech was detected in the audio file."
        }
    }
}

class AudioTranscriptionService {
    
    static let shared = AudioTranscriptionService()
    
    /// Supported audio file extensions
    static let supportedExtensions: Set<String> = ["m4a", "wav", "mp3", "aac", "caf", "aiff", "aif"]
    private static let directTranscriptionLimit: TimeInterval = 55
    private static let chunkDuration: TimeInterval = 45
    
    private var speechRecognizer: SFSpeechRecognizer?

    private init() {
        // Locale fallback: en-US → current locale → any supported locale.
        // See SpeechRecognitionHelpers.swift. This means imported audio still
        // transcribes even when en-US models aren't downloaded.
        speechRecognizer = SFSpeechRecognizer.preferred()
    }

    /// Check if speech recognition is available. Re-resolves the recognizer
    /// on each call so newly-downloaded models get picked up without needing
    /// to relaunch the app.
    var isAvailable: Bool {
        if speechRecognizer?.isAvailable == true { return true }
        speechRecognizer = SFSpeechRecognizer.preferred()
        return speechRecognizer?.isAvailable ?? false
    }
    
    /// Request speech recognition authorization
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    /// Check current authorization status
    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
    
    /// Check if a file extension is supported
    static func isSupported(fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }
    
    /// Transcribe an audio file at the given URL
    /// - Parameter url: The URL of the audio file to transcribe
    /// - Returns: The transcription result
    func transcribe(audioURL url: URL) async throws -> AudioTranscriptionResult {
        // Check authorization
        let status = Self.authorizationStatus
        if status != .authorized {
            if status == .notDetermined {
                let newStatus = await Self.requestAuthorization()
                if newStatus != .authorized {
                    throw AudioTranscriptionError.authorizationDenied
                }
            } else {
                throw AudioTranscriptionError.authorizationDenied
            }
        }
        
        // Check if recognizer is available. Re-resolve once via locale
        // fallback if our cached recognizer is nil or temporarily unavailable
        // — models may have downloaded since init.
        if speechRecognizer == nil || speechRecognizer?.isAvailable == false {
            speechRecognizer = SFSpeechRecognizer.preferred()
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw AudioTranscriptionError.transcriptionFailed("Speech recognizer is not available")
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioTranscriptionError.fileNotFound
        }
        
        // Check file extension
        let ext = url.pathExtension.lowercased()
        guard Self.isSupported(fileExtension: ext) else {
            throw AudioTranscriptionError.unsupportedFormat
        }
        
        let transcriptionURL = try prepareTranscriptionInput(from: url)
        defer {
            if transcriptionURL != url {
                try? FileManager.default.removeItem(at: transcriptionURL)
            }
        }

        let duration = try? await getAudioDuration(url: transcriptionURL)
        let output: RecognitionOutput
        if let duration, duration > Self.directTranscriptionLimit {
            output = try await transcribeInChunks(audioURL: transcriptionURL, duration: duration, recognizer: recognizer)
        } else {
            output = try await transcribeSingleFile(audioURL: transcriptionURL, recognizer: recognizer)
        }
        
        let transcription = output.transcription
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioTranscriptionError.noSpeechDetected
        }
        
        return AudioTranscriptionResult(
            transcription: transcription,
            confidence: output.confidence,
            originalFilename: url.lastPathComponent,
            importDate: Date(),
            duration: duration
        )
    }

    private struct RecognitionOutput {
        let transcription: String
        let confidence: Float
    }

    private func prepareTranscriptionInput(from url: URL) throws -> URL {
        let ext = url.pathExtension.lowercased()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitbinder_transcription_input_\(UUID().uuidString)")
            .appendingPathExtension(ext.isEmpty ? "m4a" : ext)

        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.copyItem(at: url, to: temporaryURL)
            return temporaryURL
        } catch {
            throw AudioTranscriptionError.audioExportFailed("Could not create a stable transcription copy: \(error.localizedDescription)")
        }
    }

    private func transcribeSingleFile(
        audioURL url: URL,
        recognizer: SFSpeechRecognizer
    ) async throws -> RecognitionOutput {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        
        // Perform recognition
        // We keep a reference to the task so we can cancel it on timeout.
        // We also retain the last non-empty partial result so that the terminal
        // nil-result / nil-error callback does not incorrectly throw noSpeechDetected.
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            // NSLock guards all mutable state shared between the timeout work item
            // (DispatchQueue.global()) and the recognitionTask callback (internal
            // SFSpeechRecognizer queue). Using NSLock instead of DispatchQueue.sync
            // avoids blocking Swift concurrency cooperative pool threads.
            let guard_lock = NSLock()
            var completed = false
            var lastResult: SFSpeechRecognitionResult?
            var task: SFSpeechRecognitionTask?
            
            // Hard timeout – SFSpeechRecognizer can hang on some files.
            // Pulled from SpeechReliability so we can tune in one place.
            let timeoutWork = DispatchWorkItem {
                guard_lock.lock()
                defer { guard_lock.unlock() }
                guard !completed else { return }
                completed = true
                task?.cancel()
                if let best = lastResult {
                    continuation.resume(returning: best)
                } else {
                    continuation.resume(throwing: AudioTranscriptionError.transcriptionFailed("Transcription timed out"))
                }
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + SpeechReliability.fileTranscriptionTimeout,
                execute: timeoutWork
            )
            
            task = recognizer.recognitionTask(with: request) { result, error in
                guard_lock.lock()
                defer { guard_lock.unlock() }
                guard !completed else { return }
                    
                    if let result = result {
                        lastResult = result
                        if result.isFinal {
                            timeoutWork.cancel()
                            completed = true
                            continuation.resume(returning: result)
                        }
                        return
                    }
                    
                    // Terminal callback: result == nil
                    timeoutWork.cancel()
                    completed = true
                    if let error = error {
                        // If we already have a good partial result, use it rather than throwing
                        if let best = lastResult, !best.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            continuation.resume(returning: best)
                        } else {
                            continuation.resume(throwing: AudioTranscriptionError.transcriptionFailed(error.localizedDescription))
                        }
                    } else if let best = lastResult {
                        continuation.resume(returning: best)
                    } else {
                        continuation.resume(throwing: AudioTranscriptionError.noSpeechDetected)
                    }
            }
        }
        
        let transcription = result.bestTranscription.formattedString
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioTranscriptionError.noSpeechDetected
        }
        
        let segments = result.bestTranscription.segments
        let avgConfidence: Float = segments.isEmpty ? 0.5 : segments.reduce(0) { $0 + $1.confidence } / Float(segments.count)
        
        return RecognitionOutput(
            transcription: transcription,
            confidence: avgConfidence
        )
    }

    private func transcribeInChunks(
        audioURL url: URL,
        duration: TimeInterval,
        recognizer: SFSpeechRecognizer
    ) async throws -> RecognitionOutput {
        let asset = AVURLAsset(url: url)
        var chunkURLs: [URL] = []
        defer {
            for chunkURL in chunkURLs {
                try? FileManager.default.removeItem(at: chunkURL)
            }
        }

        var outputs: [RecognitionOutput] = []
        var start: TimeInterval = 0
        var chunkIndex = 0

        while start < duration {
            let length = min(Self.chunkDuration, duration - start)
            let chunkURL = try await exportChunk(
                asset: asset,
                originalURL: url,
                start: start,
                duration: length,
                index: chunkIndex
            )
            chunkURLs.append(chunkURL)

            do {
                let output = try await transcribeSingleFile(audioURL: chunkURL, recognizer: recognizer)
                outputs.append(output)
            } catch AudioTranscriptionError.noSpeechDetected {
                // A silent section should not fail the whole recording.
            }

            start += Self.chunkDuration
            chunkIndex += 1
        }

        guard !outputs.isEmpty else {
            throw AudioTranscriptionError.noSpeechDetected
        }

        let transcription = outputs
            .map(\.transcription)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let confidence = outputs.reduce(Float(0)) { $0 + $1.confidence } / Float(outputs.count)
        return RecognitionOutput(transcription: transcription, confidence: confidence)
    }

    private func exportChunk(
        asset: AVURLAsset,
        originalURL: URL,
        start: TimeInterval,
        duration: TimeInterval,
        index: Int
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitbinder_transcription_\(UUID().uuidString)_\(index).m4a")

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTranscriptionError.audioExportFailed("Audio export is not available for \(originalURL.lastPathComponent).")
        }

        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )

        do {
            try await exporter.export(to: outputURL, as: .m4a)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioTranscriptionError.audioExportFailed(error.localizedDescription)
        }
    }
    
    /// Get audio file duration
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
    
    /// Generate a title from transcribed text
    static func generateTitle(from transcription: String) -> String {
        let cleaned = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to find first sentence
        let sentenceEnders = CharacterSet(charactersIn: ".!?")
        if let range = cleaned.rangeOfCharacter(from: sentenceEnders) {
            let firstSentence = String(cleaned[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if firstSentence.count >= 5 && firstSentence.count <= 80 {
                return firstSentence
            }
        }
        
        // Fall back to first N words
        let words = cleaned.split(separator: " ").prefix(8)
        let title = words.joined(separator: " ")
        
        if title.count > 60 {
            return String(title.prefix(57)) + "..."
        }
        
        return title.isEmpty ? "Voice Note Import" : title
    }
}
