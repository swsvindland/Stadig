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

    public init(
        avoid: Set<String> = [], want: Set<String> = [], diet: PlanPreferences.Diet? = nil, cheaper: Bool? = nil,
        quicker: Bool? = nil
    ) {
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

    static let negations: Set<String> = [
        "no", "not", "without", "avoid", "hate", "hates", "dislike", "dislikes", "skip", "less", "fewer",
        "never", "stop", "remove", "drop", "allergic", "dont", "don't", "cant", "can't", "cannot",
        "doesnt", "doesn't", "didnt", "didn't", "won't", "wouldnt", "wouldn't", "sick",
        "tired", "bored", "except", "nothing", "instead", "lose", "ditch", "swap", "replace",
    ]
    /// Words that end what a negation covers: "no chicken, more salmon". Not "and" or "or", which
    /// carry it along a list: "allergic to shellfish and peanuts".
    static let breaks: Set<String> = [
        ",", ";", ".", "but", "though", "more", "want", "add", "love", "like", "prefer", "please",
        "with", "plus",
    ]
    /// Breaks that belong to the negation just before them: "don't want", "not like", "no more".
    static let negatedVerbs: Set<String> = ["want", "like", "love", "prefer", "more"]
    /// Words that can sit between a negation and its verb: "don't really want", "don't want to eat any more".
    static let fillers: Set<String> = ["really", "much", "particularly", "even", "actually", "any", "to", "eat", "have"]
    /// A verb starting a new clause after "and" ends the negation the way a comma would: "no rice
    /// and use quinoa", "no fish and make it spicy". Elsewhere they're just words: "can't eat fish".
    static let clauseVerbs: Set<String> = ["use", "try", "do", "make", "give", "have", "eat", "get", "include", "go", "put", "keep"]

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
        // Just after a negation, where "want" or "more" is still part of it.
        var verbOfNegation = false
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if verbOfNegation, negatedVerbs.contains(token) || fillers.contains(token) {
                i += 1
                continue
            }
            verbOfNegation = false
            let newClause = i > 0 && tokens[i - 1] == "and" && clauseVerbs.contains(token)
            if breaks.contains(token) || newClause {
                negated = false
                i += 1
                continue
            }
            if negations.contains(token) {
                negated = true
                verbOfNegation = true
                i += 1
                continue
            }
            // The longest phrase starting here.
            var matched = false
            for length in stride(from: 3, through: 1, by: -1) where i + length <= tokens.count {
                let phrase = tokens[i..<i + length].joined(separator: " ")
                let tag = FoodTags.named.first { $0.word == phrase }?.word
                let ids = vocabulary.filter { $0.phrase == phrase }.flatMap(\.ids)
                guard tag != nil || !ids.isEmpty else { continue }
                if negated {
                    // A tag word leaves out everything with it, even when it also names a food or a
                    // flavour: "allergic to peanut" is the Peanut-lime bowl and peanuts, "no soy" is
                    // teriyaki and soy sauce, "no eggs" is every egg.
                    if let tag { change.avoid.insert(tag) }
                    change.avoid.formUnion(ids)
                } else {
                    // A food or flavour by name, else the foods a tag stands for: "more fish".
                    change.want.formUnion(ids.isEmpty ? wantedTags[phrase] ?? [] : ids)
                }
                i += length
                matched = true
                break
            }
            if !matched { i += 1 }
        }
        change.want = remaining(change.want, avoiding: change.avoid, diet: change.diet)
        return change
    }

    /// What's still wanted once the avoided things are out: an avoided id, or a food the avoided
    /// tags or the diet rule out ("no fish" is no salmon either; a vegetarian diet isn't also a wish
    /// for every food it names).
    static func remaining(_ want: Set<String>, avoiding avoid: Set<String>, diet: PlanPreferences.Diet? = nil) -> Set<String> {
        let preferences = PlanPreferences(diet: diet ?? .everything, avoid: avoid)
        return want.filter { id in !avoid.contains(id) && (Library.ingredient(id).map(preferences.allows) ?? true) }
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
        change.want = remaining(change.want, avoiding: change.avoid, diet: change.diet)
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
                if !word.isEmpty {
                    tokens.append(word)
                    word = ""
                }
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
