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
    public var oneDish: Bool?

    public init(
        avoid: Set<String> = [], want: Set<String> = [], diet: PlanPreferences.Diet? = nil, cheaper: Bool? = nil,
        quicker: Bool? = nil, oneDish: Bool? = nil
    ) {
        self.avoid = avoid
        self.want = want
        self.diet = diet
        self.cheaper = cheaper
        self.quicker = quicker
        self.oneDish = oneDish
    }

    public var isEmpty: Bool { avoid.isEmpty && want.isEmpty && diet == nil && cheaper == nil && quicker == nil && oneDish == nil }

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
        if let oneDish { p.oneDish = oneDish }
        return p
    }

    /// "No fish · more Tex-Mex · cheaper", for the screen.
    public var summary: String {
        var parts: [String] = []
        if let diet { parts.append(diet.label) }
        if let oneDish { parts.append(oneDish ? "one dish all week" : "two dishes") }
        if !avoid.isEmpty { parts.append("no " + PlanRequests.names(avoid).joined(separator: ", ")) }
        if !want.isEmpty { parts.append("more " + PlanRequests.names(want).joined(separator: ", ")) }
        if cheaper == true { parts.append("cheaper") }
        if quicker == true { parts.append("quicker") }
        return parts.joined(separator: " · ").capitalizedFirst
    }
}

/// Reads a request ("no fish this week, and I'm sick of chicken") into a plan change, by its
/// words. The on-device model, when there is one, reads it too, into short phrases this reads the
/// same way; `PlanAssistant.merge` keeps the ones for foods the request names.
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
    /// Words that end what a negation covers: "no chicken, more salmon", "no pasta just rice". Not
    /// "and" or "or", which carry it along a list: "allergic to shellfish and peanuts".
    static let breaks: Set<String> = [
        ",", ";", ".", "but", "though", "more", "want", "add", "love", "like", "prefer", "please",
        "with", "plus", "just",
    ]
    /// Breaks that belong to the negation just before them: "don't want", "not like", "no more".
    static let negatedVerbs: Set<String> = ["want", "like", "love", "prefer", "more"]
    /// Words that can sit between a negation and its verb: "don't really want", "don't want to eat any more",
    /// "don't just give me".
    static let fillers: Set<String> = ["really", "much", "particularly", "even", "actually", "any", "to", "eat", "have", "just"]
    /// After a food group, these leave it out: "lactose intolerant", "a nut allergy". Before one,
    /// with "to" or "of": "an allergy to shellfish".
    static let allergies: Set<String> = ["intolerant", "intolerance", "allergy", "allergies", "sensitive", "sensitivity"]
    /// A verb starting a new clause after "and" ends the negation the way a comma would: "no rice
    /// and use quinoa", "no fish and make it spicy". Elsewhere they're just words: "can't eat fish".
    static let clauseVerbs: Set<String> = ["use", "try", "do", "make", "give", "have", "eat", "get", "include", "go", "put", "keep"]

    public static func read(_ text: String) -> PlanChange { reading(text).change }

    /// The change a request asks for, and every food, flavour and food group it names, wanted or
    /// not: all the model's reading may use (`PlanAssistant.merge`).
    static func reading(_ text: String) -> (change: PlanChange, named: Set<String>) {
        var change = PlanChange()
        var named: Set<String> = []
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let tokens = tokenize(lower)
        let words = " \(tokens.joined(separator: " ")) "
        // Phrases that aren't single foods.
        if says(words, ["vegan"]) {
            change.diet = .vegetarian
            change.avoid.formUnion(["dairy", "eggs"])
        } else if says(words, ["vegetarian", "veggie", "meatless", "plant-based", "plant based", "no meat"]) {
            change.diet = .vegetarian
        } else if says(words, ["pescatarian", "pescetarian"]) {
            change.diet = .pescatarian
        } else if says(words, ["meat again", "eat everything", "anything is fine", "back to normal"]) {
            change.diet = .everything
        }
        if says(words, ["cheap", "budget", "save money", "less expensive", "affordable"]) { change.cheaper = true }
        if says(words, ["quick", "fast", "less time", "no time", "busy", "easy", "simple", "short on time", "lazy"]) {
            change.quicker = true
        }
        for (word, _) in FoodTags.named where says(words, ["\(word)-free", "\(word) free"]) {
            if let group = group(word) { change.avoid.insert(group) }
        }
        if says(words, ["coeliac", "celiac"]) { change.avoid.insert("gluten") }

        change.oneDish = oneDish(tokens)
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
            if negations.contains(token) || (allergies.contains(token) && i + 1 < tokens.count && ["to", "of"].contains(tokens[i + 1])) {
                negated = true
                verbOfNegation = true
                i += 1
                continue
            }
            // The longest phrase starting here.
            var matched = false
            for length in stride(from: 3, through: 1, by: -1) where i + length <= tokens.count {
                let phrase = tokens[i..<i + length].joined(separator: " ")
                let tag = group(phrase)
                let ids = vocabulary.filter { $0.phrase == phrase }.flatMap(\.ids)
                guard tag != nil || !ids.isEmpty else { continue }
                named.formUnion(ids)
                if let tag { named.insert(tag) }
                named.formUnion(wantedTags[phrase] ?? [])
                let allergy = tag != nil && i + length < tokens.count && allergies.contains(tokens[i + length])
                if negated || allergy {
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
        named.formUnion(change.avoid)
        return (change, named)
    }

    /// True for one dish all week ("the same meal for lunch and dinner", "just one dish"), false
    /// for two again ("more variety"), nil when the request says neither. A negation just before
    /// turns a phrase round: "not the same meal", "instead of two different meals".
    static func oneDish(_ tokens: [String]) -> Bool? {
        let meals = tokens.contains("lunch") && tokens.contains("dinner")
        let one =
            [
                "same meal", "same dish", "same bowl", "same recipe", "same thing every day", "same every day", "one dish", "one bowl",
                "one recipe", "single dish", "single meal",
            ] + (meals ? ["same", "single", "combine", "combined", "identical", "both"] : [])
        let two =
            ["two dishes", "two meals", "two bowls", "two recipes", "different dishes", "different meals", "variety", "mix it up"]
            + (meals ? ["different"] : [])
        for (phrases, asked) in [(one, true), (two, false)] {
            for phrase in phrases {
                let words = phrase.split(separator: " ").map(String.init)
                guard tokens.count >= words.count,
                    let start = (0...tokens.count - words.count).first(where: { tokens[$0..<$0 + words.count].elementsEqual(words) })
                else { continue }
                var before = start - 1
                while before >= 0, leadIns.contains(tokens[before]) { before -= 1 }
                return before >= 0 && negations.contains(tokens[before]) ? !asked : asked
            }
        }
        return nil
    }

    /// Words that can sit between a negation and the phrase it turns round: "instead of two
    /// different meals", "don't want the same meal".
    static let leadIns: Set<String> = ["of", "the", "a", "two", "need", "want", "really", "have", "do", "any", "to"]

    /// What's still wanted once the avoided things are out: an avoided id, or a food the avoided
    /// tags or the diet rule out ("no fish" is no salmon either; a vegetarian diet isn't also a wish
    /// for every food it names).
    static func remaining(_ want: Set<String>, avoiding avoid: Set<String>, diet: PlanPreferences.Diet? = nil) -> Set<String> {
        let preferences = PlanPreferences(diet: diet ?? .everything, avoid: avoid)
        return want.filter { id in !avoid.contains(id) && (Library.ingredient(id).map(preferences.allows) ?? true) }
    }

    /// Reads short phrases the model tidied a request into: only foods and flavours, since the
    /// word rules read the diet, cost and time from the request itself.
    public static func read(avoid: [String], want: [String]) -> PlanChange {
        var change = PlanChange()
        for phrase in avoid { change.avoid.formUnion(read("no \(phrase)").avoid) }
        for phrase in want { change.want.formUnion(read(phrase).want) }
        change.want = remaining(change.want, avoiding: change.avoid)
        return change
    }

    /// Whether any of the phrases is in the request's words (`" no fish , cheaper "`), starting at
    /// a word: "cheap" is in "cheaper", "fast" isn't in "breakfast" nor "nut-free" in "peanut-free".
    static func says(_ words: String, _ phrases: [String]) -> Bool { phrases.contains { words.contains(" \($0)") } }

    /// The word a request leaves a food group out by: the first `FoodTags.named` has for it, which
    /// the setup's chips use too, so "lactose intolerant" shows as Dairy left out. Nil for a word
    /// that isn't a food group.
    static func group(_ word: String) -> String? {
        guard let tags = FoodTags.named.first(where: { $0.word == word })?.tags else { return nil }
        return FoodTags.named.first { $0.tags == tags }?.word
    }

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
