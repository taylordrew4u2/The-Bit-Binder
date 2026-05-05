import Foundation

/// BitBuddy's local rule-based engine — the ONLY backend for chat.
/// AI services are reserved exclusively for the GagGrabber joke-extraction pipeline.
/// Powered by the 93-intent router for structured command handling across 11 app sections.
final class LocalFallbackBitBuddyService: BitBuddyBackend {
    static let shared = LocalFallbackBitBuddyService()
    
    private init() {}
    
    var backendName: String { "Local Fallback" }
    var isAvailable: Bool { true }
    var supportsStreaming: Bool { false }
    
    // MARK: - Mutable State (accessed only on main actor via singleton pattern)
    // SAFETY: userProfile is mutated only from send() which is called exclusively
    // by BitBuddyService (a @MainActor singleton). BitBuddyService serializes
    // access via its isLoading guard. Do NOT call send() from a non-main-actor context.
    nonisolated(unsafe) private var userProfile: UserStyleProfile = .empty()
    private let intentRouter = BitBuddyIntentRouter.shared
    
    /// Intent IDs that actually need the user's joke profile data.
    /// BitBuddy will only load and reference saved jokes when one of these is triggered.
    private static let profileDependentIntents: Set<String> = [
        "summarize_style", "suggest_unexplored_topics", "rewrite_in_my_style",
        "find_similar_jokes", "generate_premise", "generate_joke"
    ]
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        // Only refresh the joke profile when the intent actually needs it.
        // This prevents BitBuddy from proactively referencing saved jokes
        // in casual conversation — jokes are only used when the user asks.
        let intentId = dataContext.routedIntent?.intent.id
        if let intentId, Self.profileDependentIntents.contains(intentId) {
            updateProfile(from: dataContext.recentJokes)
        }
        
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use the intent router first
        if let route = dataContext.routedIntent ?? intentRouter.route(trimmed) {
            return handleRoutedIntent(route, message: trimmed, dataContext: dataContext)
        }
        
        // Legacy prefix matching for backwards compat
        let lower = trimmed.lowercased()
        
        if lower.starts(with: "analyze") {
            let content = dataContext.focusedJoke?.content ?? extractContent(from: trimmed, prefix: "analyze")
            return analyze(content)
        }
        if lower.starts(with: "improve") {
            let content = dataContext.focusedJoke?.content ?? extractContent(from: trimmed, prefix: "improve")
            return improve(content)
        }
        if lower.starts(with: "premise") {
            let content = extractContent(from: trimmed, prefix: "premise")
            return premise(content)
        }
        if lower.starts(with: "generate") {
            let content = extractContent(from: trimmed, prefix: "generate")
            return generate(content)
        }
        if lower.starts(with: "style") {
            return style()
        }
        if lower.starts(with: "suggest_topic") || lower.contains("suggest topic") {
            return suggestTopic()
        }
        
        // Friendly fallback with section-aware help
        return buildHelpResponse(for: dataContext)
    }
    
    // MARK: - Intent-Routed Dispatch
    
    private func handleRoutedIntent(_ route: BitBuddyRouteResult, message: String, dataContext: BitBuddyDataContext) -> String {
        let response = dispatchIntent(route, message: message, dataContext: dataContext)
        if dataContext.isRoastMode {
            return applyRoastVoice(response, intentId: route.intent.id)
        }
        return response
    }

    private func applyRoastVoice(_ response: String, intentId: String) -> String {
        let alreadyRoasty: Set<String> = [
            "roast_line_generation", "toggle_roast_mode", "create_roast_target",
            "add_roast_joke", "search_roasts", "create_roast_set",
            "present_roast_set", "attach_photo_to_target",
            "analyze_joke", "improve_joke", "generate_premise", "generate_joke",
            "shorten_joke", "expand_joke", "crowdwork_help",
            "explain_comedy_theory", "rewrite_in_my_style",
        ]
        if alreadyRoasty.contains(intentId) { return response }

        let prefixes = ["Sharp.", "Done.", "Handled.", "On it.", "Locked in."]
        let prefix = prefixes.randomElement()!
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix) \(cleaned)"
    }

    private func dispatchIntent(_ route: BitBuddyRouteResult, message: String, dataContext: BitBuddyDataContext) -> String {
        let intent = route.intent
        let entities = route.extractedEntities
        let userName = dataContext.userName

        switch intent.id {

        // ═══════════════════════════════════════════
        // JOKES
        // ═══════════════════════════════════════════
        case "save_joke":
            return " Got it, \(userName)! I'll save that joke to your collection. Head to Jokes to see it."
        case "save_joke_in_folder":
            let folder = entities["folder"] ?? "your folder"
            return " Saved! I've filed this joke under \(folder). You can find it in the Jokes section."
        case "edit_joke":
            return " Opening the joke editor — make your changes and I'll keep the original safe in case you want to revert."
        case "rename_joke":
            let title = entities["title"] ?? entities["quoted_value"] ?? "the new title"
            return " Renamed! This joke is now called \"\(title)\". You can find it under the new name in Jokes."
        case "delete_joke":
            return " Joke moved to trash. You can restore it anytime from the Trash section if you change your mind."
        case "restore_deleted_joke":
            return " Restored! That joke is back in your collection right where it belongs."
        case "mark_hit":
            return " Marked as a Hit! This joke is now in your proven material. You've earned that star."
        case "unmark_hit":
            return "Removed from The Hits. The joke is still saved — it just lost its star status."
        case "add_tags":
            let tags = entities["value"] ?? entities["quoted_value"] ?? "tags"
            return " Tags added! Labeled with \(tags). Use tags to filter your jokes later."
        case "remove_tags":
            return " Tags removed. This joke is now untagged — a blank canvas."
        case "move_joke_folder":
            let folder = entities["folder"] ?? "the new folder"
            return " Moved! This joke is now filed under \(folder)."
        case "create_folder":
            let folder = entities["value"] ?? entities["quoted_value"] ?? "New Folder"
            return " Folder \"\(folder)\" created! Start adding jokes to it."
        case "rename_folder":
            return " Folder renamed! The new name is live across all your jokes."
        case "delete_folder":
            return " Folder deleted. Any jokes inside have been moved to unfiled."
        case "search_jokes":
            let query = entities["value"] ?? "your search"
            return " Searching your jokes for \"\(query)\"... Head to the Jokes tab to see results."
        case "filter_jokes_recent":
            return " Here's what you've been working on recently. Check the Jokes tab for your latest material."
        case "filter_jokes_by_folder":
            let folder = entities["folder"] ?? "that folder"
            return " Filtering by \(folder). Switch to the Jokes tab to see everything in that folder."
        case "filter_jokes_by_tag":
            return " Filtering by tag. Open Jokes to see the matching material."
        case "list_hits":
            return " Opening The Hits — your proven material that lands every time. Head to Jokes and filter by Hits to see them."
        case "share_joke":
            return " Joke ready to share! I'll open the share sheet so you can send it however you like."
        case "duplicate_joke":
            return " Duplicated! You now have a fresh copy to experiment with without risking the original."
        case "merge_jokes":
            return " I'll pull these versions together. Check the merged result in Jokes and see if the combined version hits harder."
            
        // ═══════════════════════════════════════════
        // BRAINSTORM
        // ═══════════════════════════════════════════
        case "add_brainstorm_note":
            return " Idea captured! It's pinned to your Brainstorm board as a sticky note. Come back to it whenever inspiration strikes."
        case "voice_capture_idea":
            return " Voice capture ready! Tap the mic button on the Brainstorm page to start speaking your idea."
        case "edit_brainstorm_note":
            return " Opening that brainstorm note for editing. Polish it up!"
        case "delete_brainstorm_note":
            return " Brainstorm note deleted. Sometimes clearing the board makes room for the next big idea."
        case "promote_idea_to_joke":
            return " Promoted! That brainstorm idea is now a full joke in your collection. Time to start writing the setup and punchline."
        case "search_brainstorm":
            let query = entities["value"] ?? "that topic"
            return " Searching your brainstorm notes for \"\(query)\"... Head to the Brainstorm tab."
        case "group_brainstorm_topics":
            return " Grouping your brainstorm notes by topic... Head to Brainstorm to see which ideas cluster together. You might find a whole chunk hiding in there."
            
        // ═══════════════════════════════════════════
        // SET LISTS
        // ═══════════════════════════════════════════
        case "create_set_list":
            let name = entities["set_name"] ?? entities["quoted_value"] ?? "New Set"
            return " Set list \"\(name)\" created! Start adding jokes to build your lineup."
        case "rename_set_list":
            return " Set list renamed! The new title is live."
        case "delete_set_list":
            return " Set list deleted. Those jokes are still saved individually — just the list is gone."
        case "add_joke_to_set":
            return " Joke added to the set list! Drag to reorder if you want it in a different slot."
        case "remove_joke_from_set":
            return " Removed from the set list. The joke is still in your collection."
        case "reorder_set":
            return " Set reordered! Your lineup is updated. Remember: strong opener, build in the middle, killer closer."
        case "estimate_set_time":
            return " Rule of thumb: most comics average about 1–2 minutes per joke on stage. A tight 5-minute set is usually 3–5 jokes, a 10-minute set is 5–8. Open your set list to see the exact joke count and do the math!"
        case "shuffle_set":
            return " Set shuffled! Sometimes a random order reveals pairings you'd never have thought of. Try reading it through."
        case "suggest_set_opener":
            return " For an opener, pick something accessible — a relatable observation or a quick-hit joke that doesn't need context. Your most crowd-friendly material goes first."
        case "suggest_set_closer":
            return " Close with your strongest material — the joke with the biggest reaction. Callbacks work great as closers too. Leave them wanting more."
        case "present_set":
            return " Entering performance mode! Your set list is ready to go — swipe through joke by joke on stage."
        case "find_set_list":
            return " Searching your set lists... Head to the Set Lists tab to see the match."
            
        // ═══════════════════════════════════════════
        // RECORDINGS
        // ═══════════════════════════════════════════
        case "start_recording":
            return " Recording started! I'll capture everything. Tap stop when you're done."
        case "stop_recording":
            return " Recording saved! You can play it back, transcribe it, or attach it to a set list."
        case "rename_recording":
            return " Recording renamed! Give it a title that'll jog your memory about the set."
        case "delete_recording":
            return " Recording deleted. Audio files take up space, so good call if it wasn't a keeper."
        case "play_recording":
            return " Playing back your recording. Listen for the laughs — and the silences."
        case "transcribe_recording":
            return " Transcription started! This will convert your set audio into searchable text. Check back in Recordings when it's done."
        case "search_transcripts":
            let query = entities["value"] ?? "that word"
            return " Searching transcripts for \"\(query)\"... I'll pull up every set where you mentioned it."
        case "clip_recording":
            return " Clip tool ready! Select the start and end points in the Recordings tab to extract just the good part."
        case "attach_recording_to_set":
            return " Recording attached to the set list! Now you can compare what you wrote to what you actually said on stage."
        case "review_set_from_recording":
            return " Reviewing your set recording... I'll look for strong moments, improv additions, and spots where the energy dipped."
            
        // ═══════════════════════════════════════════
        // BITBUDDY
        // ═══════════════════════════════════════════
        case "analyze_joke":
            let jokeText = dataContext.focusedJoke?.content ?? extractContent(from: message, prefix: "analyze")
            return analyze(jokeText.isEmpty ? message : jokeText)
        case "improve_joke":
            let jokeText = dataContext.focusedJoke?.content ?? extractContent(from: message, prefix: "improve")
            return improve(jokeText.isEmpty ? message : jokeText)
        case "generate_premise":
            let content = extractContent(from: message, prefix: "premise")
            return premise(content)
        case "generate_joke":
            let content = extractContent(from: message, prefix: "generate")
            return generate(content)
        case "summarize_style":
            return style()
        case "suggest_unexplored_topics":
            return suggestTopic()
        case "find_similar_jokes":
            return " Scanning your joke book for similar material... Check Jokes for any overlap or repeated angles."
        case "shorten_joke":
            let fillerList = BitBuddyResources.fillerWords.prefix(6).joined(separator: ", ")
            return """
             **Tightening Mode**
            • Cut the setup to the absolute minimum context needed.
            • Kill these filler words: \(fillerList).
            • End on the funniest word — don't explain after the punchline.
            • If the audience can infer it, don't say it.
            • Pro tip: The best jokes feel effortless but are surgically precise.
            """
        case "expand_joke":
            let technique = BitBuddyResources.jokeProTechniques.randomElement() ?? "Callback"
            return """
             **Expansion Mode**
            • Add a second beat — what happens next?
            • Tag it: find 2–3 additional angles on the same premise.
            • Build a callback you can use later in the set.
            • Add an act-out or voice to make it physical.
            • Try the **\(technique)** technique to find a new gear.
            """
        case "generate_tags_for_joke":
            let content = message
            let tags = inferTagsFromContent(content)
            return " Suggested tags: \(tags.isEmpty ? "observational, personal" : tags.joined(separator: ", ")). These help you filter and find similar material later."
        case "rewrite_in_my_style":
            let profileInfo = userProfile.summary.isEmpty ? "I don't have enough of your jokes yet to match your style" : "Based on your style (\(userProfile.summary))"
            return " \(profileInfo) — try rewriting with your most-used structure and keep the word count around \(Int(userProfile.avgWordCount)) words."
        case "crowdwork_help":
            let nycFlavor = BitBuddyResources.vocabNYCFlavored.randomElement() ?? "subway-speed"
            return """
             **Crowdwork — Master Guide**
            • "Where are you guys from?" → Riff on the city/neighborhood. NYC? Go \(nycFlavor).
            • "What do you do for work?" → Find the absurd angle. Exaggerate to \(BitBuddyResources.vocabExaggeration.randomElement() ?? "apocalyptic") proportions.
            • "How long have you two been together?" → The answer is always comedy gold.
            • "Who dragged who here tonight?" → Sets up a power dynamic to play with.
            Keep it light and curious — never punching down at someone who didn't sign up for it. Channel your inner Chappelle (story) or Carlin (observational).
            """
        case "roast_line_generation":
            let intensity: String
            let lower = message.lowercased()
            if lower.contains("savage") || lower.contains("brutal") || lower.contains("destroy") {
                intensity = "savage"
            } else if lower.contains("light") || lower.contains("gentle") || lower.contains("soft") {
                intensity = "light"
            } else {
                intensity = "medium"
            }
            let example = BitBuddyResources.randomRoastExample(intensity: intensity)
                ?? BitBuddyResources.randomRoastExample() ?? ""
            let technique = BitBuddyResources.roastTechniques.randomElement() ?? "Callback"
            let desc = BitBuddyResources.roastIntensityDescriptions[intensity] ?? "Medium"
            return """
            Here's a \(desc.lowercased()) burn to get you started:

            \(example)

            That one uses **\(technique)**. Want more, or should I dial it up? Say "savage" or "light" to change the heat.
            """
        case "compare_versions":
            let adj = BitBuddyResources.vocabPunchyAdjectives.randomElement() ?? "razor-sharp"
            return """
             **Version Compare**
            • Read both out loud — which one flows better?
            • Which setup is shorter? Shorter usually wins.
            • Which punchline has a harder consonant at the end? (K, T, P sounds hit harder.)
            • Which version could stand alone without context?
            • Which feels more \(adj)?
            • Pro tip: The best jokes feel effortless but are surgically precise.
            """
        case "extract_premises_from_notes":
            return " Mining your notes for premises... Look for any sentence that starts with an observation or frustration — those are your premises. The formula: [Thing] + [What's weird about it] = premise."
        case "explain_comedy_theory":
            return buildComedyTheoryResponse(from: message)
            
        // ═══════════════════════════════════════════
        // NOTEBOOK
        // ═══════════════════════════════════════════
        case "open_notebook":
            return " The **Notebook** is your scratch pad — anything goes. Quick notes, random thoughts, stage observations.\n\n**Would you like me to take you there?**"
        case "save_notebook_text":
            return " Saved to your Notebook! Quick notes add up — review them weekly for hidden gems."
        case "attach_photo_to_notebook":
            return " Photo attached to your Notebook! Great for saving set lists from the stage, whiteboard ideas, or inspiration."
        case "search_notebook":
            let query = entities["value"] ?? "your search"
            return " Searching Notebook for \"\(query)\"... Head to the Notebook tab to see matches."
            
        // ═══════════════════════════════════════════
        // ROAST MODE
        // ═══════════════════════════════════════════
        case "toggle_roast_mode":
            let isCurrentlyRoast = dataContext.isRoastMode
            return isCurrentlyRoast
                ? "Roast Mode OFF. Back to your regularly scheduled comedy. "
                : " ROAST MODE ACTIVATED. Everything's darker from here. Let's write some burns."
        case "create_roast_target":
            let target = entities["target"] ?? entities["quoted_value"] ?? "your target"
            return " Roast target \"\(target)\" created! Start adding burns and roast material under their profile."
        case "add_roast_joke":
            let target = entities["target"] ?? "the target"
            return " Burn filed under \(target)! The roast arsenal grows."
        case "search_roasts":
            return " Searching your roast material... Head to Roast Mode to see the results."
        case "create_roast_set":
            return " Roast set created! Add your sharpest burns and order them for maximum damage."
        case "present_roast_set":
            return " Roast presentation mode ready! Swipe through your burns on stage. Destroy with precision."
        case "attach_photo_to_target":
            return " Photo attached to the roast target! Now you'll never forget that face."
            
        // ═══════════════════════════════════════════
        // IMPORT
        // ═══════════════════════════════════════════
        case "import_file":
            return """
             **GagGrabber — File Import**
            
            To import jokes from a file, you'll want to use **GagGrabber** — it's the dedicated import tool built right into the app.
            
            **Where to find it:**
            • Go to the **Jokes** tab
            • Tap the **+** button (top right)
            • Choose **"Import Files"** from the menu
            
            GagGrabber supports **PDF**, **text files** (.txt, .md), and **documents** (.doc, .docx, .rtf). It'll extract individual jokes automatically and let you review each one before saving.
            
            **Would you like me to take you to the Jokes page so you can use GagGrabber?** Just say "yes" or "take me there."
            """
        case "import_image":
            return """
             **GagGrabber — Image Import**
            
            For importing from images or scans, you'll want to use **GagGrabber** on the Jokes page.
            
            **Where to find it:**
            • Go to **Jokes** tab → tap **+** (top right)
            • Choose **"Scan from Camera"** or **"Import Photos"**
            
            GagGrabber uses OCR to read the text, then extracts individual jokes for you to review.
            
             **Tips:** Good lighting, flat page, and typed/printed text give the best results.
            
            **Would you like me to take you to the Jokes page?** Just say "yes" or "take me there."
            """
        case "review_import_queue":
            return """
             **Import Review Queue**
            
            After GagGrabber extracts jokes, you'll see a card-by-card review:
            • **Swipe right** or tap  to accept a joke
            • **Swipe left** or tap  to skip it
            • Tap  **Edit** to fix the text before saving
            • Tap  **Idea** to send it to Brainstorm instead
            
            High-confidence jokes are auto-accepted (you'll see a green banner).
            You can still review those by scrolling back through the dots.
            
            When you're done, tap **"Save & Finish"** to add everything to your collection.
            """
        case "approve_imported_joke":
            return " Approved! This joke will be saved to your collection when you tap \"Save & Finish\" at the end of the review."
        case "reject_imported_joke":
            return " Skipped. This extracted joke won't be saved. You can go back to it using the dots at the top if you change your mind."
        case "edit_imported_joke":
            return """
             **Editing an Imported Joke**
            
            Tap the  **Edit** button on the review card to:
            • Fix the title (or add one if GagGrabber didn't detect it)
            • Clean up the joke text — merge broken lines, fix OCR errors
            • The original source text is shown below for reference
            
            When you're happy with it, tap **Done**, then accept the card.
            """
        case "check_import_limit":
            return " GagGrabber extractions are currently **unlimited**! Import as many files as you want. You can check your import history from the Jokes tab → ⋯ menu → **Import History**."
        case "show_import_history":
            return " To see your import history: Jokes tab → tap the **⋯** menu (top left) → **Import History**. You'll see every file you've imported, how many jokes were extracted, and any unresolved fragments."
            
        // ═══════════════════════════════════════════
        // SYNC
        // ═══════════════════════════════════════════
        case "check_sync_status":
            return " Checking iCloud sync status... Head to Settings → iCloud Sync to see the latest details."
        case "sync_now":
            return " Manual sync triggered! Your data is being pushed to iCloud now."
        case "toggle_icloud_sync":
            return " You can toggle iCloud sync in Settings → iCloud Sync. This keeps your jokes, sets, and recordings synced across all your devices."
            
        // ═══════════════════════════════════════════
        // SETTINGS
        // ═══════════════════════════════════════════
        case "export_all_jokes":
            return " Export ready! Head to Settings → Export to download your entire joke collection as a backup."
        case "export_recordings":
            return " Recording export available in Settings. You can back up all your set audio."
        case "clear_cache":
            return " Cache cleared! The app should feel lighter now. No data was lost — just temporary files."
            
        // ═══════════════════════════════════════════
        // HELP
        // ═══════════════════════════════════════════
        case "open_help_faq":
            return " **Help & FAQ** has guides for every feature in the app.\n\n**Would you like me to take you there?**"
        case "explain_feature":
            return buildFeatureExplanation(from: message)
            
        default:
            return buildHelpResponse(for: dataContext)
        }
    }
    
    // MARK: - Feature Explanations
    
    private func buildFeatureExplanation(from message: String) -> String {
        let lower = message.lowercased()
        
        if lower.contains("gaggrabber") || lower.contains("import") {
            return """
             **GagGrabber** is BitBinder's smart import tool.
            • Import jokes from PDFs, text files, or photos.
            • Automatically extracts individual jokes from your documents.
            • Review each one before it's saved to your collection.
            • There's a daily extraction limit that resets every 24 hours.
            """
        }
        if lower.contains("roast") {
            return """
             **Roast Mode** transforms BitBinder into a roast battle prep tool.
            • Create targets with names and photos.
            • Write and organize burns under each target.
            • Build roast set lists for battle night.
            • Present mode shows one burn at a time on stage.
            """
        }
        if lower.contains("hits") || lower.contains("hit") {
            return """
             **The Hits** is your collection of proven material.
            • Mark any joke as a "Hit" when it consistently works on stage.
            • Use The Hits to quickly build strong set lists.
            • It's your highlight reel of tested material.
            """
        }
        if lower.contains("set list") || lower.contains("sets") {
            return """
             **Set Lists** help you plan your stage time.
            • Create named sets for different venues or time slots.
            • Drag to reorder jokes in your lineup.
            • Estimate total runtime.
            • Present mode shows one joke at a time on stage.
            """
        }
        if lower.contains("bitbuddy") || lower.contains("commands") {
            return """
             **BitBuddy** is your comedy writing partner.
            • Analyze jokes for structure and strengths.
            • Get rewrites, premises, and new joke ideas.
            • Ask about joke structure, comedy techniques, and what makes things funny.
            • Summarize your comedy style (when you ask).
            • Find gaps in your material.
            • Available on every screen — tap my icon in the toolbar anytime.
            Just type naturally — I understand \(BitBuddyIntentRouter.shared.allIntents.count) different commands across \(BitBuddySection.allCases.count) app sections.
            """
        }
        if lower.contains("brainstorm") {
            return """
             **Brainstorm** is your sticky note wall for raw ideas.
            • Capture ideas as text or voice.
            • Group by topic to find patterns.
            • Promote ideas to full jokes when ready.
            """
        }
        if lower.contains("icloud") || lower.contains("sync") {
            return """
             **iCloud Sync** keeps your data safe across devices.
            • Toggle sync in Settings.
            • Force a manual sync anytime.
            • All jokes, sets, recordings, and notes stay in sync.
            """
        }
        if lower.contains("recording") {
            return """
             **Recordings** let you capture and review your sets.
            • Record audio of your performances.
            • Transcribe recordings to searchable text.
            • Clip and trim the best moments.
            • Attach recordings to set lists for post-show review.
            """
        }
        if lower.contains("notebook") {
            return """
             **Notebook** is your freeform scratch pad.
            • Quick text capture — no formatting needed.
            • Attach photos for visual inspiration.
            • Search across all your notes.
            """
        }
        
        return "I can explain any feature! Try asking about GagGrabber, Roast Mode, The Hits, Set Lists, Brainstorm, Recordings, Notebook, iCloud Sync, or BitBuddy commands."
    }
    
    // MARK: - Comedy Theory Knowledge
    
    private func buildComedyTheoryResponse(from message: String) -> String {
        let lower = message.lowercased()
        
        // Joke structure
        if lower.contains("structure") || lower.contains("anatomy") || lower.contains("parts of a joke") || lower.contains("how to write") || lower.contains("writing basics") {
            return """
             **Joke Structure — The Building Blocks**
            
            Every joke has the same DNA, no matter the style:
            
            **1. Setup** — Establish a shared reality with the audience. The setup creates an expectation. It should feel natural, like you're just telling a story or making an observation.
            
            **2. Tension / Misdirection** — Build on that expectation. The audience thinks they know where you're going. This is the invisible part — when it's done right, nobody notices it.
            
            **3. Punchline** — Shatter the expectation. The laugh comes from the surprise of landing somewhere unexpected. End on the funniest word — everything after the punch dilutes it.
            
            **The Golden Rule:** Punchline = Shortest distance between setup and surprise. Cut every word that doesn't serve the laugh.
            
            **Common Structures:**
            • **One-liner** — Setup and punch in one sentence. Maximum efficiency.
            • **Setup-Punchline** — Classic two-part structure. Setup builds, punch flips.
            • **Rule of Three** — Two items set the pattern, third breaks it.
            • **Anecdote / Story** — Longer form. Multiple beats and tags. Character + situation + escalation.
            • **Chunk / Bit** — A premise explored from multiple angles with tags building on each other.
            
            Say **techniques** to learn the specific tools, or try **analyze** on one of your jokes to see structure in action.
            """
        }
        
        // What makes things funny
        if lower.contains("what makes") && (lower.contains("funny") || lower.contains("humor") || lower.contains("laugh")) ||
           lower.contains("why do jokes work") || lower.contains("why is") && lower.contains("funny") ||
           lower.contains("theory of comedy") || lower.contains("comedy theory") || lower.contains("incongruity") {
            return """
             **Why Things Are Funny — The Core Theories**
            
            Comedy scholars and working comics agree on a few key mechanisms:
            
            **1. Incongruity** — Something doesn't fit. The brain expects one thing and gets another. That gap = funny. This is the engine behind most jokes. A punchline works because it's logically connected to the setup but emotionally surprising.
            
            **2. Superiority** — We laugh when we feel cleverer or luckier than someone else. Roasts, slapstick, and embarrassment humor run on this. Self-deprecation flips it — you make yourself the target so the audience feels in on it.
            
            **3. Relief / Release** — Tension builds, then the punchline releases it. Taboo topics, dark humor, and awkward situations work this way. The laugh is a pressure valve.
            
            **4. Recognition** — The audience sees themselves in it. Observational humor lives here. The laugh is less surprise and more I thought I was the only one.
            
            **5. Absurdity** — Take something normal and crank it to 11. The humor is in the commitment to the ridiculous premise. Think Mitch Hedberg or Steven Wright.
            
            **The Ways Something Can Be Funny:**
            • Surprise / twist / subversion of expectations
            • Exaggeration to absurd proportions
            • Specificity (precise details are funnier than vague ones)
            • Contrast between what's said and what's meant (irony)
            • Wordplay — double meanings, homophones, unexpected literalism
            • Timing — the pause, the callback, the delayed punch
            • Commitment — the more seriously you sell a ridiculous premise, the funnier it gets
            • Status play — high-status person in low-status situation (or vice versa)
            
            Want me to break down a specific technique? Just name it.
            """
        }
        
        // Specific techniques
        if lower.contains("misdirection") || lower.contains("surprise") || lower.contains("subversion") || lower.contains("twist") {
            return """
             **Misdirection / Subversion of Expectations**
            
            This is the #1 comedy tool. Here's how it works:
            
            Your setup leads the audience down one mental path. The punchline yanks them onto a completely different one. The bigger the gap between where they expected to land and where you took them, the bigger the laugh.
            
            **How to build it:**
            • Write the obvious ending first — then throw it away
            • Find a second meaning in a word or phrase from your setup
            • Use the audience's assumptions against them
            • The setup should feel 100% sincere — never tip the twist
            
            **Example pattern:**
            Setup: I told my doctor I broke my arm in two places.
            Expected: Medical advice
            Actual: He told me to stop going to those places.
            
            The punchline reinterprets places from body locations to physical locations. Same word, different meaning = surprise.
            """
        }
        
        if lower.contains("callback") {
            return """
             **Callbacks**
            
            A callback references something from earlier in your set. The audience remembers the original context, so the callback gets a laugh from recognition + surprise combined.
            
            **Why they work:**
            • The audience feels smart for catching the reference
            • It makes your set feel intentional and connected
            • Each callback gets a bigger laugh than the last because the audience anticipates the pattern
            
            **How to use them:**
            • Plant a strong, memorable image or phrase early in your set
            • Wait at least 2-3 jokes before calling back
            • The callback should add a new twist, not just repeat the original joke
            • Great closers often call back to the opener — it wraps the set in a bow
            
            Callbacks are the mark of a pro. If you're building a set list, look for opportunities to connect unrelated bits.
            """
        }
        
        if lower.contains("rule of three") {
            return """
             **Rule of Three**
            
            Two items set the pattern. The third breaks it.
            
            The brain loves patterns — it takes exactly two examples to establish an expectation. The third slot is where you put the surprise.
            
            **Pattern:**
            Normal, Normal, Absurd
            
            **Example:**
            I need three things to be happy: food, shelter, and the WiFi password.
            
            **Advanced version — Reverse Rule of Three:**
            Absurd, Absurd, Normal — the normal one becomes the punchline because the audience expected another escalation.
            
            **Pro tip:** The third item should be the most specific and visual. Vague = mild chuckle. Specific = real laugh.
            """
        }
        
        if lower.contains("timing") || lower.contains("pause") || lower.contains("delivery") {
            return """
             **Timing & Delivery**
            
            Timing is the invisible craft. The words are the joke; the timing is the weapon.
            
            **Key principles:**
            • **The pause before the punch** — Give the audience a beat to lean in. They should almost feel the punch coming, then BAM.
            • **The pause after the punch** — Let the laugh breathe. Don't step on your own laugh by rushing to the next line.
            • **Speed changes** — Fast setup, slow punch. Or slow build, rapid-fire punch. The contrast amplifies impact.
            • **The throw-away** — Deliver a devastating punchline casually, like it's nothing. Deadpan power.
            
            **On paper vs on stage:**
            Written jokes can use line breaks and formatting for timing. On stage, you control timing with your voice, pace, and body. A joke that reads flat on paper can destroy live with the right delivery.
            
            **The golden rule of timing:** If you're not sure whether to pause, pause. Silence is the most powerful comedy tool nobody uses enough.
            """
        }
        
        if lower.contains("self deprecat") || lower.contains("self-deprecat") {
            return """
             **Self-Deprecation**
            
            Making yourself the target is one of the most powerful comedy moves. It builds trust, disarms the audience, and gives you permission to go darker later.
            
            **Why it works:**
            • The audience roots for someone who doesn't take themselves too seriously
            • It establishes you as the underdog — and everyone loves an underdog
            • You can't be heckled with something you already said about yourself
            
            **How to do it well:**
            • Be specific — I'm bad at dating is weak. My last date asked if I was lost is strong.
            • Don't wallow — self-deprecation should be confident, not sad
            • Use it early to build rapport, then pivot to other targets
            • The best self-deprecation has a hidden brag (I'm so bad at saving money I accidentally bought a boat)
            """
        }
        
        if lower.contains("wordplay") || lower.contains("pun") {
            return """
             **Wordplay & Puns**
            
            Wordplay is comedy at the language level. The laugh comes from a word meaning two things at once, or sounding like another word.
            
            **Types of wordplay:**
            • **Double meaning** — A word has two valid interpretations in context
            • **Homophone** — Words that sound alike but mean different things
            • **Malapropism** — Intentionally using the wrong word for comic effect
            • **Literalism** — Taking a figurative expression literally
            • **Portmanteau** — Blending two words into a new one
            
            **Pro tip:** The best puns don't announce themselves. If the audience groans, you tipped it too early. If they laugh, the double meaning hit them by surprise.
            
            **The hierarchy:** Unintentional-sounding wordplay > clever wordplay > obvious pun. The less the audience sees it coming, the harder it hits.
            """
        }
        
        if lower.contains("tag") && (lower.contains("line") || lower.contains("topper")) {
            return """
             **Tag Lines / Toppers**
            
            A tag is an additional punchline that builds on the same setup. It extends the laugh without needing a new premise.
            
            **How they work:**
            • After the initial punchline lands, add another angle on the same idea
            • Each tag should escalate — funnier than the last
            • Tags turn a single joke into a full bit
            
            **Structure:**
            Setup → Punch → Tag 1 → Tag 2 → Tag 3 (callback)
            
            **Pro tip:** Write your tags AFTER the core joke works. Don't dilute a strong punchline with weak tags. 2 great tags beat 5 mediocre ones.
            
            **The best tags** either escalate the absurdity or flip the perspective. Think of each tag as a new punchline that rides the wave of the first laugh.
            """
        }
        
        if lower.contains("observational") || lower.contains("observation") {
            return """
             **Observational Humor**
            
            Observational comedy points out what everyone notices but nobody says. The laugh comes from recognition — the audience thinks, that's so true.
            
            **The formula:**
            [Universal experience] + [The thing nobody talks about] + [Your unique take]
            
            **How to find observations:**
            • Pay attention to daily frustrations — lines, traffic, apps, interactions
            • Notice the gap between how things should work and how they actually work
            • Ask yourself: what is everyone pretending is normal that is actually insane?
            
            **What separates good from great:**
            • Good: Points out something relatable
            • Great: Points out something relatable AND reveals why it's absurd
            • Elite: Makes the audience see something they experience daily in a way they never considered
            
            **The key:** Specificity. Don't just say airports are weird. Say specifically WHAT is weird about them and WHY.
            """
        }
        
        if lower.contains("irony") || lower.contains("sarcasm") {
            return """
             **Irony vs Sarcasm**
            
            These get confused constantly. Here's the difference:
            
            **Irony** — The gap between expectation and reality. Things don't turn out the way they should. Irony can exist without anyone saying a word — it's situational.
            Example: A fire station burns down.
            
            **Sarcasm** — Saying the opposite of what you mean, with tone doing the heavy lifting. Sarcasm is verbal. It requires delivery.
            Example: Oh great, another meeting that could have been an email.
            
            **Dramatic irony** — The audience knows something the subject doesn't. This is gold for storytelling bits.
            
            **How to use irony in jokes:**
            • Set up a sincere expectation, then reveal the ironic outcome
            • Let the audience figure out the irony themselves — don't explain it
            • Pair irony with deadpan delivery for maximum impact
            """
        }
        
        if lower.contains("act out") || lower.contains("actout") || lower.contains("physical") {
            return """
             **Act-Outs / Physical Comedy**
            
            An act-out is when you physicalize the joke — you become the character, mimic the action, or use your body to sell the bit. This is where written material becomes performance.
            
            **Why act-outs kill:**
            • They add a visual dimension the audience didn't expect
            • They make you memorable — people remember what they see AND hear
            • They extend laughs — the audience reacts to the words, then the physical, double hit
            
            **Types:**
            • **Character voice** — Become someone else mid-joke
            • **Mime / gesture** — Physicalize an action instead of describing it
            • **Facial reaction** — Your face reacts to your own joke (deadpan, shock, resignation)
            • **Exaggerated movement** — Amplify a normal action for absurdity
            
            **On paper:** Write [act out] in brackets where you'd physically perform. It reminds you where the visual beats are when you practice.
            """
        }
        
        if lower.contains("exaggerat") || lower.contains("hyperbole") {
            return """
             **Exaggeration / Hyperbole**
            
            Take something real and blow it up to absurd proportions. The humor lives in the gap between reality and the exaggerated version.
            
            **How to calibrate:**
            • 2x exaggeration = not funny (too close to reality)
            • 10x exaggeration = mildly funny
            • 100x exaggeration = comedy (so absurd it's obviously not literal)
            
            **The key:** Start from a truthful observation. The exaggeration only works if the seed is recognizable. My rent is high → weak. My rent is high enough that my landlord has a money room like Scrooge McDuck → strong.
            
            **Combine with specificity:** Don't just say it took forever. Say it took so long my phone died, charged, and died again. Specific exaggeration beats vague exaggeration every time.
            """
        }
        
        if lower.contains("anti joke") || lower.contains("anti-joke") || lower.contains("deadpan") {
            return """
             **Anti-Jokes & Deadpan**
            
            An anti-joke sets up the expectation of a joke, then delivers something mundane, literal, or depressingly real instead. The humor comes from the absence of a traditional punchline.
            
            **Example:**
            A horse walks into a bar. Several people leave, recognizing the potential danger of the situation.
            
            **Why it works:** The audience's brain is primed for a punchline. When it doesn't come, the subverted expectation itself becomes the joke.
            
            **Deadpan:** Delivering absurd material with zero emotion. The contrast between what you're saying and how you're saying it creates tension that the audience releases as laughter.
            
            **Masters to study:** Norm Macdonald, Steven Wright, Mitch Hedberg, Demetri Martin.
            
            **Pro tip:** Anti-humor works best when the audience trusts you're funny. Open with proven material, then hit them with the anti-joke once they're on your side.
            """
        }
        
        // Catch-all for general "techniques" or "types" questions
        if lower.contains("technique") || lower.contains("types of") || lower.contains("kinds of") ||
           lower.contains("ways") && lower.contains("funny") || lower.contains("comedy tools") {
            let techniques = BitBuddyResources.jokeProTechniques
            return """
             **Comedy Techniques — The Full Toolkit**
            
            Here's every major tool in the joke writer's arsenal:
            
            \(techniques.enumerated().map { "**\($0.offset + 1). \($0.element)**" }.joined(separator: "\n"))
            
            **The 5 Engines of Funny:**
            • **Surprise** — They didn't see it coming
            • **Recognition** — They've lived it but never said it
            • **Exaggeration** — It's true, but cranked to 11
            • **Wordplay** — Language doing double duty
            • **Tension & Release** — Build discomfort, then pop it
            
            Ask about any specific technique and I'll break it down with examples and how to use it in your material.
            """
        }
        
        // Punchline specifically
        if lower.contains("punchline") || lower.contains("punch line") {
            return """
             **Punchlines — The Art of the Landing**
            
            The punchline is the destination. Everything else is the journey to get there.
            
            **Rules of punchline writing:**
            • **End on the funny word.** Rearrange the sentence if you have to. The last word the audience hears should be the one that triggers the laugh.
            • **Shorter is almost always better.** If you can cut a word and keep the meaning, cut it.
            • **Hard consonants hit harder.** Words ending in K, T, P, and B sound punchier than soft endings. Truck is funnier than vehicle.
            • **Don't explain after the punch.** The moment you say because or I mean after the punchline, you're stepping on your own laugh.
            • **Surprise is everything.** If the audience can predict your punchline, rewrite it.
            
            **Testing your punchline:**
            • Cover the punchline and read just the setup. Is the expected ending obvious? If yes, your punch needs to go further.
            • Read the punchline out loud. Does it feel like a landing or a continuation? Punchlines should feel final.
            """
        }
        
        // Setup specifically
        if lower.contains("setup") && !lower.contains("set up a") {
            return """
             **Setups — Laying the Foundation**
            
            The setup is the invisible half of the joke. When it's done right, the audience doesn't even know they're being set up.
            
            **A great setup does 3 things:**
            1. Establishes the world of the joke (who, what, where)
            2. Creates an expectation the punchline will shatter
            3. Contains only the information needed for the punch to land
            
            **Common setup mistakes:**
            • Too long — By the time the punch hits, they've forgotten the setup
            • Too obvious — The audience can see the punchline from a mile away
            • Missing context — The punch doesn't land because the setup didn't establish enough
            
            **Pro tip:** Write the punchline first, then write the minimum setup needed to make it work. Most setups are 2x longer than they need to be.
            """
        }
        
        // General/default comedy knowledge
        return """
         **Comedy Knowledge Base**
        
        I know joke structure inside and out. Ask me about any of these:
        
        **Structure:** joke anatomy, setup, punchline, tags, bits, chunks
        **Techniques:** misdirection, callbacks, rule of three, irony, wordplay, act-outs, exaggeration, anti-jokes, deadpan
        **Theory:** what makes things funny, incongruity, surprise, recognition, tension & release
        **Craft:** timing, delivery, self-deprecation, observational humor
        
        Try asking something like:
        • What makes a good punchline?
        • How do callbacks work?
        • What are the different ways something can be funny?
        • Explain the rule of three
        
        I'm your comedy encyclopedia — just ask.
        """
    }
    
    // MARK: - Help Response Builder
    
    private func buildHelpResponse(for dataContext: BitBuddyDataContext) -> String {
        let userName = dataContext.userName
        let roast = dataContext.isRoastMode

        if let page = dataContext.currentPage {
            return pageAwareHelpResponse(userName: userName, page: page, roastMode: roast)
        }

        if roast {
            return """
            Didn't catch that, \(userName) — but I'm still dangerous. I can do everything the normal me does, just meaner.

            **Burns**: "roast my friend Mike", "write 5 burns about bad drivers"
            **Jokes**: "analyze this joke", "punch this up", "generate a premise about ___"
            **Sets**: "build a 10-minute set", "reorder my lineup"
            **Everything else**: tags, folders, recordings, imports — same as always

            What do you need?
            """
        }

        return """
        Hey \(userName)! I didn't quite catch that. Here's what I can do:

         **Jokes**: save, edit, tag, search, share, organize into folders
         **Brainstorm**: capture ideas, voice notes, promote to jokes
         **Set Lists**: create, reorder, shuffle, estimate time, present
         **Recordings**: record, play, transcribe, clip, attach to sets
         **Writing Help**: analyze, improve, punch up, generate premises, crowdwork
         **Comedy Knowledge**: joke structure, techniques, what makes things funny
         **Notebook**: save notes, attach photos, search
         **Roast Mode**: targets, burns, roast sets, battle prep
         **Import**: PDF/image import, review queue
         **Sync**: iCloud status, manual sync, toggle
         **Settings**: export, clear cache
         **Help**: explain any feature

        Try something like: "analyze this joke" or "what makes a good punchline"
        """
    }

    private func pageAwareHelpResponse(userName: String, page: BitBuddySection, roastMode: Bool) -> String {
        if roastMode {
            return roastPageAwareHelpResponse(userName: userName, page: page)
        }
        switch page {
        case .jokes:
            return """
            You're on **Jokes**, \(userName). I can:
            • Filter or search your library — try "show me hits" or "find jokes about my dad"
            • Move jokes between folders or sets — "move this to my Monday set"
            • Punch up a joke if you tap one open and ask "improve this"
            • Tag, untag, or favorite — "tag this as crowdwork"
            What do you want to do here?
            """
        case .brainstorm:
            return """
            You're in **Brainstorm**, \(userName). Best moves here:
            • "Save this idea: …" — I'll capture it
            • Ask "give me a premise about commuting" or "suggest a topic"
            • Promote any idea to a polished joke — "turn this into a joke"
            What's rattling around?
            """
        case .setLists:
            return """
            You're on **Set Lists**, \(userName). I can:
            • Create a new set — "make a 10-minute set about dating"
            • Reorder, shuffle, or estimate runtime
            • Add jokes — "add my hits to this set"
            Which set are you working on?
            """
        case .recordings:
            return """
            You're in **Recordings**, \(userName). Try:
            • "Start a new recording" or "transcribe this"
            • Clip a moment — "make a clip from 1:20 to 2:05"
            • Attach a recording to a set
            What needs capturing?
            """
        case .notebook:
            return """
            You're in the **Notebook**, \(userName). I can:
            • Save a quick note — "save this thought: …"
            • Pull up older notes — "find notes about Vegas"
            • Attach photos to a note
            What's on your mind?
            """
        case .roastMode:
            return """
            You're in **Roast Mode**, \(userName). I can:
            • Add a target — "add my brother as a target"
            • Build burns — "give me 5 jokes about his car"
            • Pull together a roast set
            Who's on the chopping block?
            """
        case .importFlow:
            return """
            You're in **Import**, \(userName). I can:
            • Review what's in the queue — "show me what's pending"
            • Approve or reject jokes
            • Pull text from PDFs and photos
            Want me to walk through the pending items?
            """
        case .sync:
            return """
            You're in **Sync**, \(userName). I can:
            • Check iCloud status — "am I synced?"
            • Trigger a manual sync
            • Explain why something didn't sync
            What's going on?
            """
        case .settings:
            return """
            You're in **Settings**, \(userName). I can help with:
            • Exporting your library
            • Clearing the cache
            • Toggling appearance, sync, or roast mode
            What are you trying to change?
            """
        case .help:
            return """
            You're in **Help**, \(userName). Ask me anything about a feature — "how do tags work?", "what is The Hits?", "how do I import a PDF?"
            """
        case .bitbuddy:
            return """
            We're already chatting, \(userName) — what do you want to work on? Try "punch up this joke" or "give me a premise about ___".
            """
        }
    }

    private func roastPageAwareHelpResponse(userName: String, page: BitBuddySection) -> String {
        switch page {
        case .jokes:
            return """
            You're in the war room, \(userName). I can sharpen anything here:
            • "Punch this up" or "analyze this joke" — I'll tear it apart and rebuild it
            • "Find jokes about ___" or "show me hits"
            • Tags, folders, favorites — all the usual
            • Or just say "roast ___" and I'll start writing burns
            What are we working on?
            """
        case .brainstorm:
            return """
            Brainstorm's open, \(userName). Even in roast mode I can:
            • Capture ideas — "save this idea: …"
            • Generate premises — "give me a premise about ___"
            • Promote ideas to jokes
            Feed me a topic and I'll make it mean.
            """
        case .setLists:
            return """
            Set Lists, \(userName). I can build a roast set or a regular one:
            • "Build a roast set for Mike's birthday"
            • Reorder, shuffle, estimate runtime
            • "Add my sharpest burns to this set"
            Who's getting destroyed tonight?
            """
        case .recordings:
            return """
            Recordings, \(userName). Same tools, darker intentions:
            • Record, transcribe, clip
            • Attach to a set
            Capture the carnage.
            """
        case .notebook:
            return """
            Notebook's open, \(userName). Save notes, attach photos, search — roast mode doesn't change how the scratch pad works. What do you need?
            """
        case .roastMode:
            return """
            This is home base, \(userName). Give me a target and tell me how savage.
            • "Add a target" — name someone
            • "Write burns about ___"
            • "Build a roast set"
            Let's cook.
            """
        case .importFlow:
            return """
            Import, \(userName). I can pull jokes from PDFs, images, or files — even in roast mode. Want me to check the queue?
            """
        case .sync:
            return """
            Sync, \(userName). iCloud status, manual sync, diagnostics — same as always. What's the issue?
            """
        case .settings:
            return """
            Settings, \(userName). Export, cache, appearance, sync toggles — I handle it all. What needs changing?
            """
        case .help:
            return """
            Help, \(userName). Ask me anything — "how do tags work?", "what is The Hits?", "how do I import?" Roast mode doesn't limit what I know.
            """
        case .bitbuddy:
            return """
            We're talking, \(userName). I can do everything — jokes, sets, brainstorm, burns, analysis. Just tell me what you need.
            """
        }
    }
    
    // MARK: - Handlers
    
    private func analyze(_ text: String) -> String {
        guard !text.isEmpty else { return "Give me something to look at." }

        let structure = JokeAnalyzer.structure(text)
        let lower = text.lowercased()
        let words = text.split(separator: " ")
        let wordCount = words.count

        let twistPatterns = [
            "\\bbut\\b", "\\bactually\\b", "\\bturns out\\b", "\\bplot twist\\b",
            "\\binstead\\b", "\\bexcept\\b", "\\bunless\\b", "\\buntil\\b",
            "\\blittle did\\b", "\\bnot really\\b", "\\bjust kidding\\b",
            "\\bsurprise\\b", "\\bthe real\\b", "\\bnope\\b"
        ]
        let twistCount = twistPatterns.filter { lower.range(of: $0, options: .regularExpression) != nil }.count

        // Pick the single most useful observation
        if twistCount == 0 {
            return "Reads like a \(structure.rawValue.lowercased()). I'm not seeing a clear twist though — where's the surprise? What does the audience expect, and how can you flip it?"
        }

        if wordCount > 50 {
            return "Reads like a \(structure.rawValue.lowercased()) — \(wordCount) words is a lot of setup. What's the one sentence in here that makes the audience laugh? Start there and build the minimum around it."
        }

        let lastWord = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).last?
            .lowercased().trimmingCharacters(in: .punctuationCharacters) ?? ""
        let weakEndings = ["it", "me", "that", "this", "one", "thing", "stuff", "there", "here"]
        if weakEndings.contains(lastWord) {
            return "Structure's solid — \(structure.rawValue.lowercased()) with a turn. But you're landing on \"\(lastWord)\". Can you rearrange so the funniest word comes last?"
        }

        if wordCount < 15 && twistCount >= 1 {
            return "Tight and it's got a turn. I'd say this is ready to try on stage. Want me to help you write a tag for it?"
        }

        let editSuggestions = JokeAnalyzer.suggestEdits(text)
        if let edit = editSuggestions.first {
            return "\(structure.rawValue) structure, got a twist — that's working. One thing: \(edit)"
        }

        return "\(structure.rawValue) with a turn — the bones are there. Want me to punch it up or help you find a tag?"
    }
    
    private func improve(_ text: String) -> String {
        guard !text.isEmpty else { return "Give me the joke and I'll punch it up." }

        let words = text.split(separator: " ")
        let wordCount = words.count
        let lower = text.lowercased()

        let lastWord = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).last?
            .lowercased().trimmingCharacters(in: .punctuationCharacters) ?? ""
        let weakEndings = ["it", "me", "that", "this", "one", "thing", "stuff", "there", "here"]

        if wordCount > 40 {
            return "OK I see the joke. The setup is \(wordCount) words — that's a lot of runway. What if we trimmed it down? What's the one detail the audience absolutely needs before the punch hits?"
        }

        if weakEndings.contains(lastWord) {
            return "I like where this is going. One thing I notice — you're ending on \"\(lastWord)\". The last word is where the laugh lives. Can you rearrange so the funniest word lands at the end?"
        }

        let foundFillers = BitBuddyResources.fillerWords.filter { lower.contains($0) }
        if foundFillers.count >= 2 {
            let fillerList = foundFillers.prefix(3).map { "\"\($0)\"" }.joined(separator: " and ")
            return "Good bones here. I'd look at \(fillerList) — those are softening the punch. Try reading it without them and see if it hits harder. Want to try that?"
        }

        let editSuggestions = JokeAnalyzer.suggestEdits(text)
        if let edit = editSuggestions.first {
            return "Nice. Here's one thing to try: \(edit)\nWant me to look at the punchline next?"
        }

        return "The wording's clean — I don't see obvious fat to cut. Have you tried it out loud yet? That usually shows you where to tighten. Or I can help write a tag to extend the laugh."
    }
    
    private func premise(_ topic: String) -> String {
        let actualTopic = topic.isEmpty ? (userProfile.topTopics.max(by: { $0.value < $1.value })?.key ?? "dating") : topic

        let observationalAngles = [
            "Nobody talks about how \(actualTopic) is basically just [unexpected comparison] with better marketing.",
            "The worst part about \(actualTopic) isn't what you think — it's that [hidden truth].",
            "We all act like \(actualTopic) is normal, but if aliens saw us doing it they'd [alien reaction].",
            "\(actualTopic.capitalized) is just society's way of saying [uncomfortable truth].",
            "The real reason \(actualTopic) exists is because someone was too [adjective] to [simpler alternative]."
        ]
        let darkAngles = [
            "What if \(actualTopic) is actually a cry for help that we all agreed to call a lifestyle?",
            "\(actualTopic.capitalized) is proof that humans will pay money to make themselves miserable on a schedule.",
            "At some point we decided \(actualTopic) was a good idea and nobody has had the guts to question it since."
        ]
        let absurdAngles = [
            "Imagine explaining \(actualTopic) to someone from 1850. They'd think we were either geniuses or completely unhinged.",
            "What if \(actualTopic) suddenly became illegal? Who panics first?",
            "If \(actualTopic) were a person, it would be the friend who shows up uninvited and doesn't leave."
        ]

        var response = " **Premise Generator: \(actualTopic.capitalized)**\n\n"
        response += "**Observational angle:**\n"
        response += "• \(observationalAngles.randomElement()!)\n\n"
        response += "**Dark/edgy angle:**\n"
        response += "• \(darkAngles.randomElement()!)\n\n"
        response += "**Absurd angle:**\n"
        response += "• \(absurdAngles.randomElement()!)\n\n"

        // Add a "what's funny about this" prompt
        response += "**The question to ask:** What's the gap between how \(actualTopic) is supposed to work and how it actually works? That gap is your joke.\n\n"
        response += "Pick one and say **\"expand this\"** — or give me a different topic."

        return response
    }

    private func generate(_ topic: String) -> String {
        let actualTopic = topic.isEmpty ? (userProfile.topTopics.max(by: { $0.value < $1.value })?.key ?? "work") : topic
        let template = BitBuddyResources.templates.randomElement() ?? "I thought [Topic] was [expectation], but it turns out it's more like [reality]."

        // Build contextual substitution pools
        let relations = ["mom", "dad", "roommate", "ex", "coworker", "therapist", "barista", "dentist"]
        let objects = ["toaster", "smoke alarm", "GPS", "printer", "parking meter", "ikea manual"]
        let activities = ["meal prepping", "meditating", "running", "online dating", "networking", "budgeting"]
        let analogies = ["assembling IKEA furniture blindfolded", "explaining WiFi to my grandma", "defusing a bomb in a sitcom", "parallel parking a bus"]
        let adjectives = ["old", "broke", "tired", "addicted to your phone", "avoiding people", "out of shape"]
        let actions = ["google your symptoms", "set five alarms", "eat cereal for dinner", "rehearse conversations in the shower"]
        let traits = ["chaotic", "expensive", "exhausting", "overhyped"]
        let opposites = ["boring", "free", "relaxing", "underrated"]
        let twists = ["extra steps", "guilt", "a monthly fee", "strangers judging you"]
        let expectations = ["simple", "fun", "relaxing", "straightforward"]
        let realities = ["a trap", "a scam with good branding", "just organized suffering", "anxiety with extra steps"]
        let reasons = ["nobody reads the instructions", "we peaked in 2012", "the universe is petty", "capitalism"]
        let groups = ["adults", "millennials", "morning people", "gym bros", "landlords", "coworkers"]

        // Pick a second topic that's different from the main one
        let otherTopic = BitBuddyResources.topics.filter { $0 != actualTopic }.randomElement() ?? "taxes"

        var joke = template
        joke = joke.replacingOccurrences(of: "[Topic]", with: actualTopic)
        joke = joke.replacingOccurrences(of: "[Topic A]", with: actualTopic)
        joke = joke.replacingOccurrences(of: "[Topic B]", with: otherTopic)
        joke = joke.replacingOccurrences(of: "[Other Topic]", with: otherTopic)
        joke = joke.replacingOccurrences(of: "[Group]", with: groups.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Action]", with: actions.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Reason]", with: reasons.randomElement()!)
        joke = joke.replacingOccurrences(of: "[expectation]", with: expectations.randomElement()!)
        joke = joke.replacingOccurrences(of: "[reality]", with: realities.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Twist]", with: twists.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Adjective]", with: adjectives.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Relation]", with: relations.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Object]", with: objects.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Comparison]", with: analogies.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Activity]", with: activities.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Analogy]", with: analogies.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Trait]", with: traits.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Opposite Trait]", with: opposites.randomElement()!)
        
        let technique = BitBuddyResources.jokeProTechniques.randomElement() ?? "Misdirection"
        let twist = BitBuddyResources.vocabTwistPhrases.randomElement() ?? "except the plot twist is"
        var response = " **Technique: \(technique)**\n\n"
        response += "\(joke)\n\n"
        response += " **Upgrade idea:** Try adding a tag line — \(twist)...\n"
        response += "Say **\"expand this\"** to build it into a full bit, or **\"analyze this\"** for a full breakdown."

        return response
    }

    private func style() -> String {
        return userProfile.summary.isEmpty ? "Not enough data to determine style." : userProfile.summary
    }

    private func suggestTopic() -> String {
        // Pick a topic NOT in top topics
        let usedTopics = Set(userProfile.topTopics.keys)
        // Filter BitBuddyResources.topics
        let newTopics = BitBuddyResources.topics.filter { !usedTopics.contains($0) }
        let suggestion = newTopics.randomElement() ?? "quantum physics"
        
        return "\(suggestion.capitalized) (unused). Try: \"Why is \(suggestion) so hard to explain? Because...\""
    }

    // MARK: - Helpers
    
    private func inferTagsFromContent(_ text: String) -> [String] {
        let lower = text.lowercased()
        let candidatePairs: [(String, String)] = [
            ("dating", "dating"), ("relationship", "relationships"), ("work", "work"),
            ("family", "family"), ("travel", "travel"), ("airport", "travel"),
            ("tech", "tech"), ("phone", "tech"), ("gym", "fitness"),
            ("therapy", "personal"), ("money", "money"), ("food", "food"),
            ("uber", "rideshare"), ("landlord", "housing"), ("subway", "transit"),
            ("tinder", "dating"), ("marriage", "relationships"), ("politics", "politics"),
            ("drunk", "nightlife"), ("doctor", "health"), ("school", "education"),
            ("crowd", "crowdwork"), ("roast", "roast"), ("dark", "dark humor")
        ]
        let tags = candidatePairs.compactMap { lower.contains($0.0) ? $0.1 : nil }
        return Array(Set(tags)).sorted().prefix(5).map { $0 }
    }
    
    private func updateProfile(from summaries: [BitBuddyJokeSummary]) {
        var profile = UserStyleProfile()
        guard !summaries.isEmpty else {
            self.userProfile = profile
            return
        }
        
        var totalWords = 0
        var totalChars = 0
        var topicCounts: [String: Int] = [:]
        var structureCounts: [String: Int] = [:]
        
        for joke in summaries {
            totalWords += joke.content.split(separator: " ").count
            totalChars += joke.content.count
            
            if let topic = JokeAnalyzer.detectTopic(joke.content) {
                topicCounts[topic, default: 0] += 1
            }
            
            let structure = JokeAnalyzer.structure(joke.content)
            structureCounts[structure.rawValue, default: 0] += 1
        }
        
        profile.avgWordCount = Double(totalWords) / Double(summaries.count)
        profile.avgCharCount = Double(totalChars) / Double(summaries.count)
        profile.topTopics = topicCounts
        profile.structureDistribution = structureCounts
        
        self.userProfile = profile
    }
    
    private func extractContent(from message: String, prefix: String) -> String {
        let lower = message.lowercased()
        // Find the prefix within the message (not necessarily at the start)
        // so "can you analyze this joke" correctly extracts "this joke"
        // instead of blindly dropping characters from the front.
        guard let range = lower.range(of: prefix) else {
            // Prefix not found at all — return the whole message trimmed
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var content = String(message[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        if content.starts(with: ":") {
            content = content.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return content
    }
}
