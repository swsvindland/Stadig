import Foundation

/// What a request changes about next week's plan.
public struct PlanChange: Hashable, Sendable {
    /// Ingredient ids, profile ids and tag words ("fish") to leave out.
    public var avoid: Set<String> = []
    /// Ingredient, profile and template ids to lean toward.
    public var want: Set<String> = []
    public var diet: PlanPreferences.Diet?
    public var cheaper: Bool?
    public var quicker: Bool?

    public init(avoid: Set<String> = [], want: Set<String> = [], diet: PlanPreferences.Diet? = nil, cheaper: Bool? = nil,
                quicker: Bool? = nil) {
        self.avoid = avoid
        self.want = want
        self.diet = diet
        self.cheaper = cheaper
        self.quicker = quicker
    }

    public var isEmpty: Bool { avoid.isEmpty && want.isEmpty && diet == nil && cheaper == nil && quicker == nil }

    /// The preferences with this change: an avoided thing is no longer wanted, and the other way round.
    public func applied(to preferences: PlanPreferences) -> PlanPreferences {
        var p = preferences
        if let diet { p.diet = diet }
        p.avoid.subtract(want)
        p.want.subtract(avoid)
        p.avoid.formUnion(avoid)
        // A new wish replaces last week's, so a plan doesn't drift toward everything ever asked for.
        if !want.isEmpty { p.want = want }
        if let cheaper { p.cheaper = cheaper }
        if let quicker { p.quicker = quicker }
        return p
    }

    /// "No fish · more Tex-Mex · cheaper", for the screen.
    public var summary: String {
        var parts: [String] = []
        if let diet { parts.append(diet.label) }
        if !avoid.isEmpty { parts.append("no " + PlanRequests.names(avoid).joined(separator: ", ")) }
        if !want.isEmpty { parts.append("more " + PlanRequests.names(want).joined(separator: ", ")) }
        if cheaper == true { parts.append("cheaper") }
        if quicker == true { parts.append("quicker") }
        return parts.joined(separator: " · ").capitalizedFirst
    }
}

/// Reads a request ("no fish this week, and I'm sick of chicken") into a plan change, by its
/// words. The on-device model, when there is one, first tidies messy requests into short phrases
/// this reads the same way.
public enum PlanRequests {
    /// Words for building blocks, flavours and breakfasts, longest phrases first when matched.
    static let vocabulary: [(phrase: String, ids: [String])] = {
        var v: [(String, [String])] = [
            ("chicken", ["chicken-breast", "chicken-thigh"]), ("chicken breast", ["chicken-breast"]), ("thighs", ["chicken-thigh"]),
            ("thigh", ["chicken-thigh"]), ("turkey", ["turkey"]), ("beef", ["beef"]), ("mince", ["beef", "turkey"]),
            ("ground beef", ["beef"]), ("steak", ["beef"]), ("pork", ["pork"]), ("salmon", ["salmon"]), ("cod", ["cod"]),
            ("white fish", ["cod"]), ("shrimp", ["shrimp"]), ("prawns", ["shrimp"]), ("prawn", ["shrimp"]), ("tofu", ["tofu"]),
            ("lentils", ["lentils"]), ("lentil", ["lentils"]), ("chickpeas", ["chickpeas"]), ("chickpea", ["chickpeas"]),
            ("beans", ["black-beans"]), ("black beans", ["black-beans"]), ("rice", ["rice-white", "rice-brown"]),
            ("white rice", ["rice-white"]), ("brown rice", ["rice-brown"]), ("quinoa", ["quinoa"]), ("pasta", ["pasta"]),
            ("potatoes", ["potato"]), ("potato", ["potato"]), ("sweet potato", ["sweet-potato"]), ("sweet potatoes", ["sweet-potato"]),
            ("broccoli", ["broccoli"]), ("green beans", ["green-beans"]), ("carrots", ["carrots"]), ("carrot", ["carrots"]),
            ("peppers", ["peppers"]), ("pepper", ["peppers"]), ("zucchini", ["zucchini"]), ("courgette", ["zucchini"]),
            ("cauliflower", ["cauliflower"]), ("brussels sprouts", ["brussels"]), ("sprouts", ["brussels"]), ("spinach", ["spinach"]),
            ("kimchi", ["kimchi"]), ("feta", ["feta"]), ("oats", ["oats", "overnight-oats"]), ("oatmeal", ["overnight-oats"]),
            ("overnight oats", ["overnight-oats"]), ("egg muffins", ["egg-muffins"]), ("yogurt", ["greek-yogurt", "yogurt-bowl"]),
            ("yoghurt", ["greek-yogurt", "yogurt-bowl"]), ("kefir", ["kefir", "kefir-banana"]), ("cottage cheese", ["cottage-cheese"]),
            ("almonds", ["almonds"]),
        ]
        for profile in Library.profiles { for word in profile.words { v.append((word, [profile.id])) } }
        return v.sorted { $0.0.split(separator: " ").count > $1.0.split(separator: " ").count }
    }()

    /// Wanting one of these means more of its foods: "more fish" is salmon and cod.
    static let wantedTags: [String: [String]] = [
        "fish": ["salmon", "cod"], "seafood": ["shrimp", "salmon"], "meat": ["beef", "pork"], "red meat": ["beef"],
        "poultry": ["chicken-breast", "turkey"], "eggs": ["egg-muffins"], "egg": ["egg-muffins"],
    ]

    static let negations: Set<String> = ["no", "not", "without", "avoid", "hate", "hates", "dislike", "dislikes", "skip", "less", "fewer",
                                         "never", "stop", "remove", "drop", "allergic", "dont", "don't", "cant", "can't", "sick",
                                         "tired", "bored", "except", "nothing", "instead", "lose", "ditch", "swap", "replace"]
    static let breaks: Set<String> = [",", ";", ".", "but", "and", "though", "more", "want", "add", "love", "like", "prefer", "please",
                                      "with", "plus"]

    public static func read(_ text: String) -> PlanChange {
        var change = PlanChange()
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        // Phrases that aren't single foods.
        if lower.contains("vegan") {
            change.diet = .vegetarian
            change.avoid.formUnion(["dairy", "eggs"])
        } else if contains(lower, ["vegetarian", "veggie", "meatless", "plant-based", "plant based", "no meat"]) {
            change.diet = .vegetarian
        } else if lower.contains("pescatarian") || lower.contains("pescetarian") {
            change.diet = .pescatarian
        } else if contains(lower, ["meat again", "eat everything", "anything is fine", "back to normal"]) {
            change.diet = .everything
        }
        if contains(lower, ["cheap", "budget", "save money", "less expensive", "affordable"]) { change.cheaper = true }
        if contains(lower, ["quick", "fast", "less time", "easy", "simple", "short on time", "lazy"]) { change.quicker = true }
        for (word, _) in FoodTags.named where lower.contains("\(word)-free") || lower.contains("\(word) free") {
            change.avoid.insert(word)
        }

        let tokens = tokenize(lower)
        var negated = false
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if breaks.contains(token) { negated = false; i += 1; continue }
            if negations.contains(token) { negated = true; i += 1; continue }
            // The longest phrase starting here.
            var matched = false
            for length in stride(from: 3, through: 1, by: -1) where i + length <= tokens.count {
                let phrase = tokens[i..<i + length].joined(separator: " ")
                if let tag = FoodTags.named.first(where: { $0.word == phrase }), Library.ingredient(phrase) == nil,
                   !vocabulary.contains(where: { $0.phrase == phrase }) {
                    if negated { change.avoid.insert(tag.word) } else if let ids = wantedTags[phrase] { change.want.formUnion(ids) }
                    i += length
                    matched = true
                    break
                }
                let ids = vocabulary.filter { $0.phrase == phrase }.flatMap(\.ids)
                if !ids.isEmpty {
                    if negated { change.avoid.formUnion(ids) } else { change.want.formUnion(ids) }
                    i += length
                    matched = true
                    break
                }
            }
            if !matched { i += 1 }
        }
        // A diet word isn't also a wish for every food it names.
        if change.diet == .vegetarian { change.want.subtract(["beef", "pork", "chicken-breast", "chicken-thigh", "turkey", "salmon", "cod", "shrimp"]) }
        change.want.subtract(change.avoid)
        return change
    }

    /// Reads short phrases the model tidied a request into.
    public static func read(avoid: [String], want: [String], diet: String, cheaper: Bool, quicker: Bool) -> PlanChange {
        var change = PlanChange()
        for phrase in avoid {
            let read = self.read("no \(phrase)")
            change.avoid.formUnion(read.avoid)
            if read.diet != nil { change.diet = read.diet }
        }
        for phrase in want {
            let read = self.read(phrase)
            change.want.formUnion(read.want)
            if read.diet != nil { change.diet = read.diet }
        }
        switch diet.lowercased() {
        case "vegetarian", "vegan": change.diet = .vegetarian
        case "pescatarian": change.diet = .pescatarian
        case "everything": change.diet = .everything
        default: break
        }
        if cheaper { change.cheaper = true }
        if quicker { change.quicker = true }
        change.want.subtract(change.avoid)
        return change
    }

    static func contains(_ text: String, _ phrases: [String]) -> Bool { phrases.contains { text.contains($0) } }

    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for character in text {
            if character.isLetter || character == "-" || character == "'" {
                word.append(character)
            } else {
                if !word.isEmpty { tokens.append(word); word = "" }
                if [",", ";", "."].contains(character) { tokens.append(String(character)) }
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    /// Display names for ids and tag words.
    static func names(_ ids: Set<String>) -> [String] {
        var names: [String] = []
        for id in ids.sorted() {
            let name = Library.ingredient(id)?.short ?? Library.profile(id)?.name ?? Library.template(id)?.name.lowercased() ?? id
            if !names.contains(name) { names.append(name) }
        }
        // "chicken" covers "chicken thigh".
        return names.filter { name in !names.contains { $0 != name && name.hasPrefix($0 + " ") } }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
