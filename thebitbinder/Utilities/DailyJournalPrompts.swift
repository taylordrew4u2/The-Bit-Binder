//
//  DailyJournalPrompts.swift
//  thebitbinder
//
//  Default end-of-day prompt questions for the Daily Journal.
//  Stable IDs so saved answers survive prompt copy-edits.
//

import Foundation

enum DailyJournalPrompts {
    struct Prompt: Identifiable, Hashable {
        let id: String
        let question: String
    }

    static let all: [Prompt] = [
        Prompt(id: "laughed",       question: "What made me laugh today?"),
        Prompt(id: "annoyed",       question: "What annoyed me today?"),
        Prompt(id: "ideas",         question: "Did I think of any joke ideas, tags, premises, or act-outs?"),
        Prompt(id: "stageWorthy",   question: "What happened today that might be useful on stage later?"),
        Prompt(id: "feltGood",      question: "What felt good in my comedy or creativity today?"),
        Prompt(id: "feltOff",       question: "What felt off or blocked today?"),
        Prompt(id: "performed",     question: "Did I perform tonight? If yes, what worked?"),
        Prompt(id: "bombed",        question: "Did anything bomb or feel weak?"),
        Prompt(id: "tomorrow",      question: "What do I want to remember tomorrow?"),
    ]
}
