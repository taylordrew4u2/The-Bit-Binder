//
//  GeminiJokeExtractor.swift
//  thebitbinder
//
//  Joke extraction powered by GagGrabber (Google Gemini 2.0 Flash).
//

import Foundation
import UIKit
import SwiftUI
import GoogleGenerativeAI

// MARK: - Public Model

struct GeminiExtractedJoke: Codable {
    let jokeText: String
    let humorMechanism: String?
    let confidence: Double
    let explanation: String?
    let title: String?
    let tags: [String]
}

// MARK: - Rate-Limit Error

enum GeminiRateLimitError: LocalizedError {
    case dailyLimitReached(used: Int, limit: Int)
    case apiError(String)
    case noJokesFound
    case keyNotConfigured

    var errorDescription: String? {
        switch self {
        case .dailyLimitReached(let used, let limit):
            return GeminiRateLimitInfo(used: used, limit: limit, remaining: 0, hoursUntilReset: DailyRequestTracker.hoursUntilReset()).limitReachedMessage
        case .apiError(let msg):
            return "GagGrabber error: \(msg)"
        case .noJokesFound:
            return "GagGrabber found no jokes in the provided content."
        case .keyNotConfigured:
            return "GagGrabber is not configured. Add your key to Secrets.plist."
        }
    }
}

// MARK: - Rate-Limit Tracker

struct DailyRequestTracker {
    private static let countKey = "gemini_daily_request_count"
    private static let dateKey = "gemini_last_request_date"
    static let dailyLimit = 1_000

    static func canMakeRequest() -> Bool {
        resetIfNewDay()
        return currentCount() < dailyLimit
    }

    @discardableResult
    static func increment() -> Int {
        resetIfNewDay()
        let newCount = currentCount() + 1
        UserDefaults.standard.set(newCount, forKey: countKey)
        return newCount
    }

    static func currentCount() -> Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: countKey)
    }
    
    static func remaining() -> Int {
        resetIfNewDay()
        return max(0, dailyLimit - UserDefaults.standard.integer(forKey: countKey))
    }
    
    static func hoursUntilReset() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return 24 }
        let seconds = tomorrow.timeIntervalSince(now)
        return max(1, Int(ceil(seconds / 3600)))
    }

    private static func resetIfNewDay() {
        let defaults = UserDefaults.standard
        let todayString = dayString(from: Date())
        let storedString = defaults.string(forKey: dateKey) ?? ""
        if storedString != todayString {
            defaults.set(0, forKey: countKey)
            defaults.set(todayString, forKey: dateKey)
        }
    }

    private static func dayString(from date: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

// MARK: - Rate Limit Info (SF Symbols, no emojis)

struct GeminiRateLimitInfo {
    let used: Int
    let limit: Int
    let remaining: Int
    let hoursUntilReset: Int
    
    static func current() -> GeminiRateLimitInfo {
        return GeminiRateLimitInfo(
            used: DailyRequestTracker.currentCount(),
            limit: DailyRequestTracker.dailyLimit,
            remaining: DailyRequestTracker.remaining(),
            hoursUntilReset: DailyRequestTracker.hoursUntilReset()
        )
    }
    
    // MARK: - SF Symbol Properties
    
    var statusIcon: String {
        if remaining > 900 { return "flame.fill" }
        if remaining > 500 { return "sparkles" }
        if remaining > 100 { return "lightbulb.fill" }
        if remaining > 10  { return "battery.25" }
        if remaining > 0   { return "battery.0" }
        return "moon.zzz.fill"
    }
    
    var statusColor: Color {
        if remaining > 500 { return .green }
        if remaining > 100 { return .blue }
        if remaining > 10  { return .orange }
        if remaining > 0   { return .red }
        return .gray
    }
    
    // MARK: - Text Properties
    
    var shortStatusText: String {
        if remaining > 0 {
            return "\(remaining) grabs left"
        } else {
            return "Resets in \(hoursUntilReset)h"
        }
    }
    
    var remainingMessageText: String {
        if remaining > 900 {
            return "GagGrabber is FULLY caffeinated! \(remaining) joke extractions left today. Go wild!"
        } else if remaining > 500 {
            return "GagGrabber is still sharp! \(remaining) extractions remaining. Keep 'em coming!"
        } else if remaining > 100 {
            return "GagGrabber is getting tired... \(remaining) extractions left. Maybe pace yourself?"
        } else if remaining > 10 {
            return "GagGrabber is running on fumes! Only \(remaining) extractions left today!"
        } else if remaining > 0 {
            return "GagGrabber has \(remaining) brain cells left! Use them wisely!"
        } else {
            return limitReachedMessage
        }
    }
    
    var limitReachedMessage: String {
        let sillyReasons = [
            "GagGrabber ran out of juice! We extracted \(limit) jokes today and now we need a nap.",
            "GagGrabber.exe has stopped responding. Too many jokes processed (\(limit)).",
            "This is GagGrabber. This is GagGrabber after \(limit) joke extractions. Any questions?",
            "RIP GagGrabber (1 day - today). Cause of death: \(limit) joke extractions.",
            "GagGrabber has entered zombie mode after \(limit) extractions. Only wants joooookes now.",
            "GAGGRABBER OVERLOAD! \(limit) jokes was apparently our limit. Who knew?",
            "GagGrabber just blue-screened after \(limit) joke extractions. Classic.",
            "Zzzzz... *snore* ...huh? Oh, GagGrabber did \(limit) extractions and passed out.",
        ]
        
        let refillMessages = [
            "GagGrabber's Adderall prescription refills in ~\(hoursUntilReset) hours. Check back then!",
            "The GagGrabber hamster needs ~\(hoursUntilReset) hours of sleep. Try again tomorrow!",
            "Recharging GagGrabber batteries... ETA: ~\(hoursUntilReset) hours",
            "GagGrabber went to get coffee. Back in ~\(hoursUntilReset) hours",
            "Currently in a food coma. GagGrabber will recover in ~\(hoursUntilReset) hours",
            "GagGrabber is taking a power nap. Wake up call in ~\(hoursUntilReset) hours",
            "Gone fishing for more jokes. Back in ~\(hoursUntilReset) hours",
            "GagGrabber.exe will restart in ~\(hoursUntilReset) hours. Please stand by...",
        ]
        
        let randomReason = sillyReasons.randomElement() ?? sillyReasons[0]
        let randomRefill = refillMessages.randomElement() ?? refillMessages[0]
        
        return "\(randomReason)\n\n\(randomRefill)"
    }
    
    // Legacy compatibility
    var shortStatus: String { shortStatusText }
    var remainingMessage: String { remainingMessageText }
    var statusEmoji: String { statusIcon }
}

// MARK: - API Key Helper

private enum GeminiKeyLoader {
    static func loadKey() -> String? {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict["GEMINI_API_KEY"] as? String,
           !key.isEmpty, key != "YOUR_GEMINI_API_KEY_HERE" {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }
}

// MARK: - Main Extractor

actor GeminiJokeExtractor {
    static let shared = GeminiJokeExtractor()
    private init() {}

    func extract(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = GeminiKeyLoader.loadKey() else {
            throw GeminiRateLimitError.keyNotConfigured
        }
        guard DailyRequestTracker.canMakeRequest() else {
            throw GeminiRateLimitError.dailyLimitReached(
                used: DailyRequestTracker.currentCount(),
                limit: DailyRequestTracker.dailyLimit
            )
        }

        let model = GenerativeModel(name: "gemini-2.0-flash", apiKey: apiKey)
        let prompt = buildTextPrompt(for: text)
        DailyRequestTracker.increment()

        let response = try await model.generateContent(prompt)
        return try parseJokes(from: response)
    }

    func extract(from image: UIImage) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = GeminiKeyLoader.loadKey() else {
            throw GeminiRateLimitError.keyNotConfigured
        }
        guard DailyRequestTracker.canMakeRequest() else {
            throw GeminiRateLimitError.dailyLimitReached(
                used: DailyRequestTracker.currentCount(),
                limit: DailyRequestTracker.dailyLimit
            )
        }

        let model = GenerativeModel(name: "gemini-2.0-flash", apiKey: apiKey)
        let imagePart = ModelContent.Part.jpeg(image.jpegData(compressionQuality: 0.85) ?? Data())
        let textPart = ModelContent.Part.text(imagePrompt)
        DailyRequestTracker.increment()

        let response = try await model.generateContent([ModelContent(parts: [imagePart, textPart])])
        return try parseJokes(from: response)
    }

    nonisolated func todayRequestCount() -> Int { DailyRequestTracker.currentCount() }
    nonisolated func remainingRequests() -> Int { DailyRequestTracker.remaining() }
    nonisolated func rateLimitInfo() -> GeminiRateLimitInfo { GeminiRateLimitInfo.current() }

    // MARK: - Prompts

    private func buildTextPrompt(for text: String) -> String {
        let maxChars = 12_000
        let truncated = text.count > maxChars ? String(text.prefix(maxChars)) + "\n...[truncated]" : text

        return """
        You are a comedy writing assistant. Extract every stand-up joke from the text below.

        CRITICAL: Each joke MUST be a SEPARATE entry. Split on:
        - "NEXT JOKE", "NEW JOKE", "NEW BIT", "---", "***", "===", "//"
        - Numbered items: "1.", "2.", "#1", "Joke 1:"
        - Blank lines, bullet points

        RULES:
        1. When in doubt, SPLIT
        2. One punchline = one entry
        3. Never combine unrelated material

        Return ONLY a valid JSON array:
        [{"jokeText":"<ONE joke>","humorMechanism":"<type or null>","confidence":<0.0-1.0>,"explanation":"<or null>","title":"<or null>","tags":["tag1"]}]

        If no jokes: []

        --- TEXT ---
        \(truncated)
        """
    }

    private var imagePrompt: String {
        """
        Extract every stand-up joke from this image. Split on separators like "NEXT JOKE", "---", numbered items, blank lines.
        RULES: When in doubt, SPLIT. One punchline = one entry.
        Return ONLY JSON array:
        [{"jokeText":"<ONE joke>","humorMechanism":"<or null>","confidence":<0.0-1.0>,"explanation":"<or null>","title":"<or null>","tags":["tag1"]}]
        If no jokes: []
        """
    }

    private func parseJokes(from response: GenerateContentResponse) throws -> [GeminiExtractedJoke] {
        guard let raw = response.text else { return [] }

        var jsonString = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw GeminiRateLimitError.apiError("Response is not valid UTF-8")
        }

        do {
            return try JSONDecoder().decode([GeminiExtractedJoke].self, from: data)
        } catch {
            throw GeminiRateLimitError.apiError("Failed to parse response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Convert to ImportedJoke

extension GeminiExtractedJoke {
    func toImportedJoke(sourceFile: String, pageNumber: Int = 1, orderInFile: Int = 0, importTimestamp: Date = Date()) -> ImportedJoke {
        let importConfidence: ImportConfidence
        switch confidence {
        case 0.8...: importConfidence = .high
        case 0.5...: importConfidence = .medium
        default: importConfidence = .low
        }

        let confidenceFactors = ConfidenceFactors(
            extractionQuality: Float(confidence),
            structuralCleanliness: 0.9,
            titleDetection: title != nil ? 0.9 : 0.3,
            boundaryClarity: 0.95,
            ocrConfidence: 1.0
        )

        let metadata = ImportSourceMetadata(
            fileName: sourceFile,
            pageNumber: pageNumber,
            orderInPage: orderInFile,
            orderInFile: orderInFile,
            boundingBox: nil,
            importTimestamp: importTimestamp
        )

        return ImportedJoke(
            title: title,
            body: jokeText,
            rawSourceText: jokeText,
            tags: tags,
            confidence: importConfidence,
            confidenceFactors: confidenceFactors,
            sourceMetadata: metadata,
            validationResult: .singleJoke,
            extractionMethod: .documentText
        )
    }
}
