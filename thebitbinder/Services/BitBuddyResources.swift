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
}
