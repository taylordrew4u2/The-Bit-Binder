//
//  BitBuddyChatView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import SwiftUI
import SwiftData

/// Chat view hosted inside BitBuddyDrawer — slides in from the right edge so
/// you can chat alongside whatever you're working on.
struct BitBuddyChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissBitBuddyDrawer) private var dismissDrawer
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var userPreferences: UserPreferences
    @Query(sort: \Joke.dateCreated, order: .reverse) private var jokes: [Joke]
    @StateObject private var bitBuddy = BitBuddyService.shared
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var messages: [ChatBubbleMessage] = []
    @State private var inputText = ""
    @State private var conversationId = UUID().uuidString
    @State private var isTyping = false
    @State private var typingMessageId: UUID?
    @State private var displayedText = ""
    /// Tracks the active send + typewriter Task so it can be cancelled
    /// when the user sends a new message, resets the conversation, or
    /// dismisses the sheet. Without this, concurrent typewriter Tasks
    /// both write to `displayedText` and produce garbled output.
    @State private var activeResponseTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool
    
    
    private var accentColor: Color {
        roastMode ? FirePalette.core : .accentColor
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
                            TypingIndicator(roastMode: roastMode, statusMessage: bitBuddy.statusMessage)
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
        .background(roastMode ? Color(FirePalette.bg) : Color(UIColor.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    // Dismiss keyboard first to avoid stale input session errors
                    isInputFocused = false
                    // Brief delay lets keyboard frame animation complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismissDrawer()
                        dismiss()
                    }
                }
                .foregroundColor(accentColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeResponseTask?.cancel()
                    activeResponseTask = nil
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
            isInputFocused = false
            activeResponseTask?.cancel()
            activeResponseTask = nil
            typingMessageId = nil
            displayedText = ""
            isTyping = false
            messages.removeAll()
            bitBuddy.cleanupAudioResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyAddJoke)) { notification in
            guard let jokeText = notification.userInfo?["jokeText"] as? String,
                  !jokeText.isEmpty else { return }
            let folderName = notification.userInfo?["folder"] as? String
            let newJoke = Joke(content: jokeText)
            // If a folder was specified, try to find or create it
            if let folderName = folderName, !folderName.isEmpty {
                let existingFolders = (try? modelContext.fetch(FetchDescriptor<JokeFolder>())) ?? []
                if let folder = existingFolders.first(where: { $0.name.lowercased() == folderName.lowercased() && !$0.isTrashed }) {
                    newJoke.folder = folder
                } else {
                    let folder = JokeFolder(name: folderName)
                    modelContext.insert(folder)
                    newJoke.folder = folder
                }
            }
            modelContext.insert(newJoke)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Joke saved via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save joke: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyAddBrainstormNote)) { notification in
            guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else { return }
            let idea = BrainstormIdea(content: text, colorHex: BrainstormIdea.randomColor())
            modelContext.insert(idea)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Brainstorm idea saved via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save brainstorm idea: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyCreateSetList)) { notification in
            guard let name = notification.userInfo?["name"] as? String, !name.isEmpty else { return }
            let setList = SetList(name: name)
            modelContext.insert(setList)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Set list '\(name)' created via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to create set list: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyCreateFolder)) { notification in
            guard let name = notification.userInfo?["name"] as? String, !name.isEmpty else { return }
            // Check for duplicate folder names before creating
            let existingFolders = (try? modelContext.fetch(FetchDescriptor<JokeFolder>())) ?? []
            if existingFolders.contains(where: { $0.name.lowercased() == name.lowercased() && !$0.isTrashed }) {
                print(" [BitBuddy→SwiftData] Folder '\(name)' already exists — skipping create")
                return
            }
            let folder = JokeFolder(name: name)
            modelContext.insert(folder)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Folder '\(name)' created via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to create folder: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyCreateRoastTarget)) { notification in
            guard let name = notification.userInfo?["name"] as? String, !name.isEmpty else { return }
            let notes = notification.userInfo?["notes"] as? String ?? ""
            let target = RoastTarget(name: name, notes: notes)
            modelContext.insert(target)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Roast target '\(name)' created via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to create roast target: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyAddRoastJoke)) { notification in
            guard let jokeText = notification.userInfo?["joke"] as? String, !jokeText.isEmpty else { return }
            let targetName = notification.userInfo?["target"] as? String
            let roastJoke = RoastJoke(content: jokeText)
            // If a target was named, find it and attach
            if let targetName = targetName, !targetName.isEmpty {
                let allTargets = (try? modelContext.fetch(FetchDescriptor<RoastTarget>())) ?? []
                if let target = allTargets.first(where: { $0.name.lowercased() == targetName.lowercased() && !$0.isTrashed }) {
                    roastJoke.target = target
                }
            }
            modelContext.insert(roastJoke)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Roast joke saved via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save roast joke: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddySaveNotebookText)) { notification in
            guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else { return }
            let record = NotebookPhotoRecord(notes: text, imageData: nil)
            modelContext.insert(record)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Notebook text saved via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save notebook text: \(error)")
            }
        }
        .onChange(of: bitBuddy.pendingNavigation) { _, section in
            guard let section else { return }
            guard let appScreen = appScreen(for: section) else { return }
            bitBuddy.clearPendingNavigation()
            // Dismiss keyboard first to prevent stale input sessions
            isInputFocused = false
            // Post navigation then dismiss the sheet so the user lands
            // on the target screen.
            NotificationCenter.default.post(
                name: .navigateToScreen,
                object: nil,
                userInfo: ["screen": appScreen.rawValue]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                Text(roastMode ? "Roast Buddy" : "Hey, \(userPreferences.userName)!")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Text(roastMode
                     ? "Sharp. Merciless. Affectionate. Give me a target."
                     : "I can help with your jokes, set lists, brainstorms, recordings, imports, and more.")
                    .font(.subheadline)
                    .foregroundColor(roastMode ? FirePalette.sub : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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
                    suggestionChip("What makes a good punchline?")
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
                .foregroundColor(roastMode ? FirePalette.text : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 280, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(roastMode ? Color.white.opacity(0.05) : Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            roastMode ? FirePalette.edge : Color.accentColor.opacity(0.15),
                            lineWidth: roastMode ? 0.5 : 1
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
                    TextField(roastMode ? "Sharpen this bit…" : "Ask BitBuddy...", text: $inputText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(roastMode ? Color.white.opacity(0.05) : Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(roastMode ? FirePalette.core.opacity(0.3) : Color.clear, lineWidth: 1)
                )

                // Send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty || bitBuddy.isLoading
                                ? (roastMode ? Color.white.opacity(0.08) : Color(UIColor.systemGray5))
                                : accentColor
                            )
                            .frame(width: 44, height: 44)

                        if bitBuddy.isLoading {
                            ProgressView()
                                .tint(roastMode ? FirePalette.text : .primary)
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
            .background(roastMode ? Color(FirePalette.bg2) : Color(UIColor.systemBackground))
        }
    }
    
    private func handleAppear() {
        // Greet the user on every fresh conversation
        if messages.isEmpty {
            let greeting = roastMode
                ? "Roast Buddy here. Give me a target and I'll sharpen the burns."
                : "Hey! I'm BitBuddy, your comedy writing partner. Ask me to analyze a joke, build a set list, brainstorm premises, or anything else — I'm ready when you are."
            let intro = ChatBubbleMessage(text: greeting, isUser: false, conversationId: conversationId)
            messages.append(intro)
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
        
        // Cancel any in-flight typewriter animation from a previous response.
        // Without this, two Tasks write to `displayedText` simultaneously and
        // the user sees garbled text.
        activeResponseTask?.cancel()
        activeResponseTask = nil
        // If a previous message was mid-typewriter, reveal its full text now
        typingMessageId = nil
        
        let userMessage = ChatBubbleMessage(text: message, isUser: true, conversationId: conversationId)
        messages.append(userMessage)
        inputText = ""
        isTyping = true
        
        activeResponseTask = Task {
            do {
                let response = try await bitBuddy.sendMessage(message)
                
                // Bail out if the Task was cancelled while waiting for the response
                guard !Task.isCancelled else { return }
                
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
                    // Check cancellation before each word so we stop quickly
                    // when the user sends a new message or dismisses the sheet.
                    guard !Task.isCancelled else {
                        return
                    }
                    try? await Task.sleep(nanoseconds: 15_000_000) // 15ms per word
                    // Re-check after sleep — cancellation may have fired while
                    // we were waiting. Without this second guard a cancelled
                    // task writes one stale word into displayedText, which
                    // contaminates the *next* response's typewriter output
                    // and produces garbled text with missing or wrong letters.
                    guard !Task.isCancelled else {
                        return
                    }
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
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isTyping = false
                    let errorMsg = ChatBubbleMessage(text: "Sorry, I encountered an error. Please try again.", isUser: false, conversationId: conversationId)
                    messages.append(errorMsg)
                }
            }
        }
    }
    
    /// Appends a BitBuddy error message to the chat.
    private func appendErrorMessage(_ text: String) {
        let msg = ChatBubbleMessage(text: text, isUser: false, conversationId: conversationId)
        messages.append(msg)
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
                    ? (roastMode ? AnyShapeStyle(FirePalette.emberCTA) : AnyShapeStyle(Color.accentColor))
                    : (roastMode ? AnyShapeStyle(Color.white.opacity(0.05)) : AnyShapeStyle(Color(UIColor.secondarySystemBackground)))
                )
                .foregroundColor(
                    message.isUser
                    ? .white
                    : (roastMode ? FirePalette.text : .primary)
                )
                .overlay(
                    !message.isUser && roastMode
                    ? RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                    : nil
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
    var statusMessage: String = ""
    @State private var dotOffset: [CGFloat] = [0, 0, 0]
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                            .offset(y: dotOffset[index])
                    }
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                roastMode ? Color.white.opacity(0.05) : Color(UIColor.secondarySystemBackground)
            )
            .cornerRadius(16)
            .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
            .overlay(
                roastMode
                ? RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(FirePalette.edge, lineWidth: 0.5)
                : nil
            )
            .animation(.easeInOut(duration: 0.3), value: statusMessage)
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

    var body: some View {
        if roastMode {
            RoastBuddyAvatar(size: size)
        } else {
            ZStack {
                Image("BitBuddyIcon")
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            }
            .frame(width: size, height: size)
        }
    }
}

/// Roast Buddy — BitBuddy's alter-ego. Charred background, ember glow,
/// speech-bubble glyph with sparkle eyes and a crooked smirk.
struct RoastBuddyAvatar: View {
    var size: CGFloat = 40
    var color: Color = FirePalette.bright

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.23, green: 0.094, blue: 0.063),
                            Color(red: 0.102, green: 0.051, blue: 0.031)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(FirePalette.core.opacity(0.27), lineWidth: 0.5)

            // Ember glow in top-right
            Circle()
                .fill(RadialGradient(
                    colors: [FirePalette.core.opacity(0.5), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.35
                ))
                .frame(width: size * 0.55, height: size * 0.55)
                .blur(radius: size * 0.08)
                .offset(x: size * 0.15, y: -size * 0.15)

            // Roast Buddy glyph — speech bubble + sparkle eyes + smirk + ember
            RoastBuddyGlyph(size: size * 0.56, color: color)
        }
        .frame(width: size, height: size)
        .shadow(color: FirePalette.core.opacity(0.2), radius: 8, y: 2)
    }
}

/// SVG-equivalent glyph for Roast Buddy: speech bubble head, sparkle eyes, smirk, ember top.
struct RoastBuddyGlyph: View {
    var size: CGFloat = 22
    var color: Color = FirePalette.bright

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let scale = s / 1024.0

            // Speech bubble
            var bubble = Path()
            bubble.move(to: CGPoint(x: 200 * scale, y: 320 * scale))
            bubble.addQuadCurve(
                to: CGPoint(x: 280 * scale, y: 240 * scale),
                control: CGPoint(x: 200 * scale, y: 240 * scale)
            )
            bubble.addLine(to: CGPoint(x: 744 * scale, y: 240 * scale))
            bubble.addQuadCurve(
                to: CGPoint(x: 824 * scale, y: 320 * scale),
                control: CGPoint(x: 824 * scale, y: 240 * scale)
            )
            bubble.addLine(to: CGPoint(x: 824 * scale, y: 664 * scale))
            bubble.addQuadCurve(
                to: CGPoint(x: 744 * scale, y: 744 * scale),
                control: CGPoint(x: 824 * scale, y: 744 * scale)
            )
            bubble.addLine(to: CGPoint(x: 568 * scale, y: 744 * scale))
            bubble.addLine(to: CGPoint(x: 460 * scale, y: 852 * scale))
            bubble.addLine(to: CGPoint(x: 460 * scale, y: 744 * scale))
            bubble.addLine(to: CGPoint(x: 280 * scale, y: 744 * scale))
            bubble.addQuadCurve(
                to: CGPoint(x: 200 * scale, y: 664 * scale),
                control: CGPoint(x: 200 * scale, y: 744 * scale)
            )
            bubble.closeSubpath()

            context.stroke(bubble, with: .color(color), style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, lineJoin: .round))

            // Sparkle eyes (4-point stars)
            drawSparkle(in: &context, center: CGPoint(x: 420 * scale, y: 478 * scale), size: 36 * scale, color: color)
            drawSparkle(in: &context, center: CGPoint(x: 636 * scale, y: 478 * scale), size: 36 * scale, color: color)

            // Crooked smirk
            var smirk = Path()
            smirk.move(to: CGPoint(x: 450 * scale, y: 620 * scale))
            smirk.addQuadCurve(
                to: CGPoint(x: 560 * scale, y: 630 * scale),
                control: CGPoint(x: 500 * scale, y: 660 * scale)
            )
            context.stroke(smirk, with: .color(color), style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round))

            // Ember flame on top
            var flame = Path()
            flame.move(to: CGPoint(x: 512 * scale, y: 240 * scale))
            flame.addCurve(
                to: CGPoint(x: 504 * scale, y: 144 * scale),
                control1: CGPoint(x: 520 * scale, y: 192 * scale),
                control2: CGPoint(x: 496 * scale, y: 176 * scale)
            )
            flame.addCurve(
                to: CGPoint(x: 536 * scale, y: 232 * scale),
                control1: CGPoint(x: 540 * scale, y: 168 * scale),
                control2: CGPoint(x: 548 * scale, y: 200 * scale)
            )
            context.stroke(flame, with: .color(color), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round))

            // Ember dot
            let dotRect = CGRect(x: 516 * scale, y: 118 * scale, width: 14 * scale, height: 14 * scale)
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
        .frame(width: size, height: size)
    }

    private func drawSparkle(in context: inout GraphicsContext, center: CGPoint, size: CGFloat, color: Color) {
        var path = Path()
        let r = size / 2
        let inner = r * 0.35
        for i in 0..<4 {
            let outerAngle = Angle.degrees(Double(i) * 90 - 90)
            let innerAngle = Angle.degrees(Double(i) * 90 - 45)
            let ox = center.x + cos(outerAngle.radians) * r
            let oy = center.y + sin(outerAngle.radians) * r
            let ix = center.x + cos(innerAngle.radians) * inner
            let iy = center.y + sin(innerAngle.radians) * inner
            if i == 0 { path.move(to: CGPoint(x: ox, y: oy)) }
            else { path.addLine(to: CGPoint(x: ox, y: oy)) }
            path.addLine(to: CGPoint(x: ix, y: iy))
        }
        path.closeSubpath()
        context.fill(path, with: .color(color))
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


#Preview {
    NavigationStack {
        BitBuddyChatView()
            .environmentObject(UserPreferences())
    }
}
