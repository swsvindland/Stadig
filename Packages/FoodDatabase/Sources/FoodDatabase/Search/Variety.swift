import Foundation

/// What comes after a search's first result. The ranking finds the food meant; left to itself
/// what follows is whatever scores next, which for a plain food is mostly the same food
/// again: USDA lists whole milk with and without added vitamins, white rice enriched and
/// not, with and without salt. So the foods that differ from an earlier one only in such a
/// note come after the ones that differ in kind, and a one-word search goes on to the kinds
/// of it people log: after milk, almond, skim and 2% milk, where malted, sheep's and human
/// milk came second to fourth. A word for a kind of food goes on to the foods it stands for
/// the same way, and they lead where the search's own first is none of them (`groups`).
enum Variety {
    /// How many results are looked at: the ones a screen shows without much scrolling.
    static let window = 40
    /// How many distinct foods come before the twins of the first ones.
    static let distinct = 12
    /// How many kinds follow the first result.
    static let kinds = 3
    /// How many kinds are looked up at once.
    static let asked = 5
    /// The score a kind's own search gives its food when it's surely that food.
    static let sure = 1.5

    /// A name's parts that say what was added or left out in making it, how it was graded or
    /// where it's kept, not what it is.
    private static let notes: Set<String> = [
        "with salt", "without salt", "with added salt", "without added salt", "salt added", "no salt added", "with salt added",
        "without salt added", "regular pack", "enriched", "unenriched", "bleached", "unbleached", "calcium-fortified", "year round average",
        "all grades", "select", "choice", "prime", "shelf stable", "refrigerated",
    ]

    /// What a food is fortified or kept fresh with, where a part says it's with or without it.
    private static let additives = ["vitamin", "calcium", "ca prop", "milk solids", "ascorbic", "iron", "dha", "folic"]

    /// A plain food's name without those notes, its parts in any order: two foods with the
    /// same one are the same food to anyone choosing between them.
    static func key(_ name: String) -> String {
        var text = name.lowercased()
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") { text.removeSubrange(open...close) }
        let parts = text.split(separator: ",").compactMap { part -> String? in
            var part = part.trimmingCharacters(in: .whitespaces)
            // How closely a cut was trimmed, which USDA lists a cut by three times over.
            if notes.contains(part) || part.hasPrefix("trimmed to ") { return nil }
            if part.hasPrefix("with ") || part.hasPrefix("without "), additives.contains(where: part.contains) { return nil }
            for tail in [" without added salt", " with added salt", " without salt", " with salt"] where part.hasSuffix(tail) {
                part.removeLast(tail.count)
            }
            return part.isEmpty ? nil : part
        }
        return parts.sorted().joined(separator: "|")
    }

    /// Everyday foods that end on a word and aren't a kind of it: peanut butter isn't a butter,
    /// nor ice cream a cream, coconut water a water or root beer a beer.
    private static let others: Set<String> = [
        "peanut butter", "almond butter", "ice cream", "ice cream sandwich", "coconut water", "tonic water", "root beer", "jelly beans",
        "rice cakes", "crab cake", "chocolate chips", "fish oil", "baking soda", "hot chocolate", "grilled cheese", "egg whites", "kettle corn",
        "caramel corn", "french toast", "english muffin", "french dip", "shredded wheat", "sweet potato", "frozen yogurt",
    ]

    /// The everyday foods named by a word with another before it, the most logged first:
    /// for "milk", whole, almond, oat, skim and 2% milk. Not a dish named with "and" (rice
    /// and beans), nor a food that only ends on the word. Nothing for a word no such food
    /// ends on.
    static func kinds(of word: String) -> [String] {
        // "green" is on its way to green beans or green tea, not the greens it stems to.
        guard word != "green" else { return [] }
        let head = stem(word)
        return EverydayPhrases.all.filter { $0.words.count > 1 && $0.words.last.map(stem) == head && !$0.words.contains("and") }
            .map { $0.words.joined(separator: " ") }.filter { !others.contains($0) }
    }

    /// A word for a kind of food, and the everyday foods it stands for where they aren't named
    /// with it: nuts are almonds, peanuts and cashews, and no search of "nuts" finds them.
    /// With `leads`, they come before the search's own first result, which is no food anyone
    /// means by the word: the catalogs' first seeds are a lotus's, their greens green tea,
    /// their dairy a non-dairy milk and their poultry mechanically deboned.
    static let groups: [String: (foods: [String], leads: Bool)] = {
        let follow: [([String], [String])] = [
            (["nuts"], ["almonds", "peanuts", "cashews", "walnuts"]),
            (["berries"], ["strawberries", "blueberries", "raspberries", "blackberries"]),
            (["fruit", "fruits"], ["apple", "banana", "orange", "grapes"]),
            (["vegetables", "veggies", "veg"], ["broccoli", "carrots", "spinach", "green beans"]),
            (["meat", "meats"], ["chicken", "beef", "pork", "turkey"]),
            (["fish"], ["salmon", "tuna", "cod", "tilapia"]),
            (["shellfish"], ["shrimp", "crab", "lobster", "clams"]),
            (["cereal", "cereals"], ["corn flakes", "granola", "oatmeal", "shredded wheat"]),
            (["melon", "melons"], ["watermelon", "honeydew", "cantaloupe"]),
            (["grains"], ["quinoa", "oats", "barley", "rice"]),
            (["alcohol"], ["wine", "vodka", "whiskey", "beer"]),
        ]
        let lead: [([String], [String])] = [
            (["seeds"], ["sunflower seeds", "chia seeds", "flax seeds", "pumpkin seeds"]),
            (["greens"], ["salad greens", "spinach", "kale", "collard greens"]),
            (["seafood"], ["shrimp", "salmon", "crab", "tuna"]),
            (["poultry"], ["chicken", "turkey", "duck"]),
            (["citrus"], ["orange", "lemon", "lime", "grapefruit"]),
            (["dairy"], ["milk", "cheese", "yogurt", "butter"]),
            (["legumes", "pulses"], ["beans", "lentils", "chickpeas", "peas"]),
            (["liquor", "spirits"], ["vodka", "whiskey", "rum", "tequila"]),
            (["booze"], ["beer", "wine", "vodka", "whiskey"]),
            (["snacks"], ["potato chips", "popcorn", "pretzels", "trail mix"]),
            (["dessert", "desserts"], ["ice cream", "cake", "cookie", "brownie"]),
            (["herbs"], ["basil", "parsley", "cilantro", "mint"]),
            (["spices"], ["black pepper", "cinnamon", "paprika", "cumin"]),
        ]
        var groups: [String: (foods: [String], leads: Bool)] = [:]
        for (words, foods) in follow { for word in words { groups[word] = (foods, false) } }
        for (words, foods) in lead { for word in words { groups[word] = (foods, true) } }
        return groups
    }()

    /// The ranked foods in the order they're shown. `named` gives the plain food each phrase
    /// names, where one does, which is how a kind is found whatever the search itself turned
    /// up.
    static func varied(_ ranked: [Ranked], typed: String, named: ([String]) -> [Ranked?]) -> [Ranked] {
        // One word and nothing else: not "2 eggs", nor "eggs on toast", which goes on to
        // the toast. And the word as typed, whole: "green" isn't greens.
        let words = typed.split(whereSeparator: \.isWhitespace)
        let word = words.count == 1 ? words[0].lowercased() : nil
        let group = word.flatMap { groups[$0] }
        let leads = group?.leads ?? false
        // The foods a word stands for are found whatever the catalogs name by it, which
        // for "legumes" or "booze" may be nothing.
        guard ranked.count > 2 || leads else { return ranked }
        var seen = Set(ranked.prefix(1).map { key($0.food.name) })
        // A search of one word goes on to its kinds, each a food that differs from the ones
        // before it. They're asked for a few at a time: the first few usually do.
        var lifted: [Ranked] = []
        if let word {
            var phrases = (group?.foods ?? kinds(of: word))[...]
            let wanted = leads ? kinds + 1 : kinds
            while lifted.count < wanted, !phrases.isEmpty {
                for case let best? in named(Array(phrases.prefix(asked))) where lifted.count < wanted {
                    guard best.food.id != ranked.first?.food.id, seen.insert(key(best.food.name)).inserted else { continue }
                    // Its score is from its own search; here it sits just ahead of the next,
                    // or of the first where it leads.
                    var best = best
                    if let next = leads ? ranked.first : ranked.dropFirst().first { best.score = next.score }
                    lifted.append(best)
                }
                phrases = phrases.dropFirst(asked)
            }
        }
        let chosen = Set(lifted.map(\.food.id))
        // Then the foods that differ in kind, and after the first of them their twins.
        let plain = { (food: Food) in food.source == .usda && (food.brand ?? "").isEmpty }
        var first: [Ranked] = []
        var twins: [Ranked] = []
        var rest: [Ranked] = []
        for found in ranked.prefix(window).dropFirst() where !chosen.contains(found.food.id) {
            if first.count >= distinct {
                rest.append(found)
            } else if plain(found.food), !seen.insert(key(found.food.name)).inserted {
                twins.append(found)
            } else {
                first.append(found)
            }
        }
        let own = Array(ranked.prefix(1))
        let head = leads ? lifted + own : own + lifted
        var shown = head + first + twins + rest + ranked.dropFirst(window).filter { !chosen.contains($0.food.id) }
        // The scores still fall in the order shown.
        for i in shown.indices.dropFirst() { shown[i].score = min(shown[i].score, shown[i - 1].score) }
        return shown
    }
}
