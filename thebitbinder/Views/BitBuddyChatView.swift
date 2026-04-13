//
//  BitBuddyChatView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import SwiftUI
import SwiftData
import UIKit

/// Full-screen chat view accessed from the side menu
struct BitBuddyChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var userPreferences: UserPreferences
    @Query(sort: \Joke.dateCreated, order: .reverse) private var jokes: [Joke]
    @StateObject private var bitBuddy = BitBuddyService.shared
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @StateObject private var authService = AuthService.shared
    @State private var messages: [ChatBubbleMessage] = []
    @State private var inputText = ""
    @State private var conversationId = UUID().uuidString
    @State private var isTyping = false
    @State private var typingMessageId: UUID?
    @State private var displayedText = ""
    @State private var pendingActionMessageId: UUID?

    private var accentColor: Color {
        roastMode ? .orange : .accentColor
    }

    @ViewBuilder
    private var bitBuddyAvatar: some View {
        BitBuddyAvatar(roastMode: roastMode, size: 100, symbolSize: 42)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages View
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(messages) { message in
                                ChatBubble(
                                    message: message,
                                    roastMode: roastMode,
                                    typingMessageId: typingMessageId,
                                    displayedText: displayedText
                                )
                                .id(message.id)
                            }
                        }
                        
                        if isTyping {
                            TypingIndicator(roastMode: roastMode)
                                .id("typing-indicator")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isTyping) {
                    if isTyping {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: displayedText) {
                    scrollToBottom(proxy: proxy)
                }
            }
            .frame(maxHeight: .infinity)
            
            // Input Area
            inputArea
        }
        .background(Color(UIColor.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(accentColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    messages.removeAll()
                    conversationId = UUID().uuidString
                    typingMessageId = nil
                    displayedText = ""
                    isTyping = false
                    bitBuddy.startNewConversation()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .foregroundColor(accentColor)
                .disabled(messages.isEmpty)
            }
        }
        .tint(accentColor)
        .onAppear {
            handleAppear()
            Task {
                await bitBuddy.preloadBackend()
            }
            // Provide larger context for local analysis (200 items)
            bitBuddy.registerJokeDataProvider {
                jokes.prefix(200).map {
                    BitBuddyJokeSummary(
                        id: $0.id,
                        title: $0.title,
                        content: $0.content,
                        tags: $0.tags,
                        dateCreated: $0.dateCreated
                    )
                }
            }
        }
        .onDisappear {
            messages.removeAll()
            bitBuddy.cleanupAudioResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyAddJoke)) { notification in
            guard let jokeText = notification.userInfo?["jokeText"] as? String,
                  !jokeText.isEmpty else { return }
            appendStatusMessage("Saving this joke to your library...")
            let newJoke = Joke(content: jokeText)
            modelContext.insert(newJoke)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Joke saved via action dispatch")
                appendStatusMessage("Saved. You can find it in Jokes.")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save joke: \(error)")
                appendStatusMessage("Couldn't save the joke. Please try again.")
            }
        }
        .onChange(of: bitBuddy.pendingNavigation) { _, section in
            guard let section else { return }
            guard let appScreen = appScreen(for: section) else { return }
            let status = "Opening \(section.displayName)..."
            appendStatusMessage(status)
            bitBuddy.clearPendingNavigation()
            // Give the user a beat to read the status before we navigate away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if section == .help {
                    AppDeepLinkStore.setSettingsDestination(.helpFAQ)
                }
                NotificationCenter.default.post(
                    name: .navigateToScreen,
                    object: nil,
                    userInfo: ["screen": appScreen.rawValue]
                )
                dismiss()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                bitBuddyAvatar
            }
            
            VStack(spacing: 8) {
                Text(roastMode ? "Ready to Roast?" : "Hey, \(userPreferences.userName)!")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Text("I can help with your jokes, set lists, brainstorms, recordings, imports, and more — all on-device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Model: \(bitBuddy.backendName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Suggestion chips — one per major section
            VStack(spacing: 8) {
                if roastMode {
                    suggestionChip("Give me roast lines for a finance bro")
                    suggestionChip("Create a roast target")
                    suggestionChip("Build a roast set for battle night")
                    suggestionChip("Shorten this burn")
                } else {
                    suggestionChip("Analyze this joke: I told my therapist I feel invisible. She said 'Next!'")
                    suggestionChip("Create a set list for tonight")
                    suggestionChip("Give me a premise about dating apps")
                    suggestionChip("Show me The Hits")
                    suggestionChip("How do recordings work?")
                }
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 280, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            roastMode ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                // Text field
                HStack {
                    TextField("Ask BitBuddy...", text: $inputText)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(roastMode ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                
                // Send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty || bitBuddy.isLoading
                                ? Color(UIColor.systemGray5)
                                : accentColor
                            )
                            .frame(width: 44, height: 44)
                        
                        if bitBuddy.isLoading {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(
                                    inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? (roastMode ? .white.opacity(0.3) : .gray)
                                    : .white
                                )
                        }
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || bitBuddy.isLoading)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
    }
    
    private func handleAppear() {
        if !authService.isAuthenticated {
            Task {
                try? await authService.signInAnonymously()
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        guard !bitBuddy.isLoading else { return }
        pendingActionMessageId = nil
        
        let userMessage = ChatBubbleMessage(text: message, isUser: true, conversationId: conversationId)
        messages.append(userMessage)
        inputText = ""
        isTyping = true
        
        Task {
            do {
                let response = try await bitBuddy.sendMessage(message)
                await MainActor.run {
                    isTyping = false
                    let aiMessage = ChatBubbleMessage(text: response, isUser: false, conversationId: conversationId)
                    messages.append(aiMessage)
                    typingMessageId = aiMessage.id
                    displayedText = ""
                }
                // Typewriter: reveal word by word
                let words = response.split(separator: " ", omittingEmptySubsequences: false)
                for (index, word) in words.enumerated() {
                    try? await Task.sleep(nanoseconds: 35_000_000) // 35ms per word
                    await MainActor.run {
                        if index == 0 {
                            displayedText = String(word)
                        } else {
                            displayedText += " " + String(word)
                        }
                    }
                }
                await MainActor.run {
                    typingMessageId = nil
                }
            } catch {
                await MainActor.run {
                    isTyping = false
                    let details = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let errorMsg = ChatBubbleMessage(text: "I hit an issue: \(details)", isUser: false, conversationId: conversationId)
                    messages.append(errorMsg)
                }
            }
        }
    }
    
    private func appendStatusMessage(_ text: String) {
        let statusMessage = ChatBubbleMessage(text: text, isUser: false, conversationId: conversationId)
        messages.append(statusMessage)
        pendingActionMessageId = statusMessage.id
    }
    
    // MARK: - Section → AppScreen Mapping
    
    /// Maps a BitBuddySection to the corresponding AppScreen for navigation.
    private func appScreen(for section: BitBuddySection) -> AppScreen? {
        switch section {
        case .jokes, .roastMode:  return .jokes
        case .brainstorm:         return .brainstorm
        case .setLists:           return .sets
        case .recordings:         return .recordings
        case .notebook:           return .notebookSaver
        case .settings, .sync:    return .settings
        case .help:               return .settings   // Help lives under Settings
        case .importFlow:         return .jokes       // Import lands on Jokes
        case .bitbuddy:           return nil           // Stay in chat
        }
    }
}

struct BitBuddyChatView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BitBuddyChatView()
                .environmentObject(UserPreferences())
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatBubbleMessage
    let roastMode: Bool
    var typingMessageId: UUID? = nil
    var displayedText: String = ""
    
    private var isBeingTyped: Bool {
        typingMessageId == message.id
    }
    
    private var visibleText: String {
        if isBeingTyped {
            return displayedText
        }
        return message.text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(visibleText)
                        .font(.body)
                    
                    if isBeingTyped {
                        Text("|")
                            .font(.body.weight(.light))
                            .opacity(0.6)
                            .blinking()
                    }
                }
                .padding(12)
                .background(
                    message.isUser
                    ? (roastMode ? Color.orange : Color.accentColor)
                    : Color(UIColor.secondarySystemBackground)
                )
                .foregroundColor(
                    message.isUser
                    ? .white
                    : .primary
                )
                .cornerRadius(16)
                .cornerRadius(message.isUser ? 16 : 4, corners: message.isUser ? [.topLeft, .bottomLeft, .bottomRight] : [.topRight, .bottomLeft, .bottomRight])
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            } else {
                // User avatar placeholder (optional)
            }
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let roastMode: Bool
    @State private var dotOffset: [CGFloat] = [0, 0, 0]
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .offset(y: dotOffset[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color(UIColor.secondarySystemBackground)
            )
            .cornerRadius(16)
            .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
            .onAppear {
                for i in 0..<3 {
                    withAnimation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15)
                    ) {
                        dotOffset[i] = -5
                    }
                }
            }
            
            Spacer(minLength: 60)
        }
    }
}

struct BitBuddyAvatar: View {
    let roastMode: Bool
    let size: CGFloat
    let symbolSize: CGFloat

    private var tintColor: Color {
        roastMode ? .orange : .accentColor
    }

    private var glyphSize: CGFloat {
        max(size * 0.56, symbolSize * 1.9)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(UIColor.tertiarySystemBackground))

            ClownGlyph()
                .frame(width: glyphSize, height: glyphSize)
                .foregroundStyle(tintColor)
        }
        .overlay(
            Circle()
                .stroke(
                    tintColor.opacity(0.18),
                    lineWidth: 0.8
                )
        )
        .frame(width: size, height: size)
    }
}

private struct ClownGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                // Hair puffs
                Circle().frame(width: w * 0.24, height: w * 0.24).offset(x: -w * 0.34, y: -h * 0.12)
                Circle().frame(width: w * 0.24, height: w * 0.24).offset(x:  w * 0.34, y: -h * 0.12)

                // Face outline
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: w * 0.12, lineCap: .round, lineJoin: .round))
                    .frame(width: w * 0.66, height: h * 0.66)

                // Eyes
                Circle().frame(width: w * 0.1, height: w * 0.1).offset(x: -w * 0.14, y: -h * 0.04)
                Circle().frame(width: w * 0.1, height: w * 0.1).offset(x:  w * 0.14, y: -h * 0.04)

                // Nose
                Circle().frame(width: w * 0.12, height: w * 0.12).offset(y: h * 0.08)

                // Smile
                Path { path in
                    path.addArc(
                        center: CGPoint(x: w * 0.5, y: h * 0.58),
                        radius: w * 0.2,
                        startAngle: .degrees(20),
                        endAngle: .degrees(160),
                        clockwise: false
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: w * 0.11, lineCap: .round, lineJoin: .round))
            }
            .frame(width: w, height: h)
        }
    }
}

// MARK: - Blinking Cursor Modifier

struct BlinkingModifier: ViewModifier {
    @State private var visible = true
    
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

extension View {
    func blinking() -> some View {
        modifier(BlinkingModifier())
    }
}
