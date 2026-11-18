import Foundation

/// What a search or a model names: "chicken breast", or "big mac" from McDonald's.
struct Named {
    var name: String
    var brand: String
}

/// What a typed search or a match knows beyond its words.
struct RankHints {
    var fixes: Fixes = [:]
    /// Among packaged foods, the ones people scan most rank higher (typed searches only).
    var popularity = false
    /// Packaged foods sold only in other countries than the phone's.
    var away: Set<String> = []
    /// The search's words that name a brand: "trader joes" in "trader joes mini wheats".
    var brand: [String] = []
    /// What the food the other words name is usually like.
    var profile: Profile?
    /// The search's words the catalogs barely know as typed, which may be a food's word misspelt.
    var doubted: Set<String> = []
    /// The corrections that are the same words written as one or apart ("redbull", "pop corn").
    var respelt: Set<String> = []
    /// The search's words that are a food's far more often than a brand's, though some food is
    /// listed under them: "seeds", "milk", "water".
    var plain: Set<String> = []
}

/// A ranked food.
struct Ranked {
    var food: Food
    var score: Double
    var index: Int
    var name: Double
}

// MARK: - Word lists

private func stems(_ text: String) -> Set<String> { Set(text.split(separator: " ").map { stem(String($0)) }) }

/// Catalog words that describe how an ordinary food is prepared or measured, not a different food.
private let neutral = stems(
    "raw cooked ripe fresh plain regular original whole prepared commercial average year round all type varieties includes baked "
        + "broiled roasted grilled boiled steamed pan fried microwaved heated cured sliced chopped diced shredded mature seeds "
        + "without salt added drained solids liquid enriched unenriched white red yellow green brewed tap water ready serve "
        + "made broilers fluid fryers meat only flesh separable fish beverages alcoholic nuts crustaceans mollusks spices "
        // How it's sold, and what's added to an ordinary food to keep or fortify it: bagels "with
        // calcium propionate", tofu "prepared with calcium sulfate", juice "with added ascorbic acid".
        + "commercially bottled shelf stable unsweetened salted unsalted vitamin calcium propionate ca prop sulfate nigari "
        + "ascorbic acid potassium sodium magnesium chloride iron "
        // How a cut of meat is graded and trimmed. Not its fat, which USDA also lists as a food
        // ("Pork, fresh, separable fat").
        + "trimmed lean choice select prime grades boneless")

/// Words that mark a less common form or part; the model should name these if it means them.
private let variationWords = stems(
    "powder dehydrated dried canned frozen unprepared imitation meatless substitute low reduced nonfat free fortified mix "
        + "flake concentrate baby infant toddler stick oil seed juice paste puree soup dry lite light diet sugar sweetened "
        + "blend spread flavored feet giblets liver gizzard heart neck back skin kidney tongue tripe glutinous "
        + "sprouted instant parboiled precooked turkey stewed babyfood product brain evaporated condensed melba rusk candied")

/// Words for a food made of something else, a further step from the food than a form of it:
/// meatless meatballs aren't meatballs the way frozen ones are.
private let insteadWords = stems("meatless imitation substitute")

/// Kinds of food named after what they're made with or taste of, which follow it in a packaged
/// food's name: cake pretzels, peanut butter cups, cheese crackers, chocolate milk. Forms already
/// in `variationWords` (oil, juice, powder) aren't repeated; words that also say what a food is like
/// ("thin", "strips", "balls") are left out.
private let formWords = stems(
    "bar bite chip crisp cracker pretzel fries fry cup pop puff roll muffin cookie cake bread sandwich wafer cluster "
        + "nugget crumb snack tender pie dip sauce dressing seasoning candy cereal granola drink shake smoothie creamer "
        + "popcorn ice gelato frosting filling pudding jam jelly butter batter yogurt milk water flour syrup bagel waffle "
        + "pancake biscuit brownie donut doughnut tart latte tea coffee salad burger wrap burrito taco pizza crust dough "
        + "noodle pasta broth sausage meatball dumpling bowl kit")

/// Words after which a name goes on to another part of the food: "cake with chocolate filling".
private let partWords: Set<String> = ["with", "and", "or", "in", "on", "filled", "topped", "dipped", "covered", "coated", "stuffed"]

/// How the catalog words the fat level a search names with a number: "2%" is reduced fat.
private let fatWords = stems("fat milkfat lowfat low reduced nonfat lean")

/// USDA's own markers for the typical entry among varieties: "Tomatoes, red, ripe, raw, year round
/// average", "Soymilk, original and vanilla".
private let typicalWords = stems("average varieties regular ripe original")

/// The peoples whose traditional foods USDA lists beside the everyday ones, in a note: "Corn,
/// white, steamed (Navajo)", "Blueberries, wild, raw (Alaska Native)".
private let traditionWords = stems("navajo hopi apache alaska shoshone bannock plains")

/// The everyday variety when a food doesn't name one ("rice" is usually long-grain).
private struct Usual {
    let marks: [String]
    let others: [String]
    let markStems: [String]
    let otherStems: [String]

    init(_ marks: [String], _ others: [String]) {
        self.marks = marks
        self.others = others
        markStems = marks.map(stem)
        otherStems = others.map(stem)
    }
}

private let breadKinds =
    ("rye egg oatmeal raisin cinnamon french italian vienna multigrain sourdough pumpernickel potato cheese "
    + "banana corn pita naan garlic gluten protein rice oat muffin muffins sprouted reduced calorie pumpkin irish soda "
    + "boston brown mixed grain cracked crust stuffing crumb crumbs").split(separator: " ").map(String.init)

/// The meats a steak or a cut can be of, when it isn't beef.
private let meats =
    "bison deer elk veal pork lamb ham salmon tuna fish game buffalo venison moose caribou turkey chicken salisbury emu ostrich goat"
    .split(separator: " ").map(String.init)

/// By the stem a word is searched by: "whiskey" is looked up as "whiske".
private let usualVarieties: [String: Usual] = Dictionary(uniqueKeysWithValues: everydayVarieties.map { (stem($0.key), $0.value) })

private let everydayVarieties: [String: Usual] = [
    "rice": Usual(["long"], ["short", "medium", "brown", "wild", "basmati", "jasmine"]),
    "cheese": Usual(
        ["cheddar", "american"],
        "mozzarella parmesan swiss feta provolone cottage cream goat blue ricotta monterey brie gouda"
            .split(separator: " ").map(String.init)),
    "milk": Usual(["whole"], "skim nonfat reduced lowfat almond soy oat chocolate buttermilk".split(separator: " ").map(String.init)),
    "egg": Usual(["whole"], ["white", "yolk"]),
    // Toast and a slice of bread are white or wheat; any other kind named is that kind.
    "toast": Usual(["white", "wheat"], breadKinds),
    "bread": Usual(["white", "wheat"], breadKinds),
    // Beans in a bowl or a burrito are black or pinto; any kind named is that kind.
    "bean": Usual(
        ["black", "pinto"],
        ("snap green yellow wax string baked refried lima fava broad navy kidney northern great white cannellini "
            + "garbanzo chickpea mung adzuki soy soybean edamame coffee cocoa vanilla jelly french yardlong hyacinth "
            + "winged moth cranberry shellie lupini mothbean").split(separator: " ").map(String.init)),
    // Sugar in a recipe or a coffee is granulated, tea is black, wine is table wine, chips are
    // potato chips and popcorn is popped, not pressed into cakes or coated.
    "sugar": Usual(["granulated"], "brown powdered maple turbinado coconut cane date palm raw free".split(separator: " ").map(String.init)),
    "tea": Usual(
        ["black"], "green herb herbal hibiscus oolong chamomile instant white iced chai matcha".split(separator: " ").map(String.init)),
    "wine": Usual(["table"], "cooking dessert rose light sparkling rice non".split(separator: " ").map(String.init)),
    "chip": Usual(
        ["potato"],
        "banana taro bagel tortilla corn pita apple plantain kale veggie vegetable sweet chocolate rice pea lentil bean"
            .split(separator: " ").map(String.init)),
    "popcorn": Usual(["popped"], "cake caramel cheese microwave kettle chicken".split(separator: " ").map(String.init)),
    // Bacon is cured pork and a steak is beef, which USDA files under "Pork" and "Beef"; the kinds
    // filed under the word itself are the unusual ones ("Bacon, turkey", "Game meat, bison, steak").
    "bacon": Usual(["pork"], "turkey canadian beef meatless bits vegetarian chicken".split(separator: " ").map(String.init)),
    "steak": Usual(["beef"], meats),
    "ribeye": Usual(["beef"], meats),
    "sirloin": Usual(["beef"], meats),
    "mayonnaise": Usual(["regular"], "tofu light imitation reduced low diet free olive vegan".split(separator: " ").map(String.init)),
    "mayo": Usual(["regular"], "tofu light imitation reduced low diet free olive vegan".split(separator: " ").map(String.init)),
    "whiskey": Usual(["distilled"], ["sour", "mix"]),
    "pita": Usual(["bread"], ["chip", "pitanga"]),
    "cottage": Usual(["creamed", "lowfat"], "vegetable fruit nonfat uncreamed dry lactose sodium".split(separator: " ").map(String.init)),
    "zucchini": Usual(["summer"], ["baby", "italian", "canned"]),
    "granola": Usual(["cereal"], ["bar", "bite"]),
]

/// Searches and seen foods naming these mean the cooked food unless they say "raw": "salmon",
/// "rice", "chicken", the beans in a burrito bowl, a bowl of oatmeal.
private let eatenCooked = stems(
    "rice pasta noodle spaghetti macaroni quinoa lentil oatmeal porridge chicken beef pork turkey lamb steak bacon sausage "
        + "salmon fish tuna cod tilapia shrimp egg potato bean chickpea barley couscous bulgur farro millet grits polenta "
        + "duck goose veal bison venison ribeye sirloin brisket tenderloin crab lobster scallop trout halibut catfish haddock")
private let cookedWords = stems("cooked roasted baked boiled broiled grilled steamed poached scrambled fried braised microwaved")

/// The cooked words in the catalog's full-text syntax, as prefixes.
private let cookedTerm =
    "("
    + "cooked roasted baked boiled broiled grilled steamed poached scrambled braised microwaved"
    .split(separator: " ").map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"

/// Extra catalog queries for the everyday form of a plain seen food, run beside the usual ones so
/// a long USDA name for it is in the pool at all: the cooked form of what's eaten cooked
/// ("Cereals, oats, …, cooked with water" for oatmeal), and the everyday variety ("black" or
/// "pinto" beans for beans). A form the `pool` already has a food filed under isn't searched again.
func everydayQueries(_ seen: Named, pool: [Entry] = []) -> [String] {
    guard seen.brand.isEmpty else { return [] }
    let name = nameWords(seen.name)
    let said = name.map(stem)
    guard !name.isEmpty, !said.contains("raw") else { return [] }
    let base = name.map(term).joined(separator: " AND ")
    var variety: String?
    if let usual = said.lazy.compactMap({ usualVarieties[$0] }).first,
        !said.contains(where: { usual.otherStems.contains($0) || usual.markStems.contains($0) })
    {
        variety = "(" + usual.marks.map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"
    }
    let cooked = said.contains(where: eatenCooked.contains) && !said.contains(where: cookedWords.contains)
    // Foods filed under what was said: "Fish, salmon, …" for salmon.
    let filed = pool.lazy.filter { entry in
        !entry.text.lead.isEmpty && entry.text.lead.allSatisfy { w in said.contains { same(w, $0) || starts(w, $0) } }
    }
    let haveCooked = filed.contains { $0.text.all.contains(where: cookedWords.contains) }
    let marks = variety == nil ? [] : (said.lazy.compactMap { usualVarieties[$0] }.first?.markStems ?? [])
    let haveVariety = filed.contains { entry in
        entry.text.all.contains(where: marks.contains) && (!cooked || entry.text.all.contains(where: cookedWords.contains))
    }
    var queries: [String] = []
    if let variety, !haveVariety { queries.append(([base, variety] + (cooked ? [cookedTerm] : [])).joined(separator: " AND ")) }
    if cooked, !haveCooked { queries.append("\(base) AND \(cookedTerm)") }
    return queries
}

/// USDA files some foods under a group: "Fish, salmon", "Beverages, coffee", "Nuts, almonds".
private let groups: Set<String> = [
    "fish", "beverage", "beverages", "alcoholic beverage", "alcoholic beverages", "nuts", "crustaceans", "mollusks", "spices",
    "cereals",
]

// MARK: - A food's words

/// The words of a food's name and brand that ranking reads, read once per ranking.
struct FoodText {
    /// The name's words, stemmed; "dry heat" is how USDA says cooked.
    let titled: [String]
    /// The name's and brand's words, stemmed.
    let all: [String]
    /// The brand's words as written, including a restaurant USDA writes first ("McDONALD'S, BIG MAC").
    let ownWords: [String]
    /// The same, stemmed.
    let own: [String]
    /// The name's words outside brackets and the brand, stemmed.
    let said: [String]
    /// Which run of `said` each word is in: a comma, "&" or "with" starts another.
    let runs: [Int]
    /// Words in brackets, stemmed, except "(Includes …)".
    let noted: [String]
    /// The words of an "(Includes …)" note, stemmed: other foods the entry stands for.
    let included: [String]
    /// The words before the name's first comma, after a USDA group ("Fish, salmon"), stemmed.
    let lead: [String]
    /// The words of the name's first two comma-separated parts, after a group, stemmed: "Oil" and
    /// "olive" in "Oil, olive, salad or cooking".
    let heads: [[String]]
    /// The name's words written in capitals, stemmed: the brands USDA names wherever in a name
    /// ("Yogurt, Greek, plain, CHOBANI").
    let shouted: [String]
    /// A restaurant or packaged food.
    let branded: Bool

    init(_ food: Food) { self.init(name: food.name, brand: food.brand ?? "", source: food.source) }

    /// Reads the name once: its words, which are in brackets, and which comma-separated part each is in.
    init(name original: String, brand: String, source: FoodSource) {
        let name = mentionsHeat(original) ? cookedHeat(original) : original
        let scalars = plainScalars(name)
        let found = scanTokens(scalars)
        let close = scalars.lastIndex(of: ")") ?? -1
        // Each token's bracket (none, a note, or an "(Includes …)" note), comma-separated part and run.
        var placed: [(bracket: Int, part: Int, run: Int)] = []
        placed.reserveCapacity(found.count)
        var bracket = 0
        var part = 0
        var run = 0
        var next = 0
        var commas: [Int] = []
        for (i, scalar) in scalars.enumerated() {
            if scalar == "(" && bracket == 0 && i < close {
                bracket = startsWithIncludes(scalars, i + 1) ? 2 : 1
            } else if scalar == ")" && bracket != 0 {
                bracket = 0
            } else if scalar == "," {
                part += 1
                run += 1
                commas.append(i)
            } else if scalar == "&" || scalar == "+" || scalar == "/" {
                run += 1
            }
            while next < found.count && found[next].start == i {
                if partWords.contains(found[next].word) { run += 1 }
                placed.append((bracket, part, run))
                next += 1
            }
        }
        let stems = found.map { stopWords.contains($0.word) ? "" : stem($0.word) }
        // Plain ASCII text keeps its letters' places, so a word's capitals can be read back.
        var shouted: [String] = []
        if source == .usda, name.utf8.allSatisfy({ $0 < 0x80 }) {
            let bytes = Array(name.utf8)
            for (i, token) in found.enumerated() where !stems[i].isEmpty && token.end - token.start > 1 {
                if bytes[token.start..<token.end].allSatisfy({ $0 >= 0x41 && $0 <= 0x5A }) { shouted.append(stems[i]) }
            }
        }
        self.shouted = shouted
        var titled: [String] = []
        var said: [String] = []
        var runs: [Int] = []
        var noted: [String] = []
        var included: [String] = []
        var parts: [[String]] = [[], [], []]
        for (i, token) in found.enumerated() where !stems[i].isEmpty {
            titled.append(stems[i])
            // "With skin" and "without skin" say how a fruit or a potato comes, not that the food
            // is its skin, as "Chicken, skin only" is.
            if stems[i] == "skin", i > 0, found[i - 1].word == "with" || found[i - 1].word == "without" { continue }
            if placed[i].bracket == 0 {
                said.append(stems[i])
                runs.append(placed[i].run)
            } else if placed[i].bracket == 1 {
                noted.append(stems[i])
            } else {
                included.append(stems[i])
            }
            // A note in brackets isn't what the food is filed under: "Chickpeas (garbanzo beans,
            // bengal gram), …" leads with chickpeas.
            if !isNumber(token.word) && placed[i].bracket == 0 {
                if placed[i].part < 3 { parts[placed[i].part].append(stems[i]) }
            }
        }
        let brandWords = words(brand)
        let ownWords: [String]
        if !brand.isEmpty {
            ownWords = brandWords
        } else if !shoutingStart(original, word: true) {
            ownWords = []
        } else {
            ownWords = FoodDatabase.brandWords(name: original, brand: "")
        }
        let own = ownWords.map(stem)
        self.titled = titled
        all = titled + brandWords.map(stem)
        self.ownWords = ownWords
        self.own = own
        let kept = own.isEmpty ? Array(said.indices) : said.indices.filter { !own.contains(said[$0]) }
        self.said = kept.map { said[$0] }
        self.runs = kept.map { runs[$0] }
        self.noted = noted
        self.included = included
        // USDA files some foods under a group: "Fish, salmon".
        let head = makeString(scalars[..<(commas.first ?? scalars.count)]).trimmingCharacters(in: .whitespaces)
        let secondPart = commas.isEmpty ? 0 : (commas.count > 1 ? commas[1] : scalars.count) - commas[0] - 1
        let grouped = groups.contains(head) && secondPart > 0
        // A chain USDA writes before the food leads with the food: pepperoni pizza in
        // `PAPA JOHN'S 14" Pepperoni Pizza`. "McDONALD'S, BIG MAC" keeps the chain, its whole first part.
        var first = parts[0]
        if brand.isEmpty && !own.isEmpty && first.count > own.count && first.starts(with: own) { first.removeFirst(own.count) }
        lead = grouped ? parts[1] : first
        heads = Array(parts[(grouped ? 1 : 0)...].prefix(commas.count + (grouped ? 0 : 1)).prefix(2))
        branded = !brand.isEmpty || source == .off || (shoutingStart(original, word: true) && shouting(dropMc(firstWord(original))))
    }
}

/// A food with its words read, so a ranking reads each food's name once and a catalog can keep it.
struct Entry: Sendable {
    let food: Food
    let text: FoodText
    /// Other names the catalog files the food under: the chains' items FNDDS counts as it
    /// ("McDonald's Chicken McNuggets" for chicken nuggets from fast food).
    let also: [OtherName]
    /// Catalogs repeat products, so listed foods are kept one per name and brand; others by id.
    let key: String
    /// The numbers hang together (see `Food.problem`); worked out once, as catalogs keep entries.
    let plausible: Bool

    /// `also` is the catalog's other names for the food, one a line.
    init(_ food: Food, also: String = "") {
        self.food = food
        text = FoodText(food)
        self.also = also.isEmpty ? [] : also.split(separator: "\n").map { OtherName(String($0), source: food.source) }
        plausible = food.isPlausible
        key = food.source == .usda || food.source == .off ? "\(food.name)|\(food.brand ?? "")".lowercased() : food.id
    }
}

/// One of a catalog's other names for a food, its words read like a name's.
struct OtherName: Sendable {
    let text: FoodText
    /// The word naming what it is, stemmed: the last, or the last before "with" ("McGriddle" in
    /// "McDonald's McGriddle with Egg"). A search finds the food by this name only when it asks for
    /// that, so "big mac" isn't "McDonald's Big Mac sauce".
    let head: String

    init(_ name: String, source: FoodSource) {
        text = FoodText(name: name, brand: "", source: source)
        let main = name.range(of: " with ", options: .caseInsensitive).map { String(name[..<$0.lowerBound]) } ?? name
        head = words(main).last.map(stem) ?? ""
    }
}

/// Whether a name may mention "dry heat" or "moist heat", checked without Foundation.
private func mentionsHeat(_ name: String) -> Bool {
    var matched = 0
    let word: [UInt8] = Array("heat".utf8)
    for byte in name.utf8 {
        let lower = byte >= 0x41 && byte <= 0x5A ? byte + 32 : byte
        matched = lower == word[matched] ? matched + 1 : (lower == word[0] ? 1 : 0)
        if matched == word.count { return true }
    }
    return false
}

/// Whether a bracket's note starts with "includes" as a word.
private func startsWithIncludes(_ scalars: [Unicode.Scalar], _ start: Int) -> Bool {
    let word = "includes".unicodeScalars
    guard start + word.count <= scalars.count else { return false }
    for (i, scalar) in word.enumerated() where scalars[start + i] != scalar { return false }
    let after = start + word.count
    guard after < scalars.count else { return true }
    let next = scalars[after].value
    return !((next >= 0x30 && next <= 0x39) || (next >= 0x61 && next <= 0x7A) || (next >= 0x41 && next <= 0x5A) || next == 0x5F)
}

/// A quick test that a name's first part (or first word) could be all capitals: no lower-case
/// ASCII letter except the c of a "Mc". Most names fail at once.
private func shoutingStart(_ name: String, word: Bool = false) -> Bool {
    var previous: UInt8 = 0x20
    var beforePrevious: UInt8 = 0x20
    for byte in name.utf8 {
        if byte == UInt8(ascii: ",") || (word && (byte == 0x20 || (byte >= 0x09 && byte <= 0x0D))) { return true }
        if byte >= 0x61 && byte <= 0x7A {
            let afterM = byte == UInt8(ascii: "c") && previous == UInt8(ascii: "M")
            let wordStart =
                !(beforePrevious >= 0x41 && beforePrevious <= 0x5A || beforePrevious >= 0x61 && beforePrevious <= 0x7A
                || beforePrevious >= 0x30 && beforePrevious <= 0x39 || beforePrevious == 0x5F)
            if !(afterM && wordStart) { return false }
        }
        beforePrevious = previous
        previous = byte
    }
    return true
}

/// `\b(?:dry|moist) heat\b` → "cooked".
private func cookedHeat(_ name: String) -> String {
    var result = name
    for phrase in ["dry heat", "moist heat"] {
        var search = result.startIndex..<result.endIndex
        while let found = result.range(of: phrase, options: .caseInsensitive, range: search) {
            let before = found.lowerBound == result.startIndex ? nil : result[result.index(before: found.lowerBound)]
            let after = found.upperBound == result.endIndex ? nil : result[found.upperBound]
            let boundary = { (c: Character?) in c.map { !($0.isLetter || $0.isNumber || $0 == "_") } ?? true }
            if boundary(before) && boundary(after) {
                result.replaceSubrange(found, with: "cooked")
                search = result.startIndex..<result.endIndex
            } else {
                search = found.upperBound..<result.endIndex
            }
        }
    }
    return result
}

private func firstWord(_ name: String) -> String {
    String(name.prefix { !($0 == "," || $0.isWhitespace) })
}

private func dropMc(_ word: String) -> String { word.hasPrefix("Mc") ? String(word.dropFirst(2)) : word }

/// All capitals, with at least two capital letters: "DOMINO'S", "T.G.I.".
private func shouting(_ text: String) -> Bool {
    text == text.uppercased() && text.unicodeScalars.filter { $0.value >= 0x41 && $0.value <= 0x5A }.count >= 2
}

/// The brand's words, including a restaurant or brand USDA writes first in capitals: "McDONALD'S,
/// BIG MAC", `PAPA JOHN'S 14" Pepperoni Pizza`, "SILK Chocolate, soymilk".
func brandWords(name: String, brand: String) -> [String] {
    if !brand.isEmpty { return words(brand) }
    var lead: [Substring] = []
    for word in name.prefix(while: { $0 != "," }).split(whereSeparator: \.isWhitespace) {
        guard shouting(dropMc(String(word))) else { break }
        lead.append(word)
    }
    return words(lead.joined(separator: " "))
}

/// Restaurant and packaged foods, which suit a seen food only when its brand is known.
func isBranded(_ food: Food) -> Bool { FoodText(food).branded }

// MARK: - Coverage

/// A word as searched: its forms and its corrections.
private struct WordForms {
    let word: String
    let options: [String]
    let fixes: [String]
    let fixParts: [[String]]
    /// For a word the catalogs barely know: the word, to compare with a food's own.
    let misspelling: Misspelling?
    /// The fixes that are the word written the other way, as one word or apart.
    let respelt: [[String]]

    init(_ word: String, prefix: Bool, fixes: Fixes, doubted: Bool = false, respelt: Set<String> = []) {
        self.word = word
        options = prefix ? searchForms(word) : forms(word)
        self.fixes = fixes[word] ?? []
        fixParts = self.fixes.map { $0.split(separator: " ").map(String.init) }
        misspelling = doubted ? Misspelling(word) : nil
        self.respelt = self.fixes.filter(respelt.contains).map { $0.split(separator: " ").map(String.init) }
    }
}

/// How well a food's name covers what was said.
struct Coverage {
    var name: Double
    /// Words said that the food doesn't have, even as corrected.
    var missing: Int
    /// The food's first two parts, inverted as USDA writes them, name exactly what was said:
    /// "Oil, olive" for olive oil.
    var named: Bool
    var partial: Int
    var head: Bool
    /// The word naming the food is in the name only to name another food after it: "cake" in
    /// Celebration Cake Pretzels, "peanut butter" in Peanut Butter Cups.
    var modifies: Bool
    var fixed: Int
    var usual: Bool
    var typical: Bool
    /// Words for a less common form, one made of something else counting half as much again.
    var variations: Double
    /// The words counted in `variations` and `others` that come before the word naming the food:
    /// "pork" in "Pork, cured, bacon", "salad dressing" in "Salad dressing, mayonnaise".
    var filed: [String]
    var others: Int
    var notes: Int
    var leads: Bool
    var brand: Bool?
    var cooked: Int
    var fried: Bool
}

/// The words that were said, read once for every food they are compared with. In a search the
/// words may be half typed, so a longer word also counts ("chic" finds chicken), below the word
/// itself, and a word found only in the brand counts half: "wheats" names a cereal, not the brand
/// Wheaty. With `nameOnly`, the words describe the product and only its name is read.
struct CoverageQuery {
    fileprivate let target: [WordForms]
    fileprivate let prefix: Bool
    fileprivate let nameOnly: Bool
    fileprivate let mentioned: [String]
    /// Words a food has whole, never as the start of a longer one: the same words as labels also
    /// write them, as one word or apart, and a size typed with the food.
    fileprivate let entire: [String]
    fileprivate let level: Bool
    fileprivate let brand: [WordForms]
    fileprivate let usual: Usual?

    init(
        seen: Named, target words: [String], prefix: Bool = false, fixes: Fixes = [:], nameOnly: Bool = false,
        doubted: Set<String> = [], respelt: Set<String> = []
    ) {
        self.prefix = prefix
        self.nameOnly = nameOnly
        target = words.map { WordForms($0, prefix: prefix, fixes: fixes, doubted: doubted.contains($0), respelt: respelt) }
        var mentioned: [String] = []
        var entire: [String] = []
        for word in target {
            // A word as labels also write it is that word and no start of another: the "meat" of
            // "meat balls", for "meatballs", doesn't make "meatless" a word that was asked for.
            let whole = word.fixes.filter(respelt.contains).flatMap { $0.split(separator: " ").map(String.init) }
            for form in whole where !entire.contains(form) { entire.append(form) }
            let started = word.options + word.fixes.filter { !respelt.contains($0) }.flatMap { $0.split(separator: " ").map(String.init) }
            for form in started where !mentioned.contains(form) { mentioned.append(form) }
        }
        let said = FoodDatabase.words(seen.name)
        // A size typed with a food isn't searched for, but a name that has it was asked for by
        // it: the "small" of "cottage cheese small curd".
        if prefix {
            for word in said where countWords.contains(word) && !words.contains(word) && !entire.contains(stem(word)) { entire.append(stem(word)) }
        }
        self.mentioned = mentioned
        self.entire = entire
        level = words.contains(where: isNumber)
        brand = FoodDatabase.words(seen.brand).map { WordForms($0, prefix: prefix, fixes: fixes) }
        // A corrected word asks for the same everyday variety as the word it corrects.
        let asked = said + fixValues(fixes, order: said)
        let usual = asked.lazy.compactMap { usualVarieties[stem($0)] }.first
        self.usual = usual.flatMap { usual in asked.contains(where: usual.others.contains) ? nil : usual }
    }

    init(seen: Named) { self.init(seen: seen, target: nameWords(seen.name)) }

    /// Whether the words name a food with an everyday variety.
    var asksUsual: Bool { usual != nil }

    @inline(__always) private func fits(_ w: String, _ form: String) -> Bool {
        isNumber(form) ? w == form : same(w, form) || (prefix && length(form) > 1 && starts(w, form))
    }

    /// Whether one of a food's words is one the search asked for.
    @inline(__always) private func asked(_ w: String) -> Bool {
        mentioned.contains { fits(w, $0) } || entire.contains { same(w, $0) }
    }

    @inline(__always) private func exact(_ w: String, _ form: String) -> Bool {
        prefix || isNumber(form) ? w == form : same(w, form)
    }

    /// The word itself, or the same word as labels also write it: "redbull" for the "red" and the
    /// "bull" of "red bull", "pop" and "corn" for "popcorn".
    private func whole(_ word: WordForms, _ found: [String]) -> Bool {
        word.options.contains { form in found.contains { exact($0, form) } }
            || word.respelt.contains { parts in parts.allSatisfy { part in found.contains { same($0, part) } } }
    }

    private func literal(_ word: WordForms, _ found: [String], whole: Bool) -> Bool {
        whole || (prefix && word.options.contains { form in found.contains { fits($0, form) } })
    }

    /// A fix is a word's start ("chick") or, for a word typed without its space, a phrase. A word
    /// the catalogs barely know is also one of the food's own words a typo or two from it.
    private func fixed(_ word: WordForms, _ found: [String]) -> Bool {
        word.fixParts.contains { parts in
            parts.indices.allSatisfy { i in
                found.contains { i == parts.count - 1 ? starts($0, parts[i]) : same($0, parts[i]) }
            }
        } || word.misspelling?.reads(found) == true
    }

    private func branded(_ word: WordForms, _ titled: [String]) -> Bool {
        prefix && !nameOnly && !word.options.contains { form in titled.contains { fits($0, form) } }
            && !word.fixParts.contains { parts in titled.contains { starts($0, parts[0]) } }
    }

    private func has(_ word: WordForms, _ found: [String]) -> Bool {
        literal(word, found, whole: whole(word, found)) || fixed(word, found)
    }

    /// `own` is how many of the first words said name the food's own brand: found there, they count
    /// in full.
    func cover(_ text: FoodText, own: Int = 0) -> Coverage {
        let found = nameOnly ? text.titled : text.all
        var total = 0.0
        var hits = 0.0
        var partial = 0
        var fixedCount = 0
        var missing = 0
        var head = false
        for (i, word) in target.enumerated() {
            // The last word names the food ("coffee" in "black coffee"); earlier words describe it.
            let weight = i == target.count - 1 ? 2.0 : 1.0
            total += weight
            let isWhole = whole(word, found)
            let isLiteral = literal(word, found, whole: isWhole)
            let isFixed = !isLiteral && fixed(word, found)
            let has = isLiteral || isFixed
            let inBrand = has && i >= own && branded(word, text.titled)
            // A typed word naming the food that the name has only in what it "(includes …)" names
            // another food: a plain bagel that includes poppy seed ones isn't "pop".
            let aside =
                prefix && has && i == target.count - 1 && !text.included.isEmpty && !self.has(word, text.said + text.noted + text.own)
            if has { hits += weight * (inBrand || aside ? 0.5 : 1) } else { missing += 1 }
            if !isWhole && isLiteral { partial += 1 }
            if isFixed { fixedCount += 1 }
            // The word that names the food is in its name: "wheats" in "Shredded Bite Size Wheats".
            if i == target.count - 1 { head = has && !inBrand && !aside }
        }
        var variations = 0.0
        var others = 0
        // Where the name last has the word naming the food, which is where it says what it is.
        let named = target.last.flatMap { last in text.said.lastIndex { w in last.options.contains { fits(w, $0) } } }
        var filed: [String] = []
        // USDA's "mature seeds" are dried beans and lentils as usually cooked, not the seeds of a plant.
        let legume = text.said.contains("mature") || text.said.contains("immature")
        for (i, w) in text.said.enumerated() where !isNumber(w) && !(level && fatWords.contains(w)) && !asked(w) {
            if w == "seed" && legume { continue }
            if variationWords.contains(w) {
                variations += insteadWords.contains(w) ? 1.5 : 1
            } else if !neutral.contains(w) {
                others += 1
            } else {
                continue
            }
            if let named, i < named { filed.append(w) }
        }
        let notes = text.noted.filter { w in !neutral.contains(w) && !asked(w) }.count
        // A people's traditional food, noted as theirs, is a kind of its own.
        if text.noted.contains(where: { traditionWords.contains($0) && !asked($0) }) { variations += 1 }
        // Sunflower seed butter is named after the seeds, though USDA files it under "Seeds".
        var modifies = false
        if let at = named {
            modifies = text.said.indices[(at + 1)...].contains { i in
                let w = text.said[i]
                return text.runs[i] == text.runs[at] && formWords.contains(w) && !asked(w)
            }
        }
        // USDA's inverted name for exactly what was said: "Oil, olive" for olive oil, "Rice, white"
        // for white rice; not "Oil, corn, peanut, and olive", nor "Chicken breast, roll".
        var inverted = false
        if missing == 0, text.heads.count == 2 {
            let both = text.heads[0] + text.heads[1]
            inverted =
                !target.allSatisfy { has($0, text.heads[0]) } && target.allSatisfy { has($0, both) }
                && both.allSatisfy(asked)
        }
        // By the name's own words, not a note of what else it includes: white bread "(includes
        // soft bread crumbs)" is still white bread.
        let kinds = nameOnly ? text.said + text.noted : text.said + text.noted + text.own
        let usual =
            self.usual.map { usual in
                kinds.contains { w in usual.markStems.contains { same(w, $0) } }
                    && !kinds.contains { w in usual.otherStems.contains { same(w, $0) } }
            } ?? false
        return Coverage(
            name: total > 0 ? hits / total : 0,
            missing: missing,
            named: inverted,
            partial: partial,
            head: head,
            modifies: modifies,
            fixed: fixedCount,
            usual: usual,
            typical: found.contains(where: typicalWords.contains),
            variations: variations,
            filed: filed,
            others: others,
            notes: notes,
            // USDA leads with the food itself: "Tomatoes, red, ripe, raw", not "Canadian bacon".
            // "Soy sauce made from soy" leads with soy sauce too: how it's made says no other food.
            leads: text.lead.contains(where: asked) && text.lead.allSatisfy { asked($0) || $0 == "made" || $0 == "from" },
            brand: brand.isEmpty ? nil : brand.allSatisfy { has($0, found) },
            cooked: found.contains(where: cookedWords.contains) ? 1 : found.contains("raw") ? -1 : 0,
            // Frying adds fat; roasted or boiled is the plainer cooked form.
            fried: found.contains("fried") && !mentioned.contains("fried"))
    }
}

/// A fix's values in the order their words were said, then any others.
func fixValues(_ fixes: Fixes, order: [String]) -> [String] {
    guard !fixes.isEmpty else { return [] }
    var keys: [String] = []
    for word in order where fixes[word] != nil && !keys.contains(word) { keys.append(word) }
    keys += fixes.keys.filter { !keys.contains($0) }.sorted()
    return keys.flatMap { fixes[$0]! }
}

func coverage(
    _ seen: Named, _ food: Food, target: [String]? = nil, prefix: Bool = false, fixes: Fixes = [:],
    nameOnly: Bool = false
) -> Coverage {
    CoverageQuery(seen: seen, target: target ?? nameWords(seen.name), prefix: prefix, fixes: fixes, nameOnly: nameOnly)
        .cover(FoodText(food))
}

// MARK: - Profiles

/// A kind of food's usual energy and macros per 100 g or ml: the middle of the foods that name it
/// and how far they stray. Calories are on a log scale, since a kind of food sets its density
/// rather than its exact calories.
struct Profile: Equatable {
    var center: [Double]
    var spread: [Double]

    /// How far another kind of food's middle is from this one's, in the wider of their spreads:
    /// under 2.25, as `likeness` has it, they are the same kind of food.
    func distance(to other: Profile) -> Double {
        var sum = 0.0
        for d in center.indices { sum += pow((center[d] - other.center[d]) / max(spread[d], other.spread[d]), 2) }
        return (sum / Double(center.count)).squareRoot()
    }
}

private func point(_ food: Food) -> [Double]? {
    food.basis == .serving
        ? nil
        : [log(max(0, food.nutrients.kcal) + 10), food.nutrients.protein, food.nutrients.carbs, food.nutrients.fat]
}

/// The least spread a profile allows: labels round, and recipes for one food differ this much.
private let leastSpread = [0.15, 3, 6, 3]

private func middle(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let half = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[half] : (sorted[half - 1] + sorted[half]) / 2
}

/// The profile of some foods, or nil for too few to say what such a food is like.
func profile(_ foods: [Food]) -> Profile? {
    let points = foods.compactMap(point)
    guard points.count >= 4 else { return nil }
    let center = leastSpread.indices.map { d in middle(points.map { $0[d] }) }
    let spread = leastSpread.indices.map { d in max(leastSpread[d], 1.4826 * middle(points.map { abs($0[d] - center[d]) })) }
    return Profile(center: center, spread: spread)
}

/// The profile of what words name, from the foods named little more than them: "peanut butter"
/// is the spread, not the cups and cookies named after it.
func profile(for product: [String], _ entries: [Entry], fixes: Fixes = [:], respelt: Set<String> = []) -> Profile? {
    let query = CoverageQuery(
        seen: Named(name: product.joined(separator: " "), brand: ""), target: product, prefix: true,
        fixes: fixes, nameOnly: true, respelt: respelt)
    var named: [Food] = []
    for entry in entries {
        let match = query.cover(entry.text)
        if match.name == 1 && Double(match.others) + match.variations <= 1 { named.append(entry.food) }
        if named.count == 12 { break }
    }
    return profile(named)
}

/// How much a food is like a profile's kind: 1 alike, 0 unsure, -1 another kind of food. A store's
/// shredded wheat cereal is like Mini-Wheats; its wheat bread, with half the carbs, is not.
func likeness(_ food: Food, _ kind: Profile) -> Double {
    guard let p = point(food) else { return 0 }
    var sum = 0.0
    for d in p.indices { sum += pow((p[d] - kind.center[d]) / kind.spread[d], 2) }
    let distance = (sum / Double(p.count)).squareRoot()
    return max(-1, min(1, (2.25 - distance) / 0.75))
}

// MARK: - Scoring

/// The person's own foods rank higher, and more so the more often they eat them.
private func boost(_ known: [String: Double], _ id: String) -> Double {
    guard let count = known[id] else { return 0 }
    return 1.5 + 0.5 * log1p(max(0, count))
}

/// Orders candidates: name match, common form, brand agreement, the person's own foods. A search
/// has no brand of its own unless `hints.brand` says which of its words name one; a food whose
/// brand it names in passing ("oreo", "mcdonalds big mac") is not marked down as branded. With a
/// profile, a food unlike the kind of food the words name ranks lower, and the named brand's food
/// most like it ranks first even under another name: Trader Joe's calls its Mini-Wheats
/// "Shredded Bite Size Wheats". Foods that don't match are left out.
func scoreFoods(
    _ seen: Named, _ foods: [Food], known: [String: Double] = [:], search: Bool = false,
    hints: RankHints = RankHints()
) -> [Ranked] {
    scoreFoods(seen, foods.map { Entry($0) }, known: known, search: search, hints: hints)
}

func scoreFoods(
    _ seen: Named, _ entries: [Entry], known: [String: Double] = [:], search: Bool = false,
    hints: RankHints = RankHints()
) -> [Ranked] {
    let read = search ? readQuery(seen.name) : nil
    let target = read.map { searchedWords($0.words) } ?? nameWords(seen.name)
    let brand = hints.brand
    let fixes = hints.fixes
    // With a brand named, the other words describe the product, and only its name is read for them.
    let asked = search && !brand.isEmpty
    let named = asked ? target.filter { !brand.contains($0) } : target
    // A brand alone names none of its foods over another, so how often each is scanned orders them.
    let alone = asked && named.isEmpty
    // A typed search and a food a model saw both mean the cooked form of what's usually eaten
    // cooked; a model asked for raw salmon says so.
    // A word still being typed counts once it's most of one: "chick" for chicken.
    // Not a food named after one: potato chips aren't a potato to bake.
    let namedAfter = target.last.map { formWords.contains(stem($0)) && !eatenCooked.contains(stem($0)) } ?? false
    let cooked =
        !target.contains("raw") && !namedAfter
        && (target + fixValues(fixes, order: target)).contains { word in
            let s = stem(word)
            return eatenCooked.contains(s) || (search && length(s) >= 4 && eatenCooked.contains { starts($0, s) })
        }
    // Catalogs repeat products; the person's own foods are each kept.
    var keys: [String] = []
    var unique: [String: Entry] = [:]
    for entry in entries {
        if unique[entry.key] == nil { keys.append(entry.key) }
        if unique[entry.key] == nil || known[entry.food.id] != nil { unique[entry.key] = entry }
    }
    let query = CoverageQuery(
        seen: seen, target: named.isEmpty ? target : named, prefix: search, fixes: fixes,
        nameOnly: asked && !named.isEmpty, respelt: hints.respelt)
    // The same, also reading a word the catalogs barely know as a food's own word misspelt.
    let lenient =
        hints.doubted.isEmpty
        ? nil
        : CoverageQuery(
            seen: seen, target: named.isEmpty ? target : named, prefix: search, fixes: fixes,
            nameOnly: asked && !named.isEmpty, doubted: hints.doubted, respelt: hints.respelt)
    // Each brand word's forms, a form being words in a row: "papajohns" is corrected to "papa john".
    let brandForms = brand.map { word in
        isNumber(word) ? [[word]] : (searchForms(word) + (fixes[word] ?? [])).map { $0.split(separator: " ").map(String.init) }
    }
    let brandParts = Array(brandForms.joined().joined())
    let mentionForms = target.map(searchForms)
    // Each word as it would name a brand's word, and as corrected ("sracy" names Stacy's).
    let typedBare = target.map { length($0) > 2 && !isNumber($0) ? bare($0) : "" }
    let last = target.count - 1
    let typedFixes = target.map { word in (fixes[word] ?? []).map { $0.split(separator: " ").map(String.init) } }
    let typedMisspelt = target.map { hints.doubted.contains($0) ? Misspelling($0) : nil }
    // The words said in another order, for a food whose brand some of them name (see `fit`),
    // apart for reading a misspelt word.
    var reordered: [[Int]: CoverageQuery] = [:]
    var reorderedLenient: [[Int]: CoverageQuery] = [:]
    // Whether a plain food has every word said, worked out when a food's brand first asks.
    var plainlyNamed: Bool?
    func isPlainlyNamed() -> Bool {
        if let plainlyNamed { return plainlyNamed }
        let found = unique.values.contains { !$0.text.branded && query.cover($0.text).missing == 0 }
        plainlyNamed = found
        return found
    }

    /// How a food covers what was said, and whether a search with no brand of its own names the
    /// food's brand. A food whose brand the search names word for word reads those words as its
    /// brand wherever they were typed, so the word naming the food is the last of the others:
    /// "cheese", not "cow", in "cottage cheese honest cow" for The Honest Cow's cottage cheese.
    /// With `misspelt`, a word the catalogs barely know is also one of the food's own words a typo
    /// or two from it, which names a brand too: "gali" for Galli's roasted chestnuts.
    func fit(_ text: FoodText, misspelt: Bool) -> (match: Coverage, own: Bool) {
        let whole = misspelt ? lenient ?? query : query
        guard search, !asked, last >= 0, !text.own.isEmpty else { return (whole.cover(text), false) }
        // Word for word, a plural or possessive apart: "wheats" isn't the brand Wheaty, though
        // they share a stem. Each of the brand's words takes one word said, so the "eggs" of "egg
        // land best brown eggs" still name the food; two said as one ("membermark") take it
        // together, and after a food the last word may be as far as the brand is typed ("oats
        // kas"; "pop" alone is on its way to popcorn as much as to Popchips).
        var naming: [Int] = []
        var halfTyped = false
        for (j, written) in text.ownWords.enumerated() {
            let word = bare(written)
            // A word that stands for two ("membermark", or "blackberries" as some labels write it)
            // names a brand only when both are the brand's: Member's Mark, not Berry Fresh.
            var named = target.indices.first { i in
                (!naming.contains(i) && typedBare[i] == word)
                    || typedFixes[i].contains { parts in
                        parts.contains(text.own[j]) && parts.allSatisfy { length($0) > 2 && text.own.contains($0) }
                    }
            }
            if named == nil, misspelt {
                named = target.indices.first { !naming.contains($0) && typedMisspelt[$0]?.reads([text.own[j]]) == true }
            }
            if named == nil, !naming.contains(last), !typedBare[last].isEmpty, starts(written, target[last]) {
                named = last
                halfTyped = true
            }
            guard let named else { return (whole.cover(text), false) }
            if !naming.contains(named) { naming.append(named) }
        }
        // A one-word brand that is a food's word on nearly every label isn't one the search names
        // when a plain food has every word: chia seeds listed under "Seeds" are no brand's. Typed
        // whole, that is ("water" is on its way to Waterloo), and "high protein supersnack edamame"
        // is still the Supersnack listed under "Edamame", which no plain food is.
        if text.ownWords.count == 1, !halfTyped, let word = naming.first, hints.plain.contains(target[word]), isPlainlyNamed() {
            return (whole.cover(text), false)
        }
        if naming.count == target.count { return (whole.cover(text), !halfTyped) }
        naming.sort()
        if let known = misspelt ? reorderedLenient[naming] : reordered[naming] { return (known.cover(text, own: naming.count), true) }
        let order = naming + target.indices.filter { !naming.contains($0) }
        let moved = CoverageQuery(
            seen: seen, target: order.map { target[$0] }, prefix: true, fixes: fixes, doubted: misspelt ? hints.doubted : [],
            respelt: hints.respelt)
        if misspelt { reorderedLenient[naming] = moved } else { reordered[naming] = moved }
        return (moved.cover(text, own: naming.count), true)
    }

    struct Row {
        var food: Food
        var text: FoodText
        var match: Coverage
        /// The catalog's other name for the food that matched, when its own name matched less.
        var other: FoodText?
        var mine: Bool
        /// The brand is the one asked for and no longer: Papa John's, not Papa John's Salads & Produce.
        var exact: Bool
        /// With no brand read from the whole search, the search names this food's brand word for word.
        var own: Bool
        /// The brand's food named by exactly the words said.
        var said: Bool
        var name: Double
        var like: Double
        var plausible: Bool
    }
    let isForm = { (word: String, form: String) in isNumber(form) ? word == form : starts(word, form) }
    var rows: [Row] = []
    rows.reserveCapacity(keys.count)
    for key in keys {
        let entry = unique[key]!
        let food = entry.food
        let text = entry.text
        var (match, own) = fit(text, misspelt: false)
        // A food is also found by a chain's name for it ("mcnuggets" finds chicken nuggets from
        // fast food), when that name says more of what was asked than its own and names what was asked.
        var other: FoodText?
        if match.name < 1 {
            for name in entry.also where mentionForms.contains(where: { $0.contains { starts(name.head, $0) } }) {
                let named = query.cover(name.text)
                if named.name > match.name {
                    match = named
                    other = name.text
                }
            }
        }
        // Only then a misspelling of the food's own words, which a typo's usual meaning or a
        // chain's name for the food would otherwise explain: "mcmuffin" isn't a muffin misspelt.
        if match.name < 1, lenient != nil {
            let loose = fit(text, misspelt: true)
            if loose.match.name > match.name {
                (match, own) = loose
                other = nil
            }
        }
        let mine: Bool
        var exact = false
        if asked {
            // The brand asked for: each of its words starts a word of the food's brand.
            mine =
                !text.own.isEmpty
                && brandForms.allSatisfy { options in
                    options.contains { form in form.allSatisfy { part in text.own.contains { isForm($0, part) } } }
                }
            // Word for word: "Poptart" starts with "pop", but isn't the brand Pop.
            exact = mine && text.own.allSatisfy { word in brandParts.contains { same(word, $0) } }
        } else {
            mine = match.brand == true
        }
        // A search for a brand alone matches all of its foods.
        let name = alone && mine ? 1 : match.name
        // The brand's food named by exactly the words said is the food asked for, whatever foods of
        // that name are usually like: Trader Joe's "Chocolate Bar" for its chocolate bar, though it
        // is darker than most.
        let said = mine && name == 1 && match.others == 0 && match.variations == 0
        rows.append(
            Row(
                food: food, text: text, match: match, other: other, mine: mine, exact: exact, own: own, said: said, name: name,
                like: hints.profile.map { said ? 1 : likeness(food, $0) } ?? 0, plausible: entry.plausible))
    }
    let sold = rows.contains { $0.mine && $0.name == 1 && $0.like > 0 }
    // A brand that makes nothing like what the other words usually name means its own food by
    // them: Papa John's pepperoni is its pizza, not sliced pepperoni, and Tillamook's cheddar is
    // cheese, not crackers. One that does is read by the profile: Trader Joe's Mini-Wheats are its
    // shredded wheat, not its mini wheat pitas.
    let makesKind = rows.contains { $0.mine && $0.like > 0 }
    // What USDA files a food under, when it isn't under its own name: among the plain foods with
    // every word of a search, a word that half of them have before the word naming the food.
    // "Beef" for a steak, "Salad dressing" for mayonnaise, "Squash, summer" for zucchini, "Snacks"
    // for potato chips. It isn't held against a food, and a name with nothing else before the
    // food leads with it as "Fish, salmon" does.
    var shelf = Set<String>()
    if search {
        let family = rows.filter { $0.match.missing == 0 && !$0.text.branded }
        if family.count >= 5 {
            var foods: [String: Int] = [:]
            // Not a brand USDA has many foods of, which it writes in capitals.
            for row in family { for word in Set(row.match.filed) where !row.text.shouted.contains(word) { foods[word, default: 0] += 1 } }
            shelf = Set(foods.filter { 2 * $0.value >= family.count }.keys)
        }
    }
    var ranked: [Ranked] = []
    for (index, row) in rows.enumerated() where row.name > 0 {
        let match = row.match
        var filedUnder = 0.0
        var leads = match.leads
        if !shelf.isEmpty && !row.text.branded && !match.filed.isEmpty {
            for word in match.filed where shelf.contains(word) {
                filedUnder += variationWords.contains(word) ? (insteadWords.contains(word) ? 1.2 : 0.8) : 0.25
            }
            if match.missing == 0 && match.filed.allSatisfy(shelf.contains) { leads = true }
        }
        let theirs = asked && row.mine && row.name == 1 && !makesKind
        let like = theirs ? max(0, row.like) : row.like
        var score =
            3 * row.name + (leads ? (search ? 0.75 : 0.5) : 0)
            // A generic food USDA names by exactly the words said, inverted, ranks above a blend or
            // dish that only has them.
            + (match.named && !row.text.branded ? 0.5 : 0)
            // A food not usually cooked is the raw one, between two that match as well.
            + (cooked ? 0.4 * Double(match.cooked) - (match.fried ? 0.2 : 0) : match.cooked < 0 ? 0.1 : 0)
            // The brand's food named by exactly the words said is as usual as its kind that says
            // so (Great Value's "Cottage Cheese Small Curd" beside its lowfat one), and "typical"
            // is USDA's word for its own entries: a label's "Original" is another product.
            + (match.usual || (row.said && query.asksUsual) ? 0.6 : 0) + (match.typical && !row.text.branded ? 0.3 : 0)
            - 0.5 * Double(match.partial) - 0.4 * Double(match.fixed) - 0.8 * match.variations
            // A note in brackets says more about the same food, however long it is.
            - 0.25 * Double(match.others) - min(0.1, 0.05 * Double(match.notes)) + filedUnder
            // A food found by another name ranks a little below one its own name matches as well.
            - (row.other == nil ? 0 : 0.5)
            // A food named after the one asked for: cake pretzels and cake fries for "cake". Not a
            // brand's own food by those words when it makes nothing like the food: Papa John's
            // pepperoni is its pepperoni pizza.
            - (match.modifies && !theirs ? 1 : 0)
        // Every food of a brand searched for alone answers it as well as any other.
        if alone && row.mine { score = 3 }
        if asked {
            // The brand asked for; then other brands' products, among them the one the search is
            // usually named after ("Kellogg's Mini-Wheats"); then plain foods.
            if row.mine {
                score += (theirs ? 3 : 1.5) + (row.exact ? 0.5 : 0)
            } else if !row.text.branded {
                score -= 1
            }
        } else if let brand = match.brand {
            score += brand ? 2 : -1
        } else if row.text.branded {
            // A brand's words aren't counted as ones the search didn't ask for, so a packaged
            // food's markdown includes them.
            score -= 2.25
        }
        if let read {
            // Only when the food's own name has the word naming the food: Oreo's cookies for "oreo",
            // not the "Flat White" brand's coffee chocolate for "flat white".
            if row.own && match.head { score += 2 }
            if !read.counts.isEmpty || !read.sizes.isEmpty {
                let list = tokens("\(row.food.name) \(row.food.brand ?? "")")
                for (count, next) in read.counts where counted(list, count, next) { score += 2 }
                for size in read.sizes where sized(list, size) { score += 2 }
            }
        }
        // Like the kind of food named, and for the brand asked for, more so when it is named the
        // same kind of food: its "wheats" are its Mini-Wheats, its "mini pretzels" are not. A
        // brand that sells the food by the name searched for isn't searched for another name of it.
        let version = row.mine && match.head && (row.name == 1 || !sold)
        score += like + (version ? max(0, like) : 0)
        // The person's own foods move up only among foods that have every word said.
        if match.missing == 0 { score += boost(known, row.food.id) }
        // Among packaged foods, the ones people scan most: Coca-Cola before a store's cola.
        if hints.popularity { score += 0.12 * row.food.popularity }
        // Another country's product, as much as four words the search didn't ask for: it still
        // answers a search nothing sold here matches as well ("Domino's" in France or the US).
        if hints.away.contains(row.food.id) { score -= 1 }
        // Numbers that can't be right (kilojoules as calories, a powder's values on a drink) rank
        // below every plausible food that matches as well.
        if !row.plausible { score -= 1.5 }
        ranked.append(Ranked(food: row.food, score: score, index: index, name: row.name))
    }
    // A generic food found by a chain's name for it stands in for the chain's item, so the chain's
    // own comes just before it though no brand was typed: SR Legacy's McDonald's McNuggets, then
    // chicken nuggets from fast food; a Starbucks mocha Frappuccino, then a frozen mocha coffee
    // drink. The chain's own has the name's every word outside brackets, so a Big Mac "(without
    // Big Mac Sauce)" isn't Big Mac sauce.
    let isTheirs = { (row: Row, other: FoodText) in
        row.other == nil && row.name == 1 && !row.text.own.isEmpty
            && row.text.own.allSatisfy { w in other.titled.contains { same($0, w) } }
            && other.titled.allSatisfy { w in row.text.own.contains { same(w, $0) } || row.text.said.contains { same(w, $0) } }
    }
    if rows.contains(where: { $0.other != nil }) {
        for i in ranked.indices {
            guard let other = rows[ranked[i].index].other,
                let theirs = ranked.indices.filter({ isTheirs(rows[ranked[$0].index], other) }).max(by: { ranked[$0].score < ranked[$1].score })
            else { continue }
            if ranked[theirs].score <= ranked[i].score { ranked[theirs].score = ranked[i].score + 0.01 }
        }
    }
    ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
    return ranked
}

/// Whether a name has a number the search put before a food: "12 grain" in "12 Grain Bread".
private func counted(_ list: [String], _ count: String, _ next: String) -> Bool {
    let wanted = stem(next)
    return list.indices.contains { i in list[i] == count && starts(stem(i + 1 < list.count ? list[i + 1] : ""), wanted) }
}

/// Whether a name has a size the search asked for in inches: 14 in `PAPA JOHN'S 14" Pepperoni
/// Pizza`, "14 Inch Pepperoni Pizza" or "14in", not in "14 oz".
private func sized(_ list: [String], _ size: String) -> Bool {
    list.indices.contains { i in
        if list[i] == size { return i + 1 == list.count || !unitWords.contains(list[i + 1]) }
        return starts(list[i], size) && inchWords.contains(String(list[i].dropFirst(size.count)))
    }
}

/// Orders foods for a typed search; foods that don't match it are left out.
func rankSearch(_ query: String, _ foods: [Food], known: [String: Double] = [:], hints: RankHints = RankHints()) -> [Ranked] {
    scoreFoods(Named(name: query, brand: ""), foods, known: known, search: true, hints: hints)
}

func rankSearch(_ query: String, _ entries: [Entry], known: [String: Double] = [:], hints: RankHints = RankHints()) -> [Ranked] {
    scoreFoods(Named(name: query, brand: ""), entries, known: known, search: true, hints: hints)
}

/// Whether a food answers a typed search, for the person's own lists; see `QueryMatcher`.
func matchesQuery(_ query: String, _ food: Food, fixes: Fixes = [:]) -> Bool {
    QueryMatcher(query, fixes: fixes).matches(food)
}
