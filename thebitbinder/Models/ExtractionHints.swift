//
//  ExtractionHints.swift
//  thebitbinder
//
//  Structured user-supplied hints that tell GagGrabber how a document is
//  organized *before* extraction runs. Hints drive three things:
//
//    1. Preprocessing — strip content the user wants ignored (stage directions,
//       crowd reactions, timestamps, notes-to-self) before the segmenter sees it.
//    2. An AI prompt prefix — a short natural-language summary that's prepended
//       to the text sent to AI providers.
//    3. (Future) Deterministic split-regex selection in the heuristic path.
//
//  Value type; Codable so we can persist last-used answers per user if we want.
//

import Foundation

struct ExtractionHints: Codable, Equatable {

    // MARK: - Sub-types

    /// How the user says bits are visually separated in the document.
    enum SeparatorStyle: String, Codable, CaseIterable, Identifiable {
        case blankLine          // Paragraph-style; blank line between bits
        case numbered           // "1.", "2)", "Bit 3:"
        case bullets            // "- ", "• ", "* "
        case headers            // Section headers / labels between bits
        case noneOrFlowing      // Stream-of-consciousness, no clear separator
        case mixed              // Unknown or a bit of everything (default)

        var id: String { rawValue }

        var label: String {
            switch self {
            case .blankLine:     return "Blank lines"
            case .numbered:      return "Numbered"
            case .bullets:       return "Bullets"
            case .headers:       return "Headers"
            case .noneOrFlowing: return "Flowing"
            case .mixed:         return "Mixed"
            }
        }

        var sfSymbol: String {
            switch self {
            case .blankLine:     return "text.alignleft"
            case .numbered:      return "list.number"
            case .bullets:       return "list.bullet"
            case .headers:       return "textformat"
            case .noneOrFlowing: return "text.justify"
            case .mixed:         return "questionmark.circle"
            }
        }
    }

    /// Typical length of each bit. Helps calibrate chunk-size priors.
    enum BitLength: String, Codable, CaseIterable, Identifiable {
        case oneLiner           // 1 sentence
        case shortFewSentences  // 2–5 sentences
        case longParagraph      // Paragraph+
        case varies             // No consistent length (default)

        var id: String { rawValue }

        var label: String {
            switch self {
            case .oneLiner:          return "One-liners"
            case .shortFewSentences: return "Short (2–5 sentences)"
            case .longParagraph:     return "Long (paragraph+)"
            case .varies:            return "Varies"
            }
        }
    }

    /// What kind of source document this is. Different kinds need different
    /// processing priorities (layout-first vs embedding-first, etc.).
    enum DocumentKind: String, Codable, CaseIterable, Identifiable {
        case writtenSetList     // Typed / formatted set list
        case notesDump          // Notes app / stream-of-thought
        case transcript         // Transcribed recording
        case messages           // Texts / DMs / chat
        case unknown            // Not sure (default)

        var id: String { rawValue }

        var label: String {
            switch self {
            case .writtenSetList: return "Written set"
            case .notesDump:      return "Notes dump"
            case .transcript:     return "Transcript"
            case .messages:       return "Messages"
            case .unknown:        return "Not sure"
            }
        }

        var sfSymbol: String {
            switch self {
            case .writtenSetList: return "doc.text"
            case .notesDump:      return "note.text"
            case .transcript:     return "mic"
            case .messages:       return "bubble.left.and.bubble.right"
            case .unknown:        return "questionmark.circle"
            }
        }
    }

    /// Toggle set for content the user wants stripped before segmentation.
    struct Ignore: Codable, Equatable {
        var stageDirections: Bool = false   // [brackets]
        var crowdReactions: Bool  = false   // (laughs), (applause)
        var timestamps: Bool      = false   // 00:00, 01:23:45
        var notesToSelf: Bool     = false   // lines starting "note:", "todo:", "fixme:"

        var isAllOff: Bool { !stageDirections && !crowdReactions && !timestamps && !notesToSelf }
    }

    // MARK: - Stored properties

    var separator: SeparatorStyle = .mixed
    var length: BitLength         = .varies
    var kind: DocumentKind        = .unknown
    var ignore: Ignore            = Ignore()

    /// Optional user-supplied example of a section label to treat as a
    /// non-joke title (e.g. `"--- Act 2 ---"`).
    var sectionLabelExample: String = ""

    /// Free-form notes the user wants included verbatim in the AI hint.
    var freeformNotes: String = ""

    // MARK: - Conveniences

    /// All-defaults / "Just figure it out" sentinel.
    static let unspecified = ExtractionHints()

    /// True when the user hasn't changed any defaults. Extraction code can
    /// short-circuit hint-aware paths when this is true.
    var isUnspecified: Bool { self == Self.unspecified }

    // MARK: - Preprocessing

    /// Strips content the user flagged to ignore. Runs on the raw input text
    /// before segmentation. Safe to call even with `isUnspecified` — it's a
    /// no-op when every toggle is off.
    func preprocess(_ text: String) -> String {
        guard !ignore.isAllOff else { return text }

        var out = text

        if ignore.stageDirections {
            // [anything inside square brackets] — cap length to avoid eating
            // paragraphs if the user has real brackets in a joke.
            out = out.replacingOccurrences(
                of: #"\s*\[[^\]]{0,120}\]\s*"#,
                with: " ",
                options: .regularExpression
            )
        }

        if ignore.crowdReactions {
            // Case-insensitive (laughs / applause / cheers / pause / sighs /
            // laughter / groans / crickets / silence / boos) with optional
            // modifiers inside the parens.
            out = out.replacingOccurrences(
                of: #"(?i)\s*\(\s*(laughs?|laughter|applause|applauds?|cheers?|pause|sighs?|groans?|crickets|silence|boos|awkward|beat)[^)]{0,40}\)\s*"#,
                with: " ",
                options: .regularExpression
            )
        }

        if ignore.timestamps {
            // HH:MM:SS or MM:SS at line starts or inline, optionally bracketed.
            out = out.replacingOccurrences(
                of: #"\s*\[?\(?\s*\d{1,2}:\d{2}(?::\d{2})?\s*\)?\]?\s*"#,
                with: " ",
                options: .regularExpression
            )
        }

        if ignore.notesToSelf {
            // Whole-line notes beginning with note / todo / fixme / reminder.
            out = out.replacingOccurrences(
                of: #"(?im)^\s*(?:note|todo|fixme|reminder)\s*[:\-–—].*$"#,
                with: "",
                options: .regularExpression
            )
        }

        // Collapse runs of blank lines we may have introduced.
        out = out.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI prompt prefix

    /// Returns a short, natural-language summary of the user's hints, suitable
    /// for prepending to text sent to an AI provider. Returns `nil` when no
    /// hints are set so callers can skip the prefix entirely.
    func aiPromptPrefix() -> String? {
        guard !isUnspecified else { return nil }

        var lines: [String] = ["[EXTRACTION HINTS FROM USER]"]

        if separator != .mixed {
            lines.append("- Separator style: \(separatorDescription)")
        }
        if length != .varies {
            lines.append("- Typical bit length: \(length.label.lowercased())")
        }
        if kind != .unknown {
            lines.append("- Document kind: \(kindDescription)")
        }

        let ignoreList = ignoreDescriptions
        if !ignoreList.isEmpty {
            lines.append("- Already removed from the text: \(ignoreList.joined(separator: ", "))")
        }

        let trimmedExample = sectionLabelExample.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExample.isEmpty {
            lines.append("- Treat lines like this as section titles, not jokes: \"\(trimmedExample)\"")
        }

        let trimmedNotes = freeformNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            lines.append("- Additional notes: \(trimmedNotes)")
        }

        // If the only thing non-default was ignore toggles and they were all
        // off after trimming, we still returned nil above via isUnspecified.
        guard lines.count > 1 else { return nil }

        lines.append("[END HINTS]")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private description helpers

    private var separatorDescription: String {
        switch separator {
        case .blankLine:     return "bits are separated by blank lines"
        case .numbered:      return "bits are numbered (1., 2., 3.)"
        case .bullets:       return "bits start with a bullet (- or •)"
        case .headers:       return "bits are divided by section headers"
        case .noneOrFlowing: return "no clear separator; stream of consciousness"
        case .mixed:         return "mixed / unknown"
        }
    }

    private var kindDescription: String {
        switch kind {
        case .writtenSetList: return "written / typed set list"
        case .notesDump:      return "dump from a notes app"
        case .transcript:     return "transcript of a recording"
        case .messages:       return "texts or DMs"
        case .unknown:        return "unknown"
        }
    }

    private var ignoreDescriptions: [String] {
        var out: [String] = []
        if ignore.stageDirections { out.append("[stage directions]") }
        if ignore.crowdReactions  { out.append("(crowd reactions)") }
        if ignore.timestamps      { out.append("timestamps") }
        if ignore.notesToSelf     { out.append("notes-to-self lines") }
        return out
    }

    // MARK: - Combine for an AI-bound request

    /// Returns `rawText` with the hint prefix prepended when hints exist,
    /// otherwise returns `rawText` unchanged. Callers that run preprocessing
    /// separately should call `preprocess` first and then this.
    func applyingPromptPrefix(to rawText: String) -> String {
        guard let prefix = aiPromptPrefix() else { return rawText }
        return "\(prefix)\n\n\(rawText)"
    }
}
