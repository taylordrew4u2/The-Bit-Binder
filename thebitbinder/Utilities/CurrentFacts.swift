//
//  CurrentFacts.swift
//  thebitbinder
//
//  Device-derived answers for facts that should never come from model memory.
//

import Foundation

enum CurrentFacts {
    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    static func answer(for message: String) -> String? {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,:;!?()[]{}"))

        let now = Date()
        let year = Calendar.current.component(.year, from: now)

        if normalized == "what year is it"
            || normalized == "what year is this"
            || normalized == "what year are we in"
            || normalized == "what is the year"
            || normalized == "what's the year"
            || normalized == "whats the year"
            || normalized == "current year"
            || normalized == "what year it is" {
            return "\(year)."
        }

        if normalized == "what date is it"
            || normalized == "what is the date"
            || normalized == "what's the date"
            || normalized == "whats the date"
            || normalized == "what is today's date"
            || normalized == "what's today's date"
            || normalized == "whats todays date"
            || normalized == "today's date"
            || normalized == "todays date" {
            return fullDateFormatter.string(from: now) + "."
        }

        if normalized == "what day is it"
            || normalized == "what day is today"
            || normalized == "what's today"
            || normalized == "whats today" {
            return fullDateFormatter.string(from: now) + "."
        }

        return nil
    }

    static var currentDateString: String {
        fullDateFormatter.string(from: Date())
    }
}
