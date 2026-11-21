import FoodDatabase
import Foundation

/// A seen food's catalog candidates, best first, and how sure the ranking is.
struct Candidates: Sendable {
    var matches: [FoodMatch]
    /// The first `tied` matches are within a point of the best: a near-tie the model may settle.
    var tied: Int
    /// The best match is strong enough to log without asking.
    var sure: Bool
}

/// The model's answer to a near-tie: entry `entry` (1-based) for asked food `food` (1-based).
struct Pick: Hashable, Sendable {
    var food: Int
    var entry: Int
}

/// Retrieval and ranking against the catalog. The catalog scores; this decides what is sure,
/// what is a near-tie for the model to settle, and what to offer instead.
enum Matching {
    /// A best score at or above this is logged without asking; below it, it is only offered.
    static let sureScore = 1.5
    /// Candidates within this of the best are a near-tie.
    static let tieWindow = 1.0
    static let maxTies = 6
    static let maxAlternatives = 5
    static let retrieved = 40

    static func candidates(for seen: SeenFood, catalog: some MealCatalog, personal: [PersonalFood]) -> Candidates {
        let ranked = catalog.candidates(name: seen.name, brand: seen.brand.nilIfEmpty, personal: personal, limit: retrieved)
        // A misread brand should cost one tap, so the plain food stays among the options.
        var generic: [FoodMatch] = []
        if !seen.brand.isEmpty && !ranked.contains(where: { !isBranded($0.food) }) {
            generic = catalog.candidates(name: seen.name, brand: nil, personal: personal, limit: 10).filter { !isBranded($0.food) }
        }
        return rank(ranked, branded: !seen.brand.isEmpty, generic: generic, seen: seen.name)
    }

    /// A best match this far below the top that fits what was seen beats a top match that doesn't.
    static let fitWindow = 2.0

    /// The match names everything seen, is the same kind of thing, and has numbers that can be right:
    /// white mushrooms or rice for a flat white do neither, and a powder's 452 kcal per 100 ml on a
    /// bottled flat white can't be logged as one.
    static func fits(_ name: String, _ food: Food) -> Bool {
        food.isPlausible && covers(name, food) && Drinks.sameKind(name, food) && !qualifies(name, food)
    }

    /// The same for a catalog's match, which names what was seen where the catalog read it so,
    /// whatever the words alone say: a frankfurter for a hot dog, brewed coffee for black
    /// coffee, toast for "toast with butter", cooked white rice for jasmine rice, scrambled eggs
    /// for "scrambled eggs (2 large)".
    static func fits(_ name: String, _ match: FoodMatch) -> Bool {
        match.food.isPlausible && (match.named || covers(name, match.food)) && Drinks.sameKind(name, match.food) && !qualifies(name, match.food)
    }

    /// The first part of a catalog name, where it says what the food is: up to its first comma or
    /// bracket ("Chickpeas" in "Chickpeas (garbanzo beans, bengal gram), mature seeds").
    static func firstPart(_ name: String) -> String {
        String(name.prefix { $0 != "," && $0 != "(" })
    }

    private static let kindEnd = Pattern(#"\s(?:or|in|with|on)\s.*$"#)
    private static let readyTo = Pattern(#"\bready[- ]to[- ](?:eat|drink|serve|heat)\b"#)

    /// The words of that part that say what kind of food it is, the last naming it: not what it
    /// comes in or with or may also be ("Pulled pork in barbecue sauce" is pulled pork, a "Ham
    /// sandwich or sub" a ham sandwich), nor how it's sold ("Cereals ready-to-eat" are cereals).
    static func kind(of food: Food) -> [String] {
        let part = readyTo.replacing(in: kindEnd.replacing(in: firstPart(food.name), with: ""), with: " ")
        return FoodText.words(part).map(FoodText.stem)
    }

    /// Two words for one food in a catalog's name: "Jams and preserves" are jam.
    private static let sameFood: [String: Set<String>] = ["jam": ["preserve"], "preserve": ["jam"]]

    /// The food's name starts with what was seen: "Blueberries, raw" for blueberries.
    static func filedUnder(_ name: String, _ food: Food) -> Bool {
        guard let head = FoodText.nameWords(name).last.map(FoodText.stem) else { return false }
        return FoodText.words(firstPart(food.name)).map(FoodText.stem).contains { FoodText.same($0, head) || FoodText.same(head, $0) }
    }

    /// The food is something else, which what was seen only describes: "Salad dressing" for a caesar
    /// salad, "Chicken salad" for chicken, "Apple juice" for an apple. The food's own kind is the
    /// last word of its name's first part; USDA files under a group first ("Fish, salmon"), which
    /// doesn't count against it.
    static func qualifies(_ name: String, _ food: Food) -> Bool {
        let kind = kind(of: food)
        let seen = FoodText.nameWords(name).map(FoodText.stem)
        guard let head = seen.last, let own = kind.last, kind.count > 1 else { return false }
        let named = { (word: String) in seen.contains { FoodText.same($0, word) || FoodText.same(word, $0) } }
        return kind.dropLast().contains { FoodText.same($0, head) || FoodText.same(head, $0) } && !named(own) && sameFood[head]?.contains(own) != true
    }

    /// Cooking and cutting words a catalog name may leave out: grilled chicken is roasted chicken.
    private static let preparation: Set<String> = Set(
        ("grilled baked roasted boiled steamed poached sauteed broiled cooked raw fresh "
            + "homemade sliced chopped diced shredded hot cold iced toasted plain organic").split(separator: " ").map(String.init))

    /// Every word of the seen name, but its preparation, is in the food's name or brand in some form.
    static func covers(_ name: String, _ food: Food) -> Bool {
        let have = FoodText.words(food.name + " " + (food.brand ?? "")).map(FoodText.stem)
        let all = FoodText.nameWords(name)
        let named = all.filter { !preparation.contains($0) }
        return (named.isEmpty ? all : named).allSatisfy { word in
            FoodText.forms(word).contains { form in have.contains { FoodText.same($0, form) } }
        }
    }

    /// The options to show, with the brand-free foods a branded guess keeps one tap away. Given
    /// what was `seen`, a match that fits it comes first when one scores close enough, only fitting
    /// matches are near-ties, and an unfitting best match is never sure.
    static func rank(_ ranked: [FoodMatch], branded: Bool, generic extra: [FoodMatch] = [], seen: String? = nil) -> Candidates {
        // A plain food is judged by the food its name is for, as the catalog matched it: the
        // toast of "toast with butter", the cereal of "cereal with milk", which is no drink.
        let seen = branded ? seen : seen.map(FoodCatalog.food(in:))
        var ranked = ranked.enumerated().sorted { ($0.element.score, -$0.offset) > ($1.element.score, -$1.offset) }.map(\.element)
        let fit: (FoodMatch) -> Bool = { match in seen.map { fits($0, match) } ?? true }
        if let top = ranked.first, !fit(top), let i = ranked.firstIndex(where: { fit($0) && $0.score >= top.score - fitWindow }) {
            ranked.insert(ranked.remove(at: i), at: 0)
        }
        let head = Array(ranked.prefix(branded ? 6 : 8))
        let ids = Set(head.map(\.id))
        let generic =
            branded
            ? Array((ranked.filter { !ids.contains($0.id) && !isBranded($0.food) } + extra.filter { !ids.contains($0.id) }).prefix(2))
            : []
        var listed = Set<String>()
        var top = (head + generic + ranked).filter { listed.insert($0.id).inserted }.prefix(8).map { $0 }
        guard let first = top.first else { return Candidates(matches: [], tied: 0, sure: false) }
        // The model only settles near-ties (raw or cooked, which lettuce); it can't override a far
        // better name match, and a clear winner needs no second opinion at all. Ties lead the list.
        let best = first.score
        let fitting = fit(first)
        // When the best match files under what was seen ("Blueberries, raw"), a food filed under
        // something else ("Muffins, blueberry") is a dish that contains it, not a near-tie.
        let itself = { (match: FoodMatch) in seen.map { filedUnder($0, match.food) } ?? true }
        let alone = itself(first)
        let close = { (match: FoodMatch) in match.score >= best - tieWindow && (!fitting || fit(match)) && (!alone || itself(match)) }
        let rest = top.dropFirst()
        top = [first] + rest.filter(close) + rest.filter { !close($0) }
        let tied = 1 + rest.filter(close).count
        // Numbers that can't be right are offered, never logged without a look.
        return Candidates(matches: top, tied: min(tied, maxTies), sure: best >= sureScore && fitting && first.food.isPlausible)
    }

    /// The seen foods whose sure best match has rivals close enough to ask the model about, and
    /// different enough to matter: salted or unsalted butter isn't worth a second request.
    static func asked(_ found: [Candidates]) -> [Int] {
        found.indices.filter { found[$0].sure && found[$0].tied > 1 && !alike(found[$0].matches.prefix(found[$0].tied)) }
    }

    /// Foods measured the same way whose energy differs by at most 15 kcal or 12% per 100 g or ml.
    static func alike(_ matches: some Collection<FoodMatch>) -> Bool {
        guard let basis = matches.first?.food.basis, basis != .serving, matches.allSatisfy({ $0.food.basis == basis }) else { return false }
        let kcal = matches.map(\.food.nutrients.kcal)
        let most = kcal.max() ?? 0
        return most - (kcal.min() ?? 0) <= max(15, most * 0.12)
    }

    /// The second, text-only request: one numbered list of near-tied entries per asked food, with
    /// the meal for context ("beans" in a burrito bowl are black or pinto beans).
    static func pickPrompt(seen: [SeenFood], found: [Candidates], asked: [Int], meal: String = "") -> String {
        let blocks = asked.enumerated().map { n, i in
            let food = seen[i]
            let entries = found[i].matches.prefix(found[i].tied).enumerated().map { j, match in
                "  \(j + 1). \(FoodText.clean(match.food.name, limit: 70))" + (match.food.brand.map { " (\(FoodText.clean($0, limit: 30)))" } ?? "")
            }
            return (["Food \(n + 1): " + (food.brand.isEmpty ? "" : "\(food.brand) ") + food.name] + entries).joined(separator: "\n")
        }
        let context = FoodText.clean(meal, limit: 300)
        return "Choose one entry number for each food." + (context.isEmpty ? "" : " The meal: \"\(context)\"") + "\n\n"
            + blocks.joined(separator: "\n\n")
    }

    /// The chosen match per seen food (nil when there are none). Unanswered foods and bad answers
    /// keep the ranked first choice.
    static func choices(_ picks: [Pick], found: [Candidates], asked: [Int]) -> [Int?] {
        var chosen: [Int?] = found.map { $0.matches.isEmpty ? nil : 0 }
        for pick in picks {
            guard pick.food >= 1, pick.food <= asked.count else { continue }
            let i = asked[pick.food - 1]
            if pick.entry >= 1 && pick.entry <= found[i].tied { chosen[i] = pick.entry - 1 }
        }
        return chosen
    }

    /// Up to five other matches, best first; a branded guess keeps a plain food among them.
    static func alternatives(_ matches: [FoodMatch], chosen: Int?, branded: Bool) -> [FoodMatch] {
        let others = matches.indices.filter { $0 != chosen }.map { matches[$0] }
        var list = Array(others.prefix(maxAlternatives))
        if branded, !list.isEmpty, !list.contains(where: { !isBranded($0.food) }),
            let plain = others.dropFirst(maxAlternatives).first(where: { !isBranded($0.food) })
        {
            list[list.count - 1] = plain
        }
        return list
    }

    private static let shout = Pattern("[A-Z]", caseInsensitive: false)

    /// Restaurant and packaged foods, which suit a seen food only when its brand is known.
    static func isBranded(_ food: Food) -> Bool {
        if food.source == .off || !(food.brand ?? "").isEmpty { return true }
        // USDA prefixes restaurant items in capitals: "McDONALD'S, french fries", "T.G.I. FRIDAY'S, …".
        var first = String(food.name.split(whereSeparator: { $0 == " " || $0 == "," }).first ?? "")
        if first.hasPrefix("Mc") { first.removeFirst(2) }
        return first == first.uppercased() && shout.allMatches(in: first).count >= 2
    }
}
