//
//  ChatMessage.swift
//  thebitbinder
//
//  View-only chat message used by the BitBuddy chat UI.
//
//  Historical note: an `@Model class ChatMessage` previously existed in the
//  SwiftData schema but was never actually written from any UI path
//  (BitBuddyChatView has always used the non-persisted `ChatBubbleMessage`
//  struct below). As part of Phase 4 wave 1, the @Model was removed. The
//  persistent ChatMessage entity now lives in the Core Data + CloudKit
//  schema (`BitBinderEntity.chatMessage`) and is accessed via NSManagedObject.
//

import Foundation

/// Lightweight, non-persisted chat message for the BitBuddy chat UI.
struct ChatBubbleMessage: Identifiable {
    let id: UUID = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date = Date()
    let conversationId: String

    init(text: String, isUser: Bool, conversationId: String = UUID().uuidString) {
        self.text = text
        self.isUser = isUser
        self.conversationId = conversationId
    }
}
