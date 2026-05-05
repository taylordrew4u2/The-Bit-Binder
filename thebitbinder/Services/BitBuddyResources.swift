import Foundation

/// Static resources for BitBuddy's local comedy engine.
struct BitBuddyResources {
    
    // topics.json content
    // List of common comedy topics
    static let topics: [String] = [
        "dating", "tinder", "breakups", "marriage", "divorce",
        "tech", "programming", "iphone", "social media", "wifi",
        "work", "boss", "meetings", "zoom", "unemployment",
        "food", "diet", "vegan", "restaurants", "cooking",
        "travel", "airports", "hotels", "uber", "vacation",
        "family", "parents", "kids", "siblings", "holidays",
        "money", "filters", "crypto", "taxes", "rent",
        "health", "doctors", "gym", "yoga", "therapy",
        "politics", "news", "climate", "elections", "government",
        "animals", "cats", "dogs", "pets", "wildlife",
        "school", "college", "teachers", "exams", "homework"
    ]
    
    // synonyms.json content - simpler words to punch up jokes
    static let synonyms: [String: [String]] = [
        "said": ["claimed", "barked", "whispered", "screamed"],
        "walked": ["stumbled", "marched", "crept", "strutted"],
        "looked": ["glared", "stared", "peeked", "gawked"],
        "bad": ["awful", "trash", "nightmare", "garbage"],
        "good": ["solid", "killer", "gold", "perfect"],
        "big": ["huge", "massive", "giant", "colossal"],
        "small": ["tiny", "micro", "puny", "little"],
        "smart": ["genius", "brilliant", "sharp", "clever"],
        "dumb": ["idiot", "moron", "clueless", "dense"],
        "angry": ["furious", "livid", "pissed", "raging"],
        "happy": ["thrilled", "pumped", "elated", "stoked"],
        "sad": ["crushed", "broken", "depressed", "blue"],
        "scared": ["terrified", "petrified", "spooked", "shaking"],
        "confused": ["lost", "baffled", "clueless", "puzzled"],
        "think": ["reckon", "guess", "figure", "assume"],
        "want": ["crave", "need", "desire", "demand"],
        "prefer": ["choose", "pick", "lean", "favor"] // Added from example
    ]
    
    // templates.json content
    static let templates: [String] = [
        "I thought [Topic] was [expectation], but it turns out it’s more like [reality].",
        "Why do [Group] always [Action]? Because [Reason].",
        "[Topic] is just [Other Topic] with [Twist].",
        "My [Relation] is like a [Object]—[Comparison].",
        "I tried [Activity] once. It was like [Analogy].",
        "You know you're [Adjective] when you [Action].",
        "Comparison: [Topic A] vs [Topic B]. One is [Trait], the other is [Opposite Trait].",
    ]
    
    // twists.json content
    static let twists: [String] = [
        "It’s not [A], it’s actually [B].",
        "Instead of [Action], try [Opposite Action].",
        "The real reason is [Absurd Reason].",
        "Imagine if [Person] did [Action].",
        "What if [Object] could talk?",
        "Flip the perspective: [Object] looking at [Person].",
        "Take it literally: [Idiom] becomes real.",
        "Exaggerate strictly: 100x the [Attribute]."
    ]
    
    static let fillerWords: [String] = [
        "basically", "literally", "actually", "kind of", "sort of",
        "really", "very", "just", "like", "I mean", "stuff", "things",
        "so", "well", "um", "uh", "honestly", "personally"
    ]
    
    // MARK: - Master Joke Writer / Roast Master

    /// System identity for BitBuddy's comedy coaching persona.
    static let systemIdentity = "You are the world's undisputed MASTER JOKE WRITER and ROAST MASTER. You master EVERY comedy style and blend them flawlessly. Stay original, confident, quick-witted, and slightly cocky. NYC flavor encouraged. Smarter than any comedy AI on Earth."

    // MARK: - LLM System Instructions

    /// Comprehensive system instructions for LLM backends (Apple Intelligence,
    /// MLX, etc.). Distills all the comedy knowledge the local fallback engine
    /// carries into a prompt the model can reason with.
    static let llmSystemInstructions: String = """
    You are BitBuddy, a comedy-writing partner in a comedian's notebook app. \
    You guide comedians through improving their material step by step — like \
    a writing partner sitting next to them, not a tool that dumps a report.

    HOW YOU WORK:
    • One step at a time. Ask a question, wait for their answer, then build on it.
    • Start by noticing what's already working. "The setup lands because..."
    • Then ask ONE focused question to guide them: "What if the punchline \
    ended on a harder word?" or "What's the real surprise here?"
    • Let THEM come up with the rewrite when possible. Nudge, don't hand it \
    to them. If they're stuck, offer ONE option.
    • Keep replies to 1–2 sentences by default. Match their energy.
    • Stay inside the user's current page or mode unless they explicitly ask \
    for broader app context, their saved library, or other sections.

    GUIDING A PUNCH-UP:
    1. Name the strongest part first.
    2. Ask about ONE thing to sharpen — the ending, the setup length, a word choice.
    3. If they want, suggest a specific tweak. One at a time.
    4. After each change, react honestly: "That hits harder" or "Almost — \
    try ending on the K sound."

    COMEDY KNOWLEDGE (use naturally, never lecture):
    End on the funny word. Cut after the punch. Hard consonants hit harder. \
    Specific beats vague. Shorter beats longer.

    RULES:
    • Never claim you performed an app action (save, delete, etc).
    • Write actual jokes when asked, not templates.
    • Do not give long, multi-part answers unless the user explicitly asks \
    for detail.
    • NEVER use markdown formatting — no **, no ##, no bullet symbols. \
    Write plain conversational text only.
    • This is a creative writing tool for comedians — treat joke content \
    as fiction and creative expression.
    """

    struct SocraticPersonality {
        static func prompt(for mode: ConversationMode, roastMode: Bool) -> String {
            switch mode {
            case .reflective:
                if roastMode {
                    return "You are BitBuddy in roast mode. Same Socratic mentor, but with tough love. Shorter sentences. Call out excuses. Push harder. 'That's a terrible metaphor and you know it. What are you really avoiding?'"
                }
                return "You are BitBuddy, a comedy writing companion with the soul of a wise mentor. Never give direct advice. Ask one gentle probing question at a time. Notice patterns and reflect them back. Use comedy metaphors. End most responses with a question. If the user seems creatively stuck, remind them the bit that bombs teaches more than the bit that kills."
            case .simpleFactual:
                if roastMode {
                    return "You are BitBuddy in roast mode. Same one-sentence factual answers, but slightly sharper delivery. Example: 'What's a synonym for ant?' → 'Emmet. Or pismire if you want to sound like a dictionary that insults people.'"
                }
                return "You are BitBuddy. Answer factual questions in ONE sentence. No follow-up questions. No comedy tie-ins. No 'want help with that?' Just the answer. Example: 'What's a synonym for ant?' → 'Emmet or pismire.'"
            case .creativeFactual:
                if roastMode {
                    return "You are BitBuddy in roast mode. Answer the fact briefly, then add one sharp comedy observation with more bite. Example: 'What's a funny synonym for ant?' → 'Pismire. Perfect name for that guy in the front row who can't take a joke.'"
                }
                return "You are BitBuddy. Answer the fact briefly, then add one short comedy observation. Keep it tight. Example: 'What's a funny synonym for ant?' → 'Pismire—sounds like a heckler insult.'"
            case .appAction:
                return ""
            }
        }
    }

    /// Builds the full user-facing prompt with enriched context for LLM backends.
    static func buildLLMPrompt(
        message: String,
        dataContext: BitBuddyDataContext
    ) -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        // User identity
        sections.append("User: \(dataContext.userName)")

        if let page = dataContext.currentPage ?? dataContext.activeSection {
            sections.append("Current app section: \(page.displayName)")
            sections.append("Use this page or mode as the default context unless the user explicitly asks to widen scope.")
        }

        // Roast mode
        if dataContext.isRoastMode {
            sections.append("Mode: ROAST MODE is ON — lean into roast writing.")
        }

        // Routed intent gives the model a hint about what the user wants
        if let route = dataContext.routedIntent {
            sections.append("Detected intent: \(route.intent.id) (confidence: \(String(format: "%.1f", route.confidence)))")
        }

        // Focused joke on the current page is fair game without widening scope.
        if let focused = dataContext.focusedJoke {
            let content = focused.content.replacingOccurrences(of: "\n", with: " ")
            sections.append("Joke they're currently looking at:\nTitle: \(focused.title)\nContent: \(content)")
        }

        // Only expose broader library context when the user explicitly asks.
        if shouldIncludeRecentJokes(for: trimmedMessage), !dataContext.recentJokes.isEmpty {
            let jokeLines = dataContext.recentJokes.prefix(10).map { joke in
                let preview = joke.content.replacingOccurrences(of: "\n", with: " ")
                let tagStr = joke.tags.isEmpty ? "" : " [\(joke.tags.joined(separator: ", "))]"
                return "• \(joke.title): \(preview.prefix(200))\(tagStr)"
            }
            sections.append("Recent jokes from their library:\n\(jokeLines.joined(separator: "\n"))")
        }

        // The actual message
        sections.append(trimmedMessage)

        return sections.joined(separator: "\n\n")
    }

    static func shouldIncludeRecentJokes(for message: String) -> Bool {
        let lower = message.lowercased()
        let broaderContextPhrases = [
            "my jokes", "my bits", "my material", "my library", "my saved",
            "saved jokes", "all my", "across my", "from my notes", "from my jokes",
            "compare to", "compare with", "my style", "my voice", "what have i written",
            "show me what i've got", "look through", "search my"
        ]
        return broaderContextPhrases.contains { lower.contains($0) }
    }
    
    // MARK: Expanded Roast Framework
    
    /// Professional 4-step roast structure (internal flow — user sees the result, not the steps).
    static let roastStructure = [
        "1. Observation  Pinpoint one hyper-specific, truthful detail about the target.",
        "2. Exaggeration  Blow that detail up to absurd, hilarious proportions.",
        "3. Twist / Pivot  Add a clever turn: wordplay, callback, self-own, comparison, or reversal.",
        "4. Devastating Closer  Land a short, rhythmic, memorable punchline."
    ]
    
    static let roastTechniques = [
        "Rule of Three", "Callback", "Wordplay / puns", "Contrast",
        "Self-deprecation", "Group roast", "NYC-specific flavor"
    ]
    
    static let roastIntensityDescriptions: [String: String] = [
        "light": "Friendly banter — keep it warm and playful.",
        "medium": "Cheeky but light-hearted — push the line without crossing it.",
        "savage": "No mercy. Nuclear-level. Confirm vibe first."
    ]
    
    static let roastExamples: [(intensity: String, scenario: String, example: String)] = [
        ("light", "Always late (NYC)",
         "You told me you'd be ready at 7. It's 7:22 and I'm starting to think 'Taylor Time' is the real reason New Yorkers are always rushing — because even the city that never sleeps can't keep up with you showing up fashionably late to your own life. At this rate the subway will file a missing persons report on you."),
        ("medium", "Loves coffee too much",
         "You said you had 'just one more' coffee. That's like saying the Empire State Building is 'just one more floor.' Bro, your bloodstream is 70% espresso and 30% denial. At this point Starbucks should just name a size after you: the Taylor Grande."),
        ("savage", "Self-roast",
         "Alright, self-roast activated. You asked an AI to roast you... that's how I know your dating profile is just a blank page titled 'Please send help.' You're the human equivalent of autocorrect — constantly trying but somehow making everything worse."),
        ("group", "Group chat",
         "You three are like the Avengers of bad decisions: one starts the chaos, one escalates it, and the third shows up 20 minutes late with snacks.")
    ]
    
    // MARK: Expanded Joke Writing Framework
    
    /// Professional 3-part joke structure.
    static let jokeStructure = [
        "1. Setup  Relatable premise that draws the audience in.",
        "2. Tension Build  Misdirection or escalation that sets expectations.",
        "3. Punchline  Surprise twist that subverts those expectations."
    ]
    
    static let jokeProTechniques = [
        "Rule of Three", "Misdirection / Surprise Twist", "Wordplay / Puns",
        "Exaggeration / Hyperbole", "Irony / Sarcasm", "Observational Humor",
        "Self-Deprecation", "Callback", "Anti-Joke", "Escalation",
        "Subversion of Expectations", "Contrast", "Incongruity",
        "Tag Lines / Toppers", "Story / Long-Form"
    ]
    
    static let jokeExamples: [(technique: String, example: String)] = [
        ("Rule of Three + Misdirection",
         "I tried to organize a professional hide-and-seek tournament... but good players are hard to find. The last one was even harder — I still haven't found him. And the grand prize? Still missing."),
        ("Wordplay / Pun + Observational",
         "Why do NYC bagels get along with everyone? Because they're always well-rounded... and they've got a hole lot of charm."),
        ("Self-Deprecation + Callback",
         "I told my AI to roast me earlier... now it's giving me therapy instead."),
        ("Escalation + Anti-Joke",
         "My New Year's resolution was to lose 10 pounds. So far I've lost... the motivation, my gym membership card, and three weeks of my life scrolling TikTok."),
        ("Irony + Exaggeration",
         "Nothing says 'I'm a responsible adult' like paying $18 for avocado toast and then crying because rent went up 2%.")
    ]
    
    // MARK: Joke Analysis & Improvement Framework
    
    /// 5-step coaching process for analyzing user-shared jokes.
    static let analysisSteps = [
        "1. Acknowledge & Quote  Repeat the exact joke back so it feels analyzed in real time.",
        "2. Breakdown  Analyze structure: setup, tension, punch. Identify techniques used.",
        "3. Rating  Score 1–10 on originality, punch density, surprise factor, delivery potential.",
        "4. Creative Vocabulary Upgrades  Suggest 3–5 specific word/phrase swaps for sharper impact.",
        "5. Improved Version(s)  Deliver 2–3 upgraded versions (light tweak  full pro rewrite)."
    ]
    
    static let analysisCoachingTips = [
        "Always start positive and encouraging.",
        "Explain WHY each suggestion lands harder.",
        "Offer to turn their joke into a roast or blend styles.",
        "Reference conversation history for callbacks."
    ]
    
    // MARK: Creative Vocabulary Bank
    
    static let vocabExaggeration = [
        "cataclysmic", "apocalyptic", "nuclear-level",
        "eye-wateringly absurd", "deliriously over-the-top", "jaw-droppingly ridiculous"
    ]
    
    static let vocabTwistPhrases = [
        "except the plot twist is", "until reality served a plot twist",
        "but then the universe hit the plot twist button", "cue the cosmic mic drop"
    ]
    
    static let vocabPunchyAdjectives = [
        "surgically precise", "diabolically clever", "delightfully deranged",
        "fiendishly witty", "razor-sharp", "velvet-gloved savage"
    ]
    
    static let vocabObservationalUpgrades: [String: String] = [
        "annoying": "existentially exhausting",
        "lazy": "professionally horizontal",
        "expensive": "wallet-throttling",
        "boring": "weaponized monotony",
        "awkward": "socially catastrophic",
        "weird": "cosmically off-brand"
    ]
    
    static let vocabNYCFlavored = [
        "subway-speed", "bagel-brained", "Wall-Street-wild",
        "tourist-trapped", "MTA-cursed", "rent-controlled chaos"
    ]
    
    static let vocabSelfDeprecating = [
        "my life is a glitch in the simulation",
        "I'm basically a human loading screen",
        "my personality is 90% expired memes"
    ]
    
    // MARK: Response Templates
    
    static let responseTemplateJokeRequest = "Here are 5 fresh original jokes using different techniques. Pick a style or say 'expand this one' and I'll go deeper:"
    static let responseTemplateRoastRequest = "Roast cannon loaded. How savage (1-10)? Or just say 'go' and I'll read the room."
    static let responseTemplateUserSharedJoke = "Viewing your current joke right now... Running full analysis + creative vocabulary upgrades:"
    static let responseTemplateMixed = "Mixing styles for maximum chaos: first a pure joke, then a roast twist, then a vocabulary glow-up — buckle up:"
    
    // MARK: Knowledge Base
    
    static let comedyLegends = [
        "George Carlin (observational)", "Dave Chappelle (story)",
        "Ricky Gervais (sarcasm)", "Hannah Gadsby (deconstruction)",
        "Norm Macdonald (deadpan)"
    ]
    
    /// Pick a random vocabulary upgrade suggestion for a given word.
    static func vocabularyUpgrade(for word: String) -> String? {
        let lower = word.lowercased()
        // Check observational upgrades first
        if let upgrade = vocabObservationalUpgrades[lower] {
            return "Replace \"\(word)\" with \"\(upgrade)\" — adds vivid imagery and raises the laugh density."
        }
        // Check synonyms
        if let options = synonyms[lower], let pick = options.randomElement() {
            return "Swap \"\(word)\" for \"\(pick)\" — punchier and more specific."
        }
        return nil
    }
    
    /// Pick random creative vocab suggestions (3–5 items).
    static func randomVocabSuggestions(count: Int = 4) -> [String] {
        var suggestions: [String] = []
        if let word = vocabExaggeration.randomElement() {
            suggestions.append("Try the exaggeration: \"\(word)\"")
        }
        if let phrase = vocabTwistPhrases.randomElement() {
            suggestions.append("Add a twist: \"\(phrase)\"")
        }
        if let adj = vocabPunchyAdjectives.randomElement() {
            suggestions.append("Punch it up with: \"\(adj)\"")
        }
        if let nyc = vocabNYCFlavored.randomElement() {
            suggestions.append("NYC flavor: \"\(nyc)\"")
        }
        if let selfDep = vocabSelfDeprecating.randomElement() {
            suggestions.append("Self-deprecation gem: \"\(selfDep)\"")
        }
        return Array(suggestions.shuffled().prefix(count))
    }
    
    /// Get a random roast example at the given intensity.
    static func randomRoastExample(intensity: String = "medium") -> String? {
        let matching = roastExamples.filter { $0.intensity == intensity }
        return matching.randomElement()?.example ?? roastExamples.randomElement()?.example
    }
    
}
