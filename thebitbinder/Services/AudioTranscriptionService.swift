//
//  AudioTranscriptionService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 1/4/26.
//

import Foundation
import Speech
import AVFoundation

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
    
    private let speechRecognizer: SFSpeechRecognizer?
    
    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    /// Check if speech recognition is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
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
        
        // Check if recognizer is available
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
        
        // Get audio duration
        let duration = try? await getAudioDuration(url: url)
        
        // Create recognition request
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
            
            // 60-second hard timeout – SFSpeechRecognizer can hang on some files
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
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeoutWork)
            
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
        
        // Check if we got any text
        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioTranscriptionError.noSpeechDetected
        }
        
        // Calculate average confidence
        let segments = result.bestTranscription.segments
        let avgConfidence: Float = segments.isEmpty ? 0.5 : segments.reduce(0) { $0 + $1.confidence } / Float(segments.count)
        
        return AudioTranscriptionResult(
            transcription: transcription,
            confidence: avgConfidence,
            originalFilename: url.lastPathComponent,
            importDate: Date(),
            duration: duration
        )
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
