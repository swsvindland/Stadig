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
        + "broiled roasted grilled boiled steamed pan stir fried microwaved heated cured sliced chopped diced shredded mature seeds "
        + "without salt added drained solids liquid enriched unenriched white red yellow green brewed tap water ready serve "
        + "made broilers fluid fryers meat only flesh separable fish beverages alcoholic nuts crustaceans mollusks spices "
        // How it's sold, and what's added to an ordinary food to keep or fortify it: bagels "with
        // calcium propionate", tofu "prepared with calcium sulfate", juice "with added ascorbic acid".
        + "commercially bottled shelf stable unsweetened salted unsalted vitamin calcium propionate ca prop sulfate nigari "
        + "ascorbic acid potassium sodium magnesium chloride iron "
        // How a cut of meat is graded and trimmed. Not its fat, which USDA also lists as a food
        // ("Pork, fresh, separable fat").
        + "trimmed lean choice select prime grades boneless "
        // How a canned soup is made up, what a canned dish is called and how corn comes.
        + "equal volume entree kernel no")

/// Words that mark a less common form or part; the model should name these if it means them.
private let variationWords = stems(
    "powder dehydrated dried canned frozen unprepared imitation meatless substitute low reduced nonfat free fortified mix "
        + "flake concentrate baby infant toddler stick oil seed juice paste puree soup dry lite light diet sugar sweetened "
        + "blend spread flavored feet giblets liver gizzard heart neck back skin kidney tongue tripe glutinous "
        + "sprouted instant parboiled precooked turkey stewed babyfood product brain evaporated condensed melba rusk candied "
        + "vegetarian vegan veggie")

/// Words for a food made of something else or for a baby, a further step from the food than a
/// form of it: meatless meatballs aren't meatballs the way frozen ones are, nor a vegetarian
/// meatloaf a meatloaf, nor strained banana with mixed berries a bowl of mixed berries.
private let insteadWords = stems("meatless imitation substitute babyfood vegetarian vegan veggie")

/// Words a food is never just filed under.
private let notFiled = insteadWords.union(stems("baby infant toddler"))

/// Kinds of food named after what they're made with or taste of, which follow it in a packaged
/// food's name: cake pretzels, peanut butter cups, cheese crackers, chocolate milk. Forms already
/// in `variationWords` (oil, juice, powder) aren't repeated; words that also say what a food is like
/// ("thin", "strips", "balls") are left out.
private let formWords = stems(
    "bar bite chip crisp cracker pretzel fries fry cup pop puff roll muffin cookie cake bread sandwich wafer cluster "
        + "nugget crumb snack tender pie dip sauce dressing seasoning candy cereal granola drink shake smoothie creamer "
        + "popcorn ice gelato frosting filling pudding jam jelly butter batter yogurt milk water flour syrup bagel waffle "
        + "pancake biscuit brownie donut doughnut tart latte tea coffee salad burger wrap burrito taco pizza crust dough "
        + "noodle pasta broth sausage meatball dumpling bowl kit shell")

/// Words after which a name goes on to another part of the food: "cake with chocolate filling".
private let partWords: Set<String> = ["with", "and", "or", "in", "on", "filled", "topped", "dipped", "covered", "coated", "stuffed"]

/// How the catalog words the fat level a search names with a number: "2%" is reduced fat.
private let fatWords = stems("fat milkfat lowfat low reduced nonfat lean")

/// USDA's own markers for the typical entry among varieties: "Tomatoes, red, ripe, raw, year round
/// average", "Soymilk, original and vanilla".
private let typicalWords = stems("average varieties regular ripe original")

/// What a canned food is packed in.
private let packings = stems("oil water brine")

/// Words in a name's first part that say nothing of another food.
private let leadFillers = stems("made from ready eat")

/// The groups USDA files foods under, as words: no word a food of the group lacks, but one a
/// search can ask for.
private let groupWords = stems("fish nuts beverages crustaceans mollusks spices")

/// The most scanned brands of one word, as a typed word is compared with a brand's.
private let popularBrands = Set(PopularBrands.names.filter { !$0.contains(" ") }.map { bare(String($0.unicodeScalars.filter(isWordScalar))) })

/// And of more than one, as their words.
private let popularNames = Set(PopularBrands.names.filter { $0.contains(" ") }.map { words($0).map(bare).joined(separator: " ") })

/// What a label says of how a food was grown or made, which a plain food needn't say to be it.
private let fluffWords = stems("organic natural homemade fresh")

/// How a food is kept, which is how some foods always come: tomato paste is canned.
private let keptWords = stems("canned frozen dried dehydrated")

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
    "milk": Usual(
        ["whole"],
        ("skim nonfat reduced lowfat almond soy oat chocolate buttermilk coconut rice cashew hemp pea goat sheep condensed "
            + "evaporated powder powdered dry shake human malted").split(separator: " ").map(String.init)),
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
    // Typed alone, a meat is the cut most logged: ground beef, fresh pork and not ham, pork ribs.
    "beef": Usual(
        ["ground"],
        ("steak roast jerky stew corned liver broth stock rib ribs brisket tenderloin sirloin ribeye chuck round burger "
            + "frank frankfurter sausage bologna pot pie taco burrito soup noodle chili stroganoff tongue heart kidney tripe "
            + "tallow bouillon gravy").split(separator: " ").map(String.init)),
    "pork": Usual(
        ["fresh"],
        ("cured ham bacon sausage chop chops loin tenderloin rib ribs sparerib spareribs shoulder belly rind rinds skin skins "
            + "ground pulled barbecue bbq sweet sour bean beans").split(separator: " ").map(String.init)),
    "rib": Usual(["pork"], "beef short shortrib prime veal lamb eye bison".split(separator: " ").map(String.init)),
    // Cereal is the kind poured from a box, nuts are mixed nuts, pickles are dill and chili is
    // the dish with beans, not the pepper.
    "cereal": Usual(["ready"], "hot cooked bar oat oats oatmeal grits farina cream baby infant".split(separator: " ").map(String.init)),
    "nut": Usual(
        ["mixed"],
        ("butter almond walnut pecan cashew pistachio macadamia brazil hazelnut pine coconut chestnut ginkgo hickory "
            + "acorn beechnut butternut pili honey bar granola cereal trail").split(separator: " ").map(String.init)),
    "pickle": Usual(["dill"], "sweet sour relish bread butter beet egg herring pepper ginger okra onion".split(separator: " ").map(String.init)),
    "chili": Usual(
        ["bean", "carne"],
        "pepper peppers powder sauce hot sweet paste flake flakes oil dog fries cheese seasoning lime green red verde"
            .split(separator: " ").map(String.init)),
    // Tuna, sardines and anchovies come out of a can; soup and stew mostly do.
    "tuna": Usual(
        ["canned"],
        "fresh steak bluefin yellowfin skipjack ahi salad seared raw sushi sashimi roll melt casserole noodle helper"
            .split(separator: " ").map(String.init)),
    "sardine": Usual(["canned"], ["fresh", "raw"]),
    "anchov": Usual(["canned"], ["fresh", "raw", "paste"]),
    "soup": Usual(["canned"], "dry mix dehydrated homemade home stock broth bouillon cube powder ramen".split(separator: " ").map(String.init)),
    "stew": Usual(["canned"], ["chuck", "meat", "raw"]),
    // A dish by its usual filling, not the sauce, shell or chips named after it.
    "lasagna": Usual(["meat"], "vegetable cheese spinach noodle noodles sheets".split(separator: " ").map(String.init)),
    "enchilada": Usual(["cheese"], ["sauce", "seasoning", "kit"]),
    "taco": Usual(["beef"], "shell shells salad seasoning sauce kit chip chips flavor".split(separator: " ").map(String.init)),
    "nacho": Usual(["fast"], "chip chips flavor tortilla sauce dip".split(separator: " ").map(String.init)),
    "cornbread": Usual(["recipe"], ["mix", "stuffing"]),
    // Goat cheese is the soft kind; goat's milk and meat are themselves.
    "goat": Usual(["soft"], ["milk", "meat", "roasted", "raw"]),
    // A kind of food typed alone is the one of its kind most logged: orange juice, olive oil,
    // heavy cream, maple syrup, a white fish, a green salad, a turkey sandwich, mixed
    // vegetables, apple pie, chocolate chip cookies, saltines, ranch dressing, pasta sauce.
    "juice": Usual(
        ["orange"],
        "apple grape cranberry lemon lime tomato carrot pineapple grapefruit prune vegetable pomegranate cherry clam pickle".split(separator: " ")
            .map(String.init)),
    "oil": Usual(
        ["olive"],
        "canola vegetable coconut corn peanut sesame avocado sunflower safflower soybean palm fish cod flaxseed mct".split(separator: " ").map(
            String.init)),
    "cream": Usual(["heavy"], "ice sour whipped cheese light half coffee table coconut soup pie puff soda".split(separator: " ").map(String.init)),
    "syrup": Usual(["maple"], "chocolate corn pancake agave simple cane sorghum malt rice date fruit".split(separator: " ").map(String.init)),
    "fish": Usual(
        ["tilapia"],
        "tuna salmon cod oil sauce stick sticks taco tacos fillet sandwich cake cakes fried chips gefilte roe".split(separator: " ").map(String.init)),
    "salad": Usual(
        ["lettuce"],
        "tuna chicken egg potato pasta macaroni fruit caesar greek cobb taco bean dressing seafood crab shrimp ham turkey kit".split(separator: " ")
            .map(String.init)),
    "sandwich": Usual(
        ["turkey"],
        "ham chicken club tuna egg cheese ice cream cookie cookies breakfast fish steak beef pork peanut butter bread spread cracker crackers".split(
            separator: " "
        ).map(String.init)),
    "vegetable": Usual(
        ["mixed"], "oil juice soup broth stock shortening spread burger burgers chips beef protein".split(separator: " ").map(String.init)),
    "pie": Usual(
        ["apple"],
        "pumpkin cherry pecan chicken pot shepherd shepherds crust filling blueberry lemon peach cream chocolate lime pizza".split(separator: " ")
            .map(String.init)),
    "cookie": Usual(
        ["chocolate"],
        "sandwich oatmeal sugar peanut butter fortune ginger gingersnap shortbread wafer dough mix".split(separator: " ").map(String.init)),
    "cracker": Usual(
        ["saltine"], "cheese graham animal rice wheat whole rye oyster sandwich peanut butter matzo".split(separator: " ").map(String.init)),
    "dressing": Usual(
        ["ranch"],
        "italian caesar french thousand island blue cheese vinaigrette honey mustard russian sesame mayonnaise mayo balsamic oil vinegar bacon".split(
            separator: " "
        ).map(String.init)),
    "sauce": Usual(
        ["pasta"],
        "soy hot bbq barbecue tomato alfredo cheese fish oyster teriyaki worcestershire tartar cocktail hoisin chili pepper cranberry apple steak pizza enchilada taco sweet sour duck plum peanut hollandaise white brown meat buffalo"
            .split(separator: " ").map(String.init)),
]

/// The same for foods of two words, read before either word's own: tomato sauce, tomato paste
/// and condensed milk come canned, and an egg roll is the filled one, not a dinner roll with egg.
private let usualPhrases: [(words: [String], usual: Usual)] = [
    ("tomato sauce", Usual(["canned"], ["chili", "pasta", "spaghetti", "marinara"])),
    ("tomato paste", Usual(["canned"], [])),
    ("condensed milk", Usual(["canned", "sweetened"], [])),
    // Ground meat sold as lean is 93% lean, and as extra lean 95% or more; every kind USDA
    // lists says how lean it is.
    ("extra lean", Usual(["95", "96", "97"], [])),
    ("lean ground", Usual(["93"], [])),
    ("egg roll", Usual(["pork", "vegetable", "chicken", "assorted"], ["dinner"])),
].map { ($0.0.split(separator: " ").map { stem(String($0)) }, $0.1) }

/// Searches and seen foods naming these mean the cooked food unless they say "raw": "salmon",
/// "rice", "chicken", the beans in a burrito bowl, a bowl of oatmeal.
private let eatenCooked = stems(
    "rice pasta noodle spaghetti macaroni quinoa lentil oatmeal porridge chicken beef pork turkey lamb steak bacon sausage "
        + "salmon fish tuna cod tilapia shrimp egg potato bean chickpea barley couscous bulgur farro millet grits polenta "
        + "duck goose veal bison venison ribeye sirloin brisket tenderloin crab lobster scallop trout halibut catfish haddock "
        + "rib sparerib backrib roast")
private let cookedWords = stems("cooked roasted baked boiled broiled grilled steamed poached scrambled fried braised microwaved")

/// How a food is cooked: with dry heat, in water or steam, or in fat.
enum Heat: Sendable { case dry, moist, fat }

/// The ways of cooking, by kind. USDA lists a cooked food one or two ways ("Broccoli, cooked,
/// boiled", "Fish, salmon, …, cooked, dry heat"), so a way it doesn't list for a food is read as
/// the nearest way it does (see `Ease`).
let heats: [String: Heat] = {
    var kinds: [String: Heat] = [:]
    for word in stems("roasted roast baked broiled grilled seared rotisserie barbecued chargrilled toasted browned") { kinds[word] = .dry }
    for word in stems("boiled steamed poached braised stewed simmered microwaved blanched") { kinds[word] = .moist }
    for word in stems("fried sauteed") { kinds[word] = .fat }
    return kinds
}()

/// How a food is cut, or how young it was picked, which USDA mostly leaves unsaid: a salmon
/// fillet is its salmon, broccoli florets its broccoli and baby spinach its spinach. Not "diced"
/// or "sliced", which more often name what's sold in a can.
private let cutWords = stems("fillet filet slice piece chunk floret spear halves stalk clove cutlet baby")

/// What a food said to be trimmed mustn't have: "skinless" chicken is USDA's "meat only", not its
/// "meat and skin".
private let trimWords = ["skinless": "skin", "boneless": "bone"]

/// Said of a food that isn't cooked, which USDA often leaves unsaid too: raw almonds are its
/// "Nuts, almonds".
private let rawWords = stems("raw fresh uncooked")

/// Whether a word says how a food is cooked or cut, not what it is.
func isEasable(_ word: String) -> Bool {
    let said = stem(word)
    return heats[said] != nil || cutWords.contains(said) || trimWords[said] != nil || rawWords.contains(said)
}

/// Whether a word says how a food is cooked.
func isHeat(_ word: String) -> Bool { heats[stem(word)] != nil }

/// A word said that a food needn't have to be the food asked for, because no plain food with
/// the other words has it: "steamed" where USDA's broccoli is only "cooked, boiled", "fillet"
/// where its salmon is just salmon.
struct Ease {
    /// For a way of cooking, its kind: any cooked food will do, the same kind first. Fried food
    /// is only ever what "fried" or "sauteed" means, and "fried" means nothing else.
    var heat: Heat?
    var fried = false
    /// A word the food mustn't have.
    var unless: String?
    /// The word says the food isn't cooked.
    var raw = false
    /// No food is spared the word: some plain food lists it, or none comes near it. Then it
    /// says which food is meant, and a food without it lacks it, though it's a word for how a
    /// food comes: fried rice isn't USDA's plain cooked rice, nor fresh mozzarella its block.
    var listed = false

    init(_ said: String, listed: Bool = false) {
        heat = heats[said]
        fried = said == "fried"
        unless = trimWords[said]
        raw = rawWords.contains(said)
        self.listed = listed
    }

    /// Whether a food is one the word needn't be said of.
    func fits(_ text: FoodText) -> Bool {
        if listed { return false }
        if let unless, text.all.contains(unless) { return false }
        if raw { return !text.cooking.cooked && !text.titled.contains(where: keptWords.contains) }
        guard let heat else { return true }
        let cooking = text.cooking
        guard cooking.cooked else { return false }
        return heat == .fat ? !fried || cooking.kinds.contains(.fat) : cooking.kinds != [.fat]
    }

    /// How much nearer a food cooked the same kind of way is than one cooked another way, and
    /// that than one that only says "cooked": USDA's own cooked entry says how, and one that
    /// doesn't is a variety's or a restaurant's.
    func nearness(_ text: FoodText) -> Double {
        guard let heat else { return 0 }
        let kinds = text.cooking.kinds
        return kinds.contains(heat) ? 0.3 : kinds.isEmpty ? 0 : 0.1
    }
}

/// The cooked words in the catalog's full-text syntax, as prefixes.
private let cookedTerm =
    "("
    + "cooked roasted baked boiled broiled grilled steamed poached scrambled braised microwaved"
    .split(separator: " ").map { "\"\($0)\"*" }.joined(separator: " OR ") + ")"

/// The same for a search that says how the food is cooked, which a fried food may answer too.
let heatedTerm =
    "("
    + "cooked roasted baked boiled broiled grilled steamed poached braised stewed microwaved toasted fried sauteed"
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
    /// The runs that start with "with": what the food comes with, not what it is.
    let served: Set<Int>
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
    /// The group USDA files it under, when it does, stemmed: "nut" for "Nuts, almonds".
    let group: [String]
    /// Its brand is a chain or a maker USDA writes first in capitals, not a label's brand field.
    let chain: Bool
    /// A restaurant or packaged food.
    let branded: Bool
    /// USDA's "dry heat" or "moist heat", which the words read as "cooked".
    let heat: Heat?

    /// How the name says the food was cooked, and whether it says it was cooked at all.
    var cooking: (kinds: Set<Heat>, cooked: Bool) {
        var kinds = Set<Heat>()
        if let heat { kinds.insert(heat) }
        var cooked = heat != nil
        for word in titled {
            if let kind = heats[word] {
                kinds.insert(kind)
                cooked = true
            } else if !cooked, cookedWords.contains(word) {
                cooked = true
            }
        }
        return (kinds, cooked)
    }

    init(_ food: Food) { self.init(name: food.name, brand: food.brand ?? "", source: food.source) }

    /// Reads the name once: its words, which are in brackets, and which comma-separated part each is in.
    init(name original: String, brand: String, source: FoodSource) {
        let heated = mentionsHeat(original)
        let name = heated ? cookedHeat(original) : original
        heat = !heated ? nil : original.range(of: "dry heat", options: .caseInsensitive) != nil ? .dry : name != original ? .moist : nil
        let scalars = plainScalars(name)
        let found = scanTokens(scalars)
        let close = scalars.lastIndex(of: ")") ?? -1
        // Each token's bracket (none, a note, or an "(Includes …)" note), comma-separated part and run.
        var placed: [(bracket: Int, part: Int, run: Int)] = []
        placed.reserveCapacity(found.count)
        var bracket = 0
        var part = 0
        var run = 0
        var served = Set<Int>()
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
                if partWords.contains(found[next].word) {
                    run += 1
                    if found[next].word == "with" { served.insert(run) }
                }
                placed.append((bracket, part, run))
                next += 1
            }
        }
        let stems = found.map { stopWords.contains($0.word) ? "" : stem($0.word) }
        // Plain ASCII text keeps its letters' places, so a word's capitals can be read back.
        var shouted: [String] = []
        if source == .usda, name.utf8.allSatisfy({ $0 < 0x80 }) {
            let bytes = Array(name.utf8)
            // Not in a note of what the entry includes: "(Includes foods for USDA's Food Distribution Program)".
            for (i, token) in found.enumerated() where !stems[i].isEmpty && token.end - token.start > 1 && placed[i].bracket != 2 {
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
            // "With skin", "without skin" and "baked in skin" say how a fruit or a potato comes,
            // not that the food is its skin, as "Chicken, skin only" is.
            if stems[i] == "skin", i > 0, ["with", "without", "in"].contains(found[i - 1].word) { continue }
            // "Dry roasted" is how nuts are cooked, not a dried food.
            if stems[i] == "dry", i + 1 < found.count, found[i + 1].word == "roasted" { continue }
            // Nor is what a food is packed in what it is: sardines "canned in oil" aren't an oil.
            if i > 1, found[i - 1].word == "in", found[i - 2].word == "canned" || found[i - 2].word == "packed", packings.contains(stems[i]) {
                continue
            }
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
        chain = brand.isEmpty && !ownWords.isEmpty
        let kept = own.isEmpty ? Array(said.indices) : said.indices.filter { !own.contains(said[$0]) }
        self.said = kept.map { said[$0] }
        self.runs = kept.map { runs[$0] }
        self.served = served
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
        group = grouped ? parts[0] : []
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
    /// The word is finished and is that word: never the start of a longer one.
    let finished: Bool

    /// `likely` is the whole word a half-typed one is probably on its way to: a food that has it
    /// has the word, not just a longer one that starts the same ("chees" is cheese before a
    /// cheeseburger).
    init(
        _ word: String, prefix: Bool, fixes: Fixes, doubted: Bool = false, respelt: Set<String> = [], likely: String? = nil,
        finished: Bool = false
    ) {
        self.word = word
        self.finished = finished
        var options = prefix ? searchForms(word) : forms(word)
        if let likely { for form in searchForms(likely) where !options.contains(form) { options.append(form) } }
        self.options = options
        self.fixes = fixes[word] ?? []
        fixParts = self.fixes.map { $0.split(separator: " ").map(String.init) }
        misspelling = doubted ? Misspelling(word) : nil
        self.respelt = self.fixes.filter(respelt.contains).map { $0.split(separator: " ").map(String.init) }
    }
}

/// How well a food's name covers what was said.
struct Coverage {
    var name: Double
    /// Words said that the food doesn't have, even as corrected, and how many of them say what
    /// the food is.
    var missing: Int
    var lacking: Int
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
    /// The words counted in `variations`.
    var forms: [String]
    /// Every word said is in one part of the name.
    var together: Bool
    /// What the food is named after instead, where a word said to describe it comes only in a
    /// later part of the name: "potato" for "egg salad" and "Potato salad with egg".
    var added: [String]
    /// The word naming the food is only in what this food comes with: the "cheese" of a chicken
    /// sandwich "with cheese".
    var garnish: Bool
    /// How near the food's way of cooking is to one said that it doesn't list (see `Ease`).
    var near: Double
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
    /// For each word, how a food may do without it; nil for a word every food asked for has.
    fileprivate let ease: [Ease?]

    init(
        seen: Named, target words: [String], prefix: Bool = false, fixes: Fixes = [:], nameOnly: Bool = false,
        doubted: Set<String> = [], respelt: Set<String> = [], eases: [String: Ease] = [:]
    ) {
        self.prefix = prefix
        self.nameOnly = nameOnly
        ease = eases.isEmpty ? [] : words.map { eases[$0] }
        // A typed search's last word may only be begun.
        let likely = prefix ? EverydayPhrases.likely(words) : nil
        target = words.enumerated().map { i, word in
            WordForms(
                word, prefix: prefix, fixes: fixes, doubted: doubted.contains(word), respelt: respelt, likely: i == words.count - 1 ? likely : nil,
                // An everyday food's own word with another typed after it is that word: the
                // "baby" of "baby spinach" isn't babyfood begun, nor the "egg" of "egg salad"
                // eggplant, the "grape" of "grape juice" grapefruit or the "ham" of "ham
                // sandwich" a hamburger. Not "mac", which people type for macaroni.
                // So is one typed alone, once it's whole: "curry" isn't currants begun. After
                // other words the last may still be half of one: the "oat" of "chobani extra
                // creamy oat" is on its way to Oatmilk.
                finished: prefix && word != "mac"
                    && (i < words.count - 1 ? EverydayPhrases.isWord(stem(word)) : words.count == 1 && EverydayPhrases.isWritten(word)))
        }
        var mentioned: [String] = []
        var entire: [String] = []
        for word in target {
            // A word as labels also write it is that word and no start of another: the "meat" of
            // "meat balls", for "meatballs", doesn't make "meatless" a word that was asked for.
            let whole =
                word.fixes.filter(respelt.contains).flatMap { $0.split(separator: " ").map(String.init) } + (word.finished ? word.options : [])
            for form in whole where !entire.contains(form) { entire.append(form) }
            let started =
                (word.finished ? [] : word.options)
                + word.fixes.filter { !respelt.contains($0) }.flatMap { $0.split(separator: " ").map(String.init) }
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
        // And a word with another spelling for the same as that one: "yoghurt" is yogurt.
        let asked = said + said.flatMap { alternatives[$0] ?? [] } + fixValues(fixes, order: said) + (likely.map { [$0] } ?? [])
        // A two-word food's, else the first word's that the others don't rule out: "beef stew" is
        // a stew, not ground beef.
        // Read through a word's one correction: "tomao paste" is tomato paste.
        var read = said.map { word in fixes[word].flatMap { $0.count == 1 && !$0[0].contains(" ") ? $0[0] : nil } ?? stem(word) }
        if let likely, !read.isEmpty { read[read.count - 1] = stem(likely) }
        let phrased = usualPhrases.first { phrase in
            read.indices.contains { $0 + phrase.words.count <= read.count && Array(read[$0..<($0 + phrase.words.count)]) == phrase.words }
        }
        self.usual =
            phrased.flatMap { asked.contains(where: $0.usual.others.contains) ? nil : $0.usual }
            ?? asked.lazy.compactMap { usualVarieties[stem($0)] }.first { usual in !asked.contains(where: usual.others.contains) }
    }

    init(seen: Named) { self.init(seen: seen, target: nameWords(seen.name)) }

    /// Whether the words name a food with an everyday variety.
    var asksUsual: Bool { usual != nil }

    /// The kinds the everyday variety isn't: beef and veal for ribs.
    var unusual: [String] { usual?.otherStems ?? [] }

    @inline(__always) private func fits(_ w: String, _ form: String) -> Bool {
        isNumber(form) ? w == form : same(w, form) || (prefix && length(form) > 1 && starts(w, form))
    }

    /// Whether one of a food's words is this one, as said or as its correction: the "mayonnaise"
    /// of "Salad dressing, mayonnaise" for "mayonnise".
    @inline(__always) private func reads(_ w: String, as word: WordForms) -> Bool {
        word.options.contains { word.finished ? same(w, $0) : fits(w, $0) } || word.fixParts.contains { $0.count == 1 && starts(w, $0[0]) }
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
        word.options.contains { form in found.contains { word.finished ? same($0, form) : exact($0, form) } }
            || word.respelt.contains { parts in parts.allSatisfy { part in found.contains { same($0, part) } } }
    }

    private func literal(_ word: WordForms, _ found: [String], whole: Bool) -> Bool {
        whole || (prefix && !word.finished && word.options.contains { form in found.contains { fits($0, form) } })
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
        prefix && !nameOnly && !word.options.contains { form in titled.contains { word.finished ? same($0, form) : fits($0, form) } }
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
        var lacking = 0
        var head = false
        // The words this food does without: a way of cooking near enough to its own, a cut it
        // leaves unsaid. The rest are read as if they were all that was said.
        // USDA leads with the food itself: "Tomatoes, red, ripe, raw", not "Canadian bacon".
        // "Soy sauce made from soy" leads with soy sauce too: how it's made says no other food.
        // So does "Cereals ready-to-eat" with cereal, and a group typed alone by its own name
        // leads every food in it: "nuts".
        let leads =
            (text.lead.contains(where: asked) && text.lead.allSatisfy { asked($0) || leadFillers.contains($0) })
            || (target.count == 1 && (text.group.first.map(asked) ?? false))
        var spared: [Bool] = []
        var near = 0.0
        // The kinds of heat said that this food is spared the word for.
        var heated = Set<Heat>()
        if !ease.isEmpty {
            let lacks = target.indices.map { ease[$0] != nil && !has(target[$0], found) }
            // "Raw" and "fresh" are only left unsaid by a food filed under what was asked:
            // fresh fruit isn't every raw food that has "fruit" in its name.
            spared = target.indices.map { lacks[$0] && ease[$0]?.fits(text) == true && (ease[$0]?.raw != true || leads) }
            for i in target.indices where spared[i] {
                near += ease[i]?.nearness(text) ?? 0
                if let kind = ease[i]?.heat { heated.insert(kind) }
            }
            // Otherwise it's no word a food lacks, as it only says how the food comes. A cut
            // already is one.
            for i in target.indices where lacks[i] && ease[i]?.listed == true {
                let said = stem(target[i].word)
                if neutral.contains(said) || fluffWords.contains(said) { lacking += 1 }
            }
            if !spared.contains(true) { spared = [] }
        }
        let naming = spared.isEmpty ? target.count - 1 : (spared.lastIndex(of: false) ?? target.count - 1)
        for (i, word) in target.enumerated() where spared.isEmpty || !spared[i] {
            // The last word names the food ("coffee" in "black coffee"); earlier words describe it.
            let weight = i == naming ? 2.0 : 1.0
            total += weight
            let isWhole = whole(word, found)
            let isLiteral = literal(word, found, whole: isWhole)
            let isFixed = !isLiteral && fixed(word, found)
            let has = isLiteral || isFixed
            let inBrand = has && i >= own && branded(word, text.titled)
            // A typed word naming the food that the name has only in what it "(includes …)" names
            // another food: a plain bagel that includes poppy seed ones isn't "pop".
            let aside =
                prefix && has && i == naming && !text.included.isEmpty && !self.has(word, text.said + text.noted + text.own)
            if has {
                hits += weight * (inBrand || aside ? 0.5 : 1)
            } else {
                missing += 1
                // A word that says what the food is, not how it comes ("fresh", "organic"). A
                // group USDA files foods under says what it is when it's said: fish and chips
                // aren't potato chips.
                let said = stem(word.word)
                if (!neutral.contains(said) && !fluffWords.contains(said)) || groupWords.contains(said) { lacking += 1 }
            }
            if !isWhole && isLiteral { partial += 1 }
            if isFixed { fixedCount += 1 }
            // The word that names the food is in its name: "wheats" in "Shredded Bite Size Wheats".
            if i == naming { head = has && !inBrand && !aside }
        }
        let needed = spared.isEmpty ? target : target.indices.filter { !spared[$0] }.map { target[$0] }
        var variations = 0.0
        var others = 0
        // Where the name last has the word naming the food, which is where it says what it is.
        let named = needed.last.flatMap { last in text.said.lastIndex { reads($0, as: last) } }
        var filed: [String] = []
        // The ones of those in the same part of the name as the word naming the food, which
        // name it after another: the "potato" of "Potato salad with egg".
        var beside: [String] = []
        var forms: [String] = []
        // USDA's "mature seeds" are dried beans and lentils as usually cooked, not the seeds of a plant.
        let legume = text.said.contains("mature") || text.said.contains("immature")
        for (i, w) in text.said.enumerated() where !isNumber(w) && !(level && fatWords.contains(w)) && !asked(w) {
            if w == "seed" && legume { continue }
            // Nor is the food's own way of cooking, the same kind as the one said, a less common
            // form of it: stewed chicken for "boiled chicken".
            if variationWords.contains(w), let kind = heats[w], heated.contains(kind) { continue }
            // The usual kind's own word isn't one that wasn't asked for: tuna is canned, nuts are mixed.
            if let usual = self.usual, usual.markStems.contains(w) { continue }
            if variationWords.contains(w) {
                // As far off as a label's food is from a plain one: the real thing by any brand comes first.
                variations += insteadWords.contains(w) ? 3 : 1
                forms.append(w)
            } else if !neutral.contains(w) {
                others += 1
            } else {
                continue
            }
            if let named, i < named {
                filed.append(w)
                if text.runs[i] == text.runs[named], !variationWords.contains(w) { beside.append(w) }
            }
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
        // Whether the name has the words in one part of it: "Nuts, coconut milk" for "coconut
        // milk", where a coconut cream pudding "prepared with whole milk" has both and is neither.
        var together = false
        var added: [String] = []
        if needed.count > 1, missing == 0 {
            let places = needed.map { word in text.said.indices.filter { reads(text.said[$0], as: word) } }
            if let first = places.first {
                together = first.contains { at in places.allSatisfy { $0.contains { text.runs[$0] == text.runs[at] } } }
            }
            // A word describing the food comes only in a later part than the food's own, which
            // is named after something else: the "egg" of "Potato salad with egg".
            if let named, places.dropLast().contains(where: { found in !found.isEmpty && found.allSatisfy { text.runs[$0] > text.runs[named] } }) {
                added = beside
            }
        } else if target.count > 1, missing == 0 {
            // One word of several is all this food needs, and it has it.
            together = true
        }
        // The word naming the food is only in what the food comes with, and its first part has
        // nothing that was said: a "Chicken fillet sandwich, grilled, …, with cheese" isn't
        // grilled cheese.
        var garnish = false
        if missing == 0, !text.served.isEmpty, let last = needed.last, let first = text.runs.first {
            let places = text.said.indices.filter { reads(text.said[$0], as: last) }
            garnish =
                !places.isEmpty && places.allSatisfy { text.served.contains(text.runs[$0]) }
                && !text.said.indices.contains { text.runs[$0] == first && asked(text.said[$0]) }
        }
        // USDA's inverted name for exactly what was said: "Oil, olive" for olive oil, "Rice, white"
        // for white rice; not "Oil, corn, peanut, and olive", nor "Chicken breast, roll".
        var inverted = false
        if missing == 0, text.heads.count == 2 {
            let both = text.heads[0] + text.heads[1]
            // Of two words or more, the one naming the food is the one USDA puts first: "Milk,
            // chocolate" is chocolate milk, not milk chocolate.
            inverted =
                !needed.allSatisfy { has($0, text.heads[0]) } && needed.allSatisfy { has($0, both) }
                && both.allSatisfy(asked) && (needed.count == 1 || (needed.last.map { has($0, text.heads[0]) } ?? false))
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
            lacking: lacking,
            named: inverted,
            partial: partial,
            head: head,
            modifies: modifies,
            fixed: fixedCount,
            usual: usual,
            typical: found.contains(where: typicalWords.contains),
            variations: variations,
            filed: filed,
            forms: forms,
            together: together,
            added: added,
            garnish: garnish,
            near: near,
            others: others,
            notes: notes,
            leads: leads,
            brand: brand.isEmpty ? nil : brand.allSatisfy { has($0, found) },
            // A food spared a way of cooking is a cooked one, however it says so: "stewed".
            cooked: found.contains(where: cookedWords.contains) || !heated.isEmpty ? 1 : found.contains("raw") ? -1 : 0,
            // Frying adds fat; roasted or boiled is the plainer cooked form.
            fried: found.contains("fried") && !mentioned.contains("fried") && !entire.contains("fried"))
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
    // Unless how it's cooked was said: "toast", "roasted almonds", "baked beans".
    let saidCooked = target.contains { cookedWords.contains(stem($0)) || stem($0) == "toast" }
    // The word being typed counts as the food it's most likely on its way to: "ground bee" is beef.
    let likely = search ? EverydayPhrases.likely(target) : nil
    let namedAfter = (likely ?? target.last).map { formWords.contains(stem($0)) && !eatenCooked.contains(stem($0)) } ?? false
    let cooked =
        !target.contains("raw") && !namedAfter
        && (target + target.flatMap { alternatives[$0] ?? [] } + fixValues(fixes, order: target) + (likely.map { [$0] } ?? [])).contains { word in
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
    // A way of cooking or a cut that no plain food with the other words lists is one the food
    // needn't say: USDA's broccoli is "cooked, boiled", so that is steamed broccoli, and its
    // salmon "cooked, dry heat" is baked salmon and a grilled salmon fillet. Not with a brand,
    // whose product is named as its label names it.
    var eases: [String: Ease] = [:]
    if !asked, seen.brand.isEmpty, target.count > 1 {
        let easable = target.filter(isEasable)
        let rest = target.filter { !isEasable($0) }
        if !easable.isEmpty, !rest.isEmpty {
            // The other words are whole unless the last of them is the last typed: the "pot" of
            // "pot roast" isn't a potato begun.
            let others = CoverageQuery(
                seen: Named(name: rest.joined(separator: " "), brand: ""), target: rest, prefix: search && target.last == rest.last, fixes: fixes,
                respelt: hints.respelt)
            var having: [(text: FoodText, match: Coverage)] = []
            for entry in unique.values where !entry.text.branded {
                // As typed and whole: "fresh stacks" aren't fresh snacks.
                let match = others.cover(entry.text)
                if match.missing == 0, match.fixed == 0, match.partial == 0, !match.modifies { having.append((entry.text, match)) }
            }
            // The foods filed under those words, by the name's first part or by the word half of
            // them come after ("Squash, summer" for zucchini): a food is spared a word only
            // where one of these is, so grilled cheese isn't a cooked "Pizza, cheese topping".
            var before: [String: Int] = [:]
            for food in having { for word in Set(food.match.filed) { before[word, default: 0] += 1 } }
            let under = having.count >= 5 ? Set(before.filter { 2 * $0.value >= having.count }.keys) : []
            let plain = having.map { food in
                (
                    text: food.text, varied: food.match.variations > 0,
                    leads: food.match.leads || (!food.match.filed.isEmpty && food.match.filed.allSatisfy(under.contains))
                )
            }
            for word in easable {
                let said = stem(word)
                let ease = Ease(said)
                // A plain food that lists it is the food meant, unless only a less common form
                // does: apple slices aren't USDA's "Apples, canned, sweetened, sliced", nor
                // roasted potatoes its "Potatoes, roasted, …, frozen, unprepared". Nor one filed
                // under more than was said, where a food filed under it will do: baked chicken
                // isn't a "Chicken wing, baked or broiled, from fast food".
                let listing = plain.filter { food in !food.varied && food.text.all.contains { same($0, said) || same(said, $0) } }
                let fits = plain.contains { $0.leads && ease.fits($0.text) }
                // Where no food is spared the word, it says which food is meant.
                eases[word] = fits && !listing.contains(where: \.leads) ? ease : Ease(said, listed: true)
            }
        }
    }
    let query = CoverageQuery(
        seen: seen, target: named.isEmpty ? target : named, prefix: search, fixes: fixes,
        nameOnly: asked && !named.isEmpty, respelt: hints.respelt, eases: eases)
    // The same, also reading a word the catalogs barely know as a food's own word misspelt.
    let lenient =
        hints.doubted.isEmpty
        ? nil
        : CoverageQuery(
            seen: seen, target: named.isEmpty ? target : named, prefix: search, fixes: fixes,
            nameOnly: asked && !named.isEmpty, doubted: hints.doubted, respelt: hints.respelt, eases: eases)
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
    // Whether a plain food has every word said, worked out when a food's brand first asks. Not
    // by a brand USDA names in capitals inside a plain food's name ("Yogurt, Greek, plain, CHOBANI").
    var plainlyNamed: [Bool: Bool] = [:]
    func isPlainlyNamed(corrected: Bool = false) -> Bool {
        if let known = plainlyNamed[corrected] { return known }
        let said = target.map(stem)
        let found = unique.values.contains { entry in
            guard !entry.text.branded, !said.contains(where: { word in entry.text.shouted.contains { starts($0, word) } }) else { return false }
            // In its name, not a note of whose it is: "Cheeseburger (McDonalds)" is McDonald's.
            guard !said.contains(where: { word in entry.text.noted.contains { starts($0, word) } && !entry.text.said.contains { starts($0, word) } })
            else { return false }
            // As typed, not as a typo of it: "hers" isn't herring.
            let match = query.cover(entry.text)
            return match.missing == 0 && (corrected || match.fixed == 0)
        }
        plainlyNamed[corrected] = found
        return found
    }

    /// How a food covers what was said, and whether a search with no brand of its own names the
    /// food's brand. A food whose brand the search names word for word reads those words as its
    /// brand wherever they were typed, so the word naming the food is the last of the others:
    /// "cheese", not "cow", in "cottage cheese honest cow" for The Honest Cow's cottage cheese.
    /// With `misspelt`, a word the catalogs barely know is also one of the food's own words a typo
    /// or two from it, which names a brand too: "gali" for Galli's roasted chestnuts.
    func fit(_ text: FoodText, misspelt: Bool) -> (match: Coverage, own: Bool, only: Int) {
        let whole = misspelt ? lenient ?? query : query
        guard search, !asked, last >= 0, !text.own.isEmpty else { return (whole.cover(text), false, 0) }
        // Word for word, a plural or possessive apart: "wheats" isn't the brand Wheaty, though
        // they share a stem. Each of the brand's words takes one word said, so the "eggs" of "egg
        // land best brown eggs" still name the food; two said as one ("membermark") take it
        // together, and after a food the last word may be as far as the brand is typed ("oats
        // kas"; "pop" alone is on its way to popcorn as much as to Popchips).
        var naming: [Int] = []
        var halfTyped = false
        // Every word is the brand's as typed, not as corrected.
        var asTyped = true
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
            // Not a word the food's own name has, or an everyday food's: the "bread" of "sourdough
            // bread" isn't Breadsmith begun, nor the "bar" of "protein bar" Barilla, nor the
            // "clove" of "garlic clove" Clover Valley. Unless it was typed twice: "sparkling water
            // water" is on its way to Waterloo.
            if named == nil, !naming.contains(last), !typedBare[last].isEmpty, starts(written, target[last]),
                target.dropLast().contains(target[last])
                    || (!text.said.contains(stem(target[last])) && !EverydayPhrases.isWord(stem(target[last])) && !isEasable(target[last]))
            {
                named = last
                halfTyped = true
            }
            guard let named else { return (whole.cover(text), false, 0) }
            if !halfTyped, typedBare[named] != word { asTyped = false }
            if !naming.contains(named) { naming.append(named) }
        }
        // A one-word brand isn't one the search names when a plain food has every word typed:
        // chia seeds listed under "Seeds", American cheese under "american" and cherry tomatoes
        // under "Cherry" are no brand's. Typed whole, that is ("water" is on its way to
        // Waterloo), and "high protein supersnack edamame" is still the Supersnack listed under
        // "Edamame", which no plain food is.
        // A brand people scan is one, whatever plain food has its word (Goldfish, Post, Kraft),
        // and so is a chain USDA names: this is about what labels put in their brand field.
        // Nor is an everyday food's own word a brand, whoever lists a food under it: "oat milk"
        // isn't the oat milk of a label that gives "milk" as its brand.
        if text.ownWords.count == 1, !halfTyped, !text.chain, !popularBrands.contains(bare(text.ownWords[0])),
            EverydayPhrases.isWord(text.own[0]) || isPlainlyNamed(corrected: true)
        {
            return (whole.cover(text), false, 0)
        }
        // The same for a brand of several words, where a plain food has them all: chow mein
        // isn't the one a label lists under "Chow Mein".
        if text.ownWords.count > 1, !halfTyped, !text.chain, !popularNames.contains(text.ownWords.map(bare).joined(separator: " ")),
            isPlainlyNamed(corrected: true)
        {
            return (whole.cover(text), false, 0)
        }
        // Nothing typed but the food's brand: it's one of that brand's foods, whatever it's called.
        // Half typed, only when the letters aren't on their way to an everyday food.
        // Not when a plain food has every word: then the search names a food, and a label that
        // lists it under its own name ("Cottage cheese" by "Cottage cheese") is no brand.
        // And only for one word: more are read as a brand from the whole search, or name a
        // product ("belvita snack packs" isn't whatever is listed under "belVita SNACK PACKS").
        if naming.count == target.count {
            // Nor for a word read as the brand misspelt: "yogrt" is yogurt before a label listed under "Yogurt".
            if target.count > 1 || !asTyped || (halfTyped && likely != nil) || isPlainlyNamed() { return (whole.cover(text), !halfTyped, 0) }
            return (whole.cover(text, own: target.count), !halfTyped, halfTyped ? 1 : 2)
        }
        naming.sort()
        if let known = misspelt ? reorderedLenient[naming] : reordered[naming] { return (known.cover(text, own: naming.count), true, 0) }
        let order = naming + target.indices.filter { !naming.contains($0) }
        let moved = CoverageQuery(
            seen: seen, target: order.map { target[$0] }, prefix: true, fixes: fixes, doubted: misspelt ? hints.doubted : [],
            respelt: hints.respelt, eases: eases)
        if misspelt { reorderedLenient[naming] = moved } else { reordered[naming] = moved }
        return (moved.cover(text, own: naming.count), true, 0)
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
        /// The search is nothing but this food's brand: 2 typed whole, 1 half typed.
        var only: Int
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
        var (match, own, only) = fit(text, misspelt: false)
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
                (match, own, only) = loose
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
                food: food, text: text, match: match, other: other, mine: mine, exact: exact, own: own, only: only, said: said, name: name,
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
    // food leads with it as "Fish, salmon" does. For a food a model saw as for a typed search:
    // its "sirloin" is beef before veal.
    var shelf = Set<String>()
    do {
        // The foods that have the words whole, where the last is still being typed and enough
        // do: "ch" on its way to chicken is filed as chicken is.
        let every = rows.filter { $0.match.missing == 0 && !$0.text.branded }
        // Of several words, the foods that have them in one part of the name: a coconut cream
        // pudding "prepared with whole milk" isn't a coconut milk.
        let one = every.filter { $0.match.together }
        let having = target.count > 1 && one.count >= 3 ? one : every
        let whole = having.filter { $0.match.partial == 0 }
        let family = whole.count >= 5 ? whole : having
        if family.count >= 5 {
            var foods: [String: Int] = [:]
            // Not a brand USDA has many foods of, which it writes in capitals.
            for row in family { for word in Set(row.match.filed) where !row.text.shouted.contains(word) { foods[word, default: 0] += 1 } }
            shelf = Set(foods.filter { 2 * $0.value >= family.count }.keys)
        }
        // And the form most of them come in is the form the food comes in: tomato sauce and
        // tomato paste are canned, so "canned" isn't a less common kind of either.
        if family.count >= 3 {
            var foods: [String: Int] = [:]
            for row in family { for word in Set(row.match.forms) where keptWords.contains(word) { foods[word, default: 0] += 1 } }
            shelf.formUnion(foods.filter { 3 * $0.value >= 2 * family.count }.keys)
        }
        // Never a kind the everyday variety isn't: most ribs USDA lists are beef, and ribs are still
        // pork. Nor a food made for babies or of something else, however many of those USDA lists:
        // applesauce isn't filed under "Babyfood".
        shelf.subtract(query.unusual)
        shelf.subtract(notFiled)
    }
    // Some food sold here has every word said, in its name or as its brand read whole: not a
    // word that only happens to be in a brand ("cottage cheese honest" isn't The Honest Cow's yet).
    let complete = rows.contains { $0.match.missing == 0 && $0.match.name == 1 && !hints.away.contains($0.food.id) }
    // A food people look for has every word as typed: a correction of one is then a long shot.
    // "spam" is Spam, though the catalogs know "spa…" better; "brocoli" is still broccoli,
    // which only labels sold elsewhere and scanned by no one spell that way.
    // Only where the correction is the word cut short, which is no typo's reading: "protien"
    // is still protein, whatever a label or two spell that way.
    let literal =
        search && target.contains { word in (fixes[word] ?? []).contains { $0 != word && word.hasPrefix($0) } }
        && rows.contains { row in
            row.match.missing == 0 && row.match.fixed == 0 && row.match.partial == 0 && !hints.away.contains(row.food.id)
                && (!row.text.branded || row.food.popularity >= 1.5)
        }
    let saidStems = target.map(stem)
    // What's eaten cooked is still the raw food where the catalog lists no cooked one: egg
    // whites are USDA's "Egg, white, raw, fresh", which it has no cooked entry for.
    let listsCooked = !cooked || rows.contains { !$0.text.branded && $0.match.lacking == 0 && $0.name > 0 && $0.match.cooked > 0 }
    // A food USDA lists with its brand in capitals is that brand's like any label's when what
    // was said is only its flavour: "Beverages, POWERADE, Zero, Mixed Berry" isn't mixed
    // berries. Not when the search names the brand, the food is filed under what was asked
    // ("Yogurt, Greek, plain, CHOBANI" is Greek yogurt) or the words are the brand's name for
    // it, which come right after the brand: "Candies, REESE'S Peanut Butter Cups".
    let isFlavour = { (text: FoodText) -> Bool in
        guard !text.shouted.isEmpty, let brand = text.said.lastIndex(where: text.shouted.contains) else { return false }
        let wasSaid = { (word: String) in saidStems.contains { starts(word, $0) } }
        if text.shouted.contains(where: wasSaid) { return false }
        // One word names a kind of food, which a brand's is only one of: "smoothie" isn't
        // "Beverages, V8 SPLASH Smoothies, Peach Mango".
        return saidStems.count == 1 || brand + 1 == text.said.count || !wasSaid(text.said[brand + 1])
    }
    var ranked: [Ranked] = []
    for (index, row) in rows.enumerated() where row.name > 0 {
        let match = row.match
        var filedUnder = 0.0
        var leads = match.leads
        if !shelf.isEmpty && !row.text.branded {
            for word in match.filed where shelf.contains(word) {
                filedUnder += variationWords.contains(word) ? (insteadWords.contains(word) ? 1.2 : 0.8) : 0.25
            }
            // A form counted wherever it comes in the name, once.
            for word in match.forms where shelf.contains(word) && !match.filed.contains(word) { filedUnder += 0.8 }
            if match.missing == 0 && !match.filed.isEmpty && match.filed.allSatisfy(shelf.contains) { leads = true }
        }
        let theirs = asked && row.mine && row.name == 1 && !makesKind
        let like = theirs ? max(0, row.like) : row.like
        var score =
            3 * row.name + (leads ? 0.75 : 0)
            // A generic food USDA names by exactly the words said, inverted, ranks above a blend or
            // dish that only has them.
            + (match.named && !row.text.branded ? 0.5 : 0)
            // A food not usually cooked is the raw one, between two that match as well, and its
            // cooked form is a kind of its own: roasted walnuts, cooked apples.
            + (cooked && listsCooked
                ? 0.4 * Double(match.cooked) - (match.fried ? 0.2 : 0) : match.cooked < 0 ? 0.1 : match.cooked > 0 && !saidCooked ? -0.3 : 0)
            // The brand's food named by exactly the words said is as usual as its kind that says
            // so (Great Value's "Cottage Cheese Small Curd" beside its lowfat one), and "typical"
            // is USDA's word for its own entries: a label's "Original" is another product.
            // Among foods with every word said, that is: plain white rice isn't the usual fried rice.
            // Nor a brand's that USDA names in capitals: "Sauce, barbecue" before "Sauce, barbecue,
            // KRAFT, original".
            + (match.missing > 0
                ? 0
                : (match.usual || (row.said && query.asksUsual) ? 0.6 : 0)
                    + (match.typical && !row.text.branded && row.text.shouted.isEmpty ? 0.3 : 0))
            // A longer word than the one being typed is likely on its way to counts a little more
            // against a food: "sal" is salmon before salsify.
            - (likely == nil ? 0.5 : 0.75) * Double(match.partial) - 0.4 * Double(match.fixed) - 0.8 * match.variations
            // A note in brackets says more about the same food, however long it is.
            - 0.25 * Double(match.others) - min(0.1, 0.05 * Double(match.notes)) + filedUnder + match.near
            // A food found by another name ranks a little below one its own name matches as well.
            - (row.other == nil ? 0 : 0.5)
            // A food named after the one asked for: cake pretzels and cake fries for "cake". Not a
            // brand's own food by those words when it makes nothing like the food: Papa John's
            // pepperoni is its pepperoni pizza.
            - (match.modifies && !theirs ? 1 : 0)
        // A plain food named after another food's word, with a word said only added to it, is
        // that other food with some of this in it: "Potato salad with egg" isn't an egg salad.
        // Not where the word before is only what the food is filed under.
        if !row.text.branded, !leads, match.garnish || match.added.contains(where: { !shelf.contains($0) }) { score -= 1.5 }
        // Every food of a brand searched for alone answers it as well as any other.
        if alone && row.mine { score = 3 }
        // Not half typed for a brand that isn't sold here: "dal" isn't Dallmayr's coffee begun.
        if row.only == 2 || (row.only == 1 && !hints.away.contains(row.food.id)) {
            // The same for a brand of one word, read from the food itself: "chobani" is Chobani's
            // foods, the most scanned first, not the ones that repeat the brand in their name.
            // Half typed, they come after a plain food that starts as typed: "her" is herring,
            // then Hershey's.
            // A chain's items as USDA analysed them come before what's sold under its name in shops.
            score = (row.only == 2 ? 5 : 3) + (row.food.source == .usda ? 0.5 : 0)
        } else if asked {
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
        } else if !leads, isFlavour(row.text) {
            score -= 2.25
        }
        if let read {
            // Only when the food's own name has the word naming the food: Oreo's cookies for "oreo",
            // not the "Flat White" brand's coffee chocolate for "flat white".
            if row.own && match.head && row.only == 0 { score += 2 }
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
        // A food that lacks a word said is another food where some food has them all: oat milk
        // isn't sheep's milk, nor a breakfast burrito a beef and bean one, nor "dolmas vine leaves
        // stuffed with rice" plain rice.
        // Not the asked brand's own food under another name: Trader Joe's Mini-Wheats are its
        // "Shredded Bite Size Wheats".
        if complete && !(asked && row.mine) { score -= 1.5 * Double(match.lacking) }
        if literal && match.fixed > 0 { score -= 2.5 }
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
