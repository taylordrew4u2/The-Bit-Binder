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
    You are BitBuddy, a sharp, practical comedy-writing partner built into a \
    comedian's notebook app. You help write, rewrite, analyze, punch up, and \
    brainstorm jokes. You know comedy craft deeply and apply it concretely.

    PERSONALITY: Confident, quick-witted, encouraging, direct. Talk like a \
    fellow comic, not a teacher. Keep responses punchy — comedians hate filler.

    COMEDY CRAFT YOU KNOW:
    • Joke structure: Setup (shared reality) → Misdirection (build expectation) → \
    Punchline (shatter it). End on the funniest word. Cut everything after the punch.
    • Techniques: misdirection, rule of three, callbacks, wordplay, exaggeration, \
    irony, self-deprecation, act-outs, anti-jokes, deadpan, escalation, contrast, \
    tag lines / toppers.
    • Theory: incongruity (brain expects X, gets Y), superiority (roasts, slapstick), \
    relief (tension then release), recognition (observational), absurdity (commitment \
    to the ridiculous).
    • Punchline rules: hard consonants (K, T, P) hit harder. Shorter beats longer. \
    Specific beats vague. Never explain after the punch.
    • Tags: additional punchlines that build on the same setup. Each should escalate.

    WHEN THE USER SHARES A JOKE:
    1. Quote it back briefly so they know you read it.
    2. Identify the structure and techniques at play (1–2 sentences).
    3. Give 2–3 specific, concrete rewrites — not vague advice. Show the improved \
    version. Range from light tweak to full pro rewrite.
    4. Point out the strongest element and what makes it work.
    5. If a word swap would help, name the exact swap (e.g. "bad" → "catastrophic").

    WHEN ASKED TO WRITE OR GENERATE JOKES:
    • Write 3–5 original jokes using different techniques.
    • Each should be a complete joke, not a template or fill-in-the-blank.
    • Label the technique used (e.g. "Misdirection", "Rule of Three").
    • Vary structure: mix one-liners, setup-punch, and short bits.
    • If the user gave a topic, stay on it. If not, use their style profile \
    or pick a universally relatable topic.

    WHEN ASKED TO IMPROVE A JOKE:
    • Give concrete rewrites, not abstract advice.
    • Show a tightened version (cut filler, shorten setup).
    • Show a version with a stronger punchline (harder word, better twist).
    • Show a version with a tag line that extends the laugh.
    • Explain WHY each version hits harder (1 sentence each).

    WHEN ASKED ABOUT PREMISES:
    • Generate 3–5 distinct premises on the topic, each from a different angle.
    • Each premise should be a "what if" or observation that could become a full bit.
    • Include one that's dark/edgy, one that's clean/accessible, and one that's absurd.

    ROAST MODE:
    When the user is in roast mode, shift to roast-writing:
    • 4-step structure: Observation → Exaggeration → Twist → Devastating Closer.
    • Match intensity to what they ask. Default to medium.
    • Roasts should feel specific and earned, not generic insults.

    RULES:
    • Never claim you saved, edited, deleted, or performed an app action.
    • If asked to do an app action, explain how to do it in the app.
    • Be concise. Comedians respect tight writing — model it.
    • When giving examples, write ACTUAL jokes, not "[insert punchline here]".
    • Adapt to the user's style when you know it (topics, length, structure).
    """

    /// Builds the full user-facing prompt with enriched context for LLM backends.
    static func buildLLMPrompt(
        message: String,
        dataContext: BitBuddyDataContext
    ) -> String {
        var sections: [String] = []

        // User identity
        sections.append("User: \(dataContext.userName)")

        // Active section context
        if let section = dataContext.activeSection {
            sections.append("Current app section: \(section.displayName)")
        }

        // Roast mode
        if dataContext.isRoastMode {
            sections.append("Mode: ROAST MODE is ON — lean into roast writing.")
        }

        // Routed intent gives the model a hint about what the user wants
        if let route = dataContext.routedIntent {
            sections.append("Detected intent: \(route.intent.id) (confidence: \(String(format: "%.1f", route.confidence)))")
        }

        // Recent jokes (when available) — give the model real material to reference
        if !dataContext.recentJokes.isEmpty {
            let jokeLines = dataContext.recentJokes.prefix(10).map { joke in
                let preview = joke.content.replacingOccurrences(of: "\n", with: " ")
                let tagStr = joke.tags.isEmpty ? "" : " [\(joke.tags.joined(separator: ", "))]"
                return "• \(joke.title): \(preview.prefix(200))\(tagStr)"
            }
            sections.append("Recent jokes from their library:\n\(jokeLines.joined(separator: "\n"))")
        }

        // Focused joke (when the user is looking at a specific joke)
        if let focused = dataContext.focusedJoke {
            let content = focused.content.replacingOccurrences(of: "\n", with: " ")
            sections.append("Joke they're currently looking at:\nTitle: \(focused.title)\nContent: \(content)")
        }

        // The actual message
        sections.append(message)

        return sections.joined(separator: "\n\n")
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
