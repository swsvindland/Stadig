import Foundation

// Keyword matching shared by typed search and AI matching. The catalogs' full-text index has no
// stemming, so words are searched as stemmed prefixes and the results are ranked here.

/// Catalog words a typed word probably meant when the catalogs barely know it as typed:
/// "chiken" → ["chicken"], "peanutbutter" → ["peanut butter"]. Forms are stemmed like the word's.
typealias Fixes = [String: [String]]

let stopWords: Set<String> = ["a", "an", "and", "the", "of", "with", "in", "on", "or", "s", "to", "for", "style"]

/// Catalog wording differs from everyday names: USDA files burger buns under "Rolls, hamburger".
let alternatives: [String: [String]] = [
    "fries": ["fries", "fried"], "bun": ["bun", "roll"], "buns": ["bun", "roll"], "ketchup": ["ketchup", "catsup"],
    "soda": ["soda", "carbonated"], "pop": ["carbonated"], "strip": ["strip", "slice"], "strips": ["strip", "slice"],
    "oatmeal": ["oatmeal", "oat"], "burger": ["burger", "hamburger"], "burgers": ["burger", "hamburger"],
    "donut": ["donut", "doughnut"], "donuts": ["donut", "doughnut"],
    // USDA's skim milk is "Milk, nonfat", its Coke "cola". A model's "mayo" is mayonnaise; typed,
    // it is already the start of the word.
    "skim": ["skim", "nonfat"], "bbq": ["bbq", "barbecue"], "coke": ["coke", "cola"], "mayo": ["mayo", "mayonnaise"],
    // USDA's kiwi is "Kiwifruit".
    "kiwi": ["kiwi", "kiwifruit"], "kiwis": ["kiwi", "kiwifruit"],
    // Ribs are its spareribs and backribs.
    "rib": ["rib", "sparerib", "backrib"], "ribs": ["rib", "sparerib", "backrib"],
    // Unsalted butter and unsalted nuts are its "without salt".
    "unsalted": ["unsalted", "without"],
    // Other spellings, and what the same food is called in Britain.
    "omelette": ["omelette", "omelet"], "omelettes": ["omelette", "omelet"], "yoghurt": ["yoghurt", "yogurt"], "yoghurts": ["yoghurt", "yogurt"],
    "chilli": ["chilli", "chili"], "barbeque": ["barbeque", "barbecue"], "whisky": ["whisky", "whiskey"], "houmous": ["houmous", "hummus"],
    "soya": ["soya", "soy"], "skimmed": ["skimmed", "skim", "nonfat"], "prawn": ["prawn", "shrimp"], "prawns": ["prawn", "shrimp"],
    "courgette": ["courgette", "zucchini"], "courgettes": ["courgette", "zucchini"], "aubergine": ["aubergine", "eggplant"],
    "aubergines": ["aubergine", "eggplant"], "beetroot": ["beetroot", "beet"], "sweetcorn": ["sweetcorn", "corn"],
]

/// Dishes the catalog files under another name, as phrases a model says: USDA's spaghetti
/// bolognese is "spaghetti with meat sauce". Longest first.
let dishNames: [(said: [String], catalog: [String])] = [
    (["mac", "n", "cheese"], ["macaroni", "cheese"]),
    (["mac", "cheese"], ["macaroni", "cheese"]),
    (["spag", "bol"], ["spaghetti", "meat", "sauce"]),
    (["bolognese", "sauce"], ["meat", "sauce"]),
    (["bolognaise", "sauce"], ["meat", "sauce"]),
    (["bolognese"], ["meat", "sauce"]),
    (["bolognaise"], ["meat", "sauce"]),
    // How an egg is fried, and a soft-boiled one, which USDA lists hard-boiled.
    (["sunny", "side", "up"], ["fried"]),
    (["over", "easy"], ["fried"]),
    (["over", "medium"], ["fried"]),
    (["over", "hard"], ["fried"]),
    (["soft", "boiled"], ["hard", "boiled"]),
    // Corn on the cob is its cooked sweet corn.
    (["corn", "cob"], ["sweet", "corn", "cooked"]),
    // Toast of a kind of bread is that bread, toasted, which is how USDA lists it.
    (["sourdough", "toast"], ["sourdough", "bread", "toasted"]),
    (["rye", "toast"], ["rye", "bread", "toasted"]),
    (["multigrain", "toast"], ["multigrain", "bread", "toasted"]),
    // Iced coffee is its brewed coffee, poured over ice; its "iced" coffee is a bottled mocha.
    (["iced", "coffee"], ["brewed", "coffee"]),
]

/// A seen dish in the catalog's wording: "Spaghetti bolognese" → "spaghetti meat sauce".
func catalogDish(_ name: String) -> String {
    var list = words(name)
    var changed = false
    for (said, catalog) in dishNames {
        guard said.count <= list.count else { continue }
        var i = 0
        while i + said.count <= list.count {
            if Array(list[i..<(i + said.count)]) == said {
                list.replaceSubrange(i..<(i + said.count), with: catalog)
                i += catalog.count
                changed = true
            } else {
                i += 1
            }
        }
    }
    guard changed else { return name }
    // "Fried egg, sunny side up" is a fried egg, said once.
    var seen = Set<String>()
    return list.filter { seen.insert($0).inserted }.joined(separator: " ")
}

/// Everyday names of two words that the catalogs file under another: a hot dog is USDA's
/// frankfurter and a bell pepper its sweet pepper. For each, the words as typed, and the
/// catalogs' word for the one at each place; both are compared by their stems.
let everydayNames: [(said: [String], means: [(at: Int, word: String)])] =
    ([
        (["hot", "dog"], [(0, "frankfurter"), (1, "frankfurter")]),
        (["bell", "pepper"], [(0, "sweet")]),
        // Black coffee is USDA's brewed coffee, black olives its ripe ones, pumpkin puree its canned
        // pumpkin, and a sports drink is Gatorade, the only kind it lists.
        (["black", "coffee"], [(0, "brewed")]),
        (["black", "olive"], [(0, "ripe")]),
        (["pumpkin", "puree"], [(1, "canned")]),
        (["sport", "drink"], [(0, "gatorade"), (1, "gatorade")]),
        // "Fat free" is USDA's "nonfat", crunchy peanut butter its "chunk style" and creamy its
        // "smooth style".
        (["fat", "free"], [(0, "nonfat"), (1, "nonfat")]),
        (["crunchy", "peanut"], [(0, "chunk")]),
        (["creamy", "peanut"], [(0, "smooth")]),
        // Extra lean ground meat is its 95% lean.
        (["extra", "lean"], [(0, "95")]),
        // Monterey Jack is its "Cheese, monterey".
        (["monterey", "jack"], [(1, "monterey")]),
        // Jasmine and basmati rice are its white rice, which it lists cooked; a label's is the
        // dry rice in the bag.
        (["jasmine", "rice"], [(0, "white")]),
        (["basmati", "rice"], [(0, "white")]),
        // A tuna steak is its fresh tuna, not the canned; a burger patty its ground beef patty.
        (["tuna", "steak"], [(1, "fresh")]),
        (["hamburger", "patty"], [(0, "ground")]),
        (["burger", "patty"], [(0, "ground")]),
        // Cherry and grape tomatoes are its red ones.
        (["cherry", "tomato"], [(0, "red")]),
        (["grape", "tomato"], [(0, "red")]),
    ] as [([String], [(Int, String)])] + pastaShapes.map { ([$0, "pasta"], [(0, "pasta")]) }).map {
        (said: $0.0.map(stem), means: $0.1.map { (at: $0.0, word: stem($0.1)) })
    }

/// Shapes of pasta, which USDA lists only as "Pasta, cooked": alone or before "pasta" they're
/// that, where a label's penne is the dry pasta in the box. With another word they're a dish
/// ("fettuccine alfredo").
let pastaShapes = ["penne", "fusilli", "rigatoni", "linguine", "fettuccine", "farfalle", "rotini", "ziti", "orzo", "tagliatelle"]

/// The everyday names that stand for a plainer food only as they're written: a typo of
/// "jasmine" beside a brand is still that brand's jasmine rice, not its white.
let writtenNames: Set<String> = Set((["jasmine", "basmati"] + pastaShapes).map(stem))

/// Names that, typed alone, mean the food named after them, in the words USDA files it under:
/// "ranch" is its "Salad dressing, ranch dressing", "protein" its protein powder and "salad" its
/// "Lettuce, salad with assorted vegetables".
let aloneNames: [String: String] = ["ranch": "ranch salad dressing", "protein": "protein powder", "salad": "lettuce salad"]

/// What people type for a food instead of its name, as the whole of a search or of what a model
/// said, by its words: "pb&j" is "pb j".
let shortNames: [String: String] = [
    "pb j": "peanut butter and jelly", "pbj": "peanut butter and jelly", "pb and j": "peanut butter and jelly",
    "pb j sandwich": "peanut butter and jelly sandwich", "pbj sandwich": "peanut butter and jelly sandwich", "pb": "peanut butter",
    "oj": "orange juice", "evoo": "extra virgin olive oil",
    "sunny side up egg": "fried egg", "sunny side up eggs": "fried egg", "over easy egg": "fried egg", "over easy eggs": "fried egg",
    "corn on the cob": "sweet corn cooked",
]

/// Names that, typed alone, are also the word USDA files them under: "spaghetti" is its "Pasta,
/// cooked", a "wrap" its tortilla and "meat" its beef. With another word they mean themselves:
/// spaghetti squash, macaroni and cheese, a chicken wrap.
let aloneFiled: [String: String] = Dictionary(
    uniqueKeysWithValues: [("spaghetti", "pasta"), ("macaroni", "pasta"), ("wrap", "tortilla"), ("meat", "beef")]
        + pastaShapes.map { (stem($0), "pasta") })

/// A typed word is searched as typed, plus the catalog's own wording for the same food. Looser
/// alternatives the model needs ("fries" as fried, "pop" as carbonated) would take over a search.
let typedAlternatives: Set<String> = [
    "bun", "buns", "ketchup", "soda", "oatmeal", "donut", "donuts", "skim", "bbq", "coke", "burger", "burgers", "rib", "ribs", "unsalted",
    "omelette", "omelettes", "yoghurt", "yoghurts", "chilli", "barbeque", "whisky", "houmous", "soya", "skimmed", "prawn", "prawns", "courgette",
    "courgettes", "aubergine", "aubergines", "beetroot", "sweetcorn", "kiwi", "kiwis",
]

/// "Tomato slice" and "bacon strip" name a food plus how much of it; only the food is searched.
let countWords: Set<String> = [
    "slice", "slices", "piece", "pieces", "strip", "strips", "leaf", "leaves", "wedge", "wedges", "chunk", "chunks",
    "serving", "servings", "portion", "portions", "cup", "cups", "bowl", "bowls", "plate", "plates", "side", "sides",
    "order", "orders", "small", "medium", "large", "regular", "jumbo", "mini", "kid", "kids", "tall", "grande", "venti",
    "segment", "segments", "cube", "cubes", "drizzle", "pat", "pats", "scoop", "scoops", "dollop", "sprinkle", "pinch", "dash", "splash",
    "spoonful", "squeeze",
]

/// A search can carry its amount: "cup of coffee", "200 g chicken", "2 eggs".
let unitWords: Set<String> = [
    "g", "gram", "grams", "gm", "gms", "kg", "kgs", "kilo", "kilos", "oz", "ounce", "ounces", "lb", "lbs", "pound",
    "pounds", "ml", "mls", "l", "liter", "liters", "litre", "litres", "fl", "floz", "tbsp", "tbs", "tsp", "tablespoon",
    "tablespoons", "teaspoon", "teaspoons", "scoop", "scoops", "can", "cans", "bottle", "bottles", "glass", "glasses",
    "mug", "mugs", "shot", "shots", "pint", "pints", "handful", "handfuls",
]

/// A size before the food says how much of it: "large egg", "grande latte". "Mini" names products.
let sizeWords: Set<String> = ["small", "medium", "large", "jumbo", "regular", "tall", "grande", "venti"]

/// How a size in inches is written after its number: "14 inch", "14in", "14-inch".
let inchWords: Set<String> = ["inch", "inches", "in"]

/// Inch marks after a number: `14"`, and the curly quote a phone's keyboard types for one.
private let inchMarks: Set<Unicode.Scalar> = ["\"", "\u{201C}", "\u{201D}"]

// MARK: - Characters

/// JavaScript's string length (UTF-16 code units), which the ranking's thresholds were tuned on.
@inline(__always) func length(_ value: String) -> Int { value.utf16.count }

@inline(__always) func starts(_ value: String, _ prefix: String) -> Bool { value.utf8.starts(with: prefix.utf8) }

@inline(__always) func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
    let v = scalar.value
    if v < 0x80 { return (v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x7A) || (v >= 0x41 && v <= 0x5A) }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .letterNumber,
        .otherNumber:
        return true
    default:
        return false
    }
}

@inline(__always) func isLetter(_ scalar: Unicode.Scalar) -> Bool {
    let v = scalar.value
    if v < 0x80 { return (v >= 0x61 && v <= 0x7A) || (v >= 0x41 && v <= 0x5A) }
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
    default: return false
    }
}

@inline(__always) func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 0x30 && scalar.value <= 0x39 }

/// JavaScript's `\s`, near enough.
@inline(__always) func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x20, 0x09...0x0D, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
    default: return false
    }
}

/// Lower case without accents: "Crème Brûlée" → "creme brulee".
func plain(_ value: String) -> String { makeString(plainScalars(value)[...]) }

/// The scalars of plain text: ASCII lower-cased directly, anything else decomposed (NFKD) without
/// its accents, then lower-cased.
func plainScalars(_ value: String) -> [Unicode.Scalar] {
    if value.utf8.allSatisfy({ $0 < 0x80 }) {
        return value.utf8.map { Unicode.Scalar($0 >= 0x41 && $0 <= 0x5A ? $0 + 32 : $0) }
    }
    var scalars = String.UnicodeScalarView()
    for scalar in value.decomposedStringWithCompatibilityMapping.unicodeScalars where !(0x300...0x36F).contains(scalar.value) {
        scalars.append(scalar)
    }
    return Array(String(scalars).lowercased().unicodeScalars)
}

/// A string from scalars, without a detour through a scalar view for ASCII.
func makeString(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
    if scalars.allSatisfy(\.isASCII) {
        return String(unsafeUninitializedCapacity: scalars.count) { buffer in
            var i = 0
            for scalar in scalars {
                buffer[i] = UInt8(truncatingIfNeeded: scalar.value)
                i += 1
            }
            return i
        }
    }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
}

/// A run of letters and digits in plain text, and where it is.
struct Token {
    var word: String
    var start: Int
    var end: Int
}

/// The runs of letters and digits in plain text.
func scanTokens(_ scalars: [Unicode.Scalar]) -> [Token] {
    var result: [Token] = []
    var index = 0
    while index < scalars.count {
        guard isWordScalar(scalars[index]) else {
            index += 1
            continue
        }
        let start = index
        while index < scalars.count, isWordScalar(scalars[index]) { index += 1 }
        result.append(Token(word: makeString(scalars[start..<index]), start: start, end: index))
    }
    return result
}

/// The words of some text, plain: "McDonald's" → ["mcdonald", "s"].
func tokens(_ value: String) -> [String] { scanTokens(plainScalars(value)).map(\.word) }

/// Tokens without the small words a name doesn't need.
func words(_ value: String) -> [String] { tokens(value).filter { !stopWords.contains($0) } }

/// Only ASCII digits: "12", not "12g".
@inline(__always) func isNumber(_ word: String) -> Bool { !word.isEmpty && word.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }

/// Words a model puts before a way of cooking that say no more about the food: "pan-seared",
/// "oven-roasted", "stir-fried", "lightly grilled".
private let methodHelpers: Set<String> = ["pan", "oven", "air", "deep", "stir", "char", "flame", "slow", "lightly", "freshly", "pressure", "wood"]

/// The words that name a food a model saw: "tomato slice" is a tomato, "scrambled eggs (2
/// large)" scrambled eggs and a "pan-seared salmon fillet" a seared one. "Mini" names products
/// more often than a size: Mini-Wheats, mini pretzels, mini peppers.
func nameWords(_ name: String) -> [String] {
    // Without its amount, as a typed search is read: "2 large", "2 tbsp", "glass of".
    var list = readQuery(name).words
    list = list.indices.filter { i in
        !(methodHelpers.contains(list[i]) && i + 1 < list.count && (isHeat(list[i + 1]) || list[i + 1] == "cooked" || list[i + 1] == "fired"))
    }.map { list[$0] }
    // Nor what was done to it on the way to the plate, where that isn't all that's said.
    let plain = list.filter { !servingWords.contains($0) }
    if !plain.isEmpty { list = plain }
    // "Half an avocado" is an avocado; half and half is a cream.
    if list.first == "half", list.count > 1, !list.dropFirst().contains("half") { list.removeFirst() }
    // A bowl named last is a dish: a poke bowl, a burrito bowl.
    let dish = list.count > 1 && (list.last == "bowl" || list.last == "bowls") ? list.count - 1 : -1
    let food = list.indices.filter { $0 == dish || list[$0] == "mini" || !countWords.contains(list[$0]) }.map { list[$0] }
    return Array((food.isEmpty ? list : food).prefix(6))
}

/// What a model says was done to a food before serving it, which names no other food:
/// "buttered toast" is toast.
private let servingWords: Set<String> = ["buttered", "seasoned", "garnished", "homemade", "leftover", "assorted"]

/// Words after which a model's name goes on to what the food comes with, on or in.
private let sideWords: Set<String> = ["with", "on", "over", "in", "atop"]

/// What a food is said to be done with what comes with it, which says nothing of the food:
/// "salad topped with chicken", "rice served with beans".
private let servedWords: Set<String> = [
    "topped", "served", "drizzled", "sprinkled", "garnished", "mixed", "tossed", "dressed", "paired", "covered", "smothered", "loaded", "filled",
]

/// A food as a model names it, apart from what it says comes with it: "Whole wheat toast with
/// butter" is whole wheat toast, with butter beside; "Turkey sandwich on wheat bread" a turkey
/// sandwich; "Chicken wings (buffalo)" chicken wings, said to be buffalo. The food is matched by
/// its own words, and the rest only tells two foods that match as well apart. A word for the
/// form the food comes in is part of its name wherever it's said: "Black beans (canned)" are
/// canned black beans, "Chicken thigh with skin" the thigh with its skin. `beside` are the
/// `sides` that are other foods served with it. "On", "over" and "in" divide a name only after
/// a food of two words or a long one: pigs in a blanket and corn on the cob are dishes.
func seenName(_ said: String) -> (main: String, sides: [String], beside: [String]) {
    var outside = ""
    var inside = ""
    var depth = 0
    for character in said {
        if character == "(" {
            depth += 1
            inside += " "
        } else if character == ")" {
            depth = max(0, depth - 1)
            outside += " "
        } else if depth > 0 {
            inside.append(character)
        } else {
            outside.append(character)
        }
    }
    var main = outside.split(separator: " ").map(String.init)
    var with: [String] = []
    if let at = main.indices.first(where: { i in
        guard i > 0, i + 1 < main.count else { return false }
        let word = main[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard sideWords.contains(word) || word == "w" else { return false }
        if word == "with" || word == "w" { return true }
        let before = words(main[..<i].joined(separator: " "))
        return before.count > 1 || (before.first.map { length($0) > 4 } ?? false)
    }) {
        with = Array(main[(at + 1)...])
        main = Array(main[..<at])
    }
    if main.count > 1, let last = main.last, servedWords.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
        main.removeLast()
    }
    let name = main.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
    guard !words(name).isEmpty else { return (said, [], []) }
    // An amount is neither: "(2 large)", "(1 cup)".
    let said = { (text: String) in nameWords(text).filter { !countWords.contains($0) && !unitWords.contains($0) } }
    let served = said(with.joined(separator: " "))
    let about = said(inside)
    // The forms go before the name, so its last word still names the food.
    let forms = (served + about).filter(isFormSaid)
    var seen = Set(words(name))
    let kept = forms.filter { seen.insert($0).inserted }
    let beside = served.filter { !isFormSaid($0) && seen.insert($0).inserted }
    let sides = beside + about.filter { !isFormSaid($0) && seen.insert($0).inserted }
    return ((kept + [name]).joined(separator: " "), Array(sides.prefix(5)), Array(beside.prefix(5)))
}

// MARK: - Stems and forms

private let iePlurals: [StaticString] = ["cookies", "brownies", "smoothies", "veggies", "hoagies", "pierogies", "goodies", "calories"]

@inline(__always) private func ends(_ bytes: UnsafeBufferPointer<UInt8>, _ suffix: StaticString) -> Bool {
    let n = suffix.utf8CodeUnitCount
    guard bytes.count >= n else { return false }
    let start = suffix.utf8Start
    let offset = bytes.count - n
    for i in 0..<n where bytes[offset + i] != start[i] { return false }
    return true
}

/// A prefix that matches singular and plural forms in the catalog's prefix search.
func stem(_ word: String) -> String {
    let n = length(word)
    if n <= 3 { return word }
    let counted: Int? = word.utf8.withContiguousStorageIfAvailable { bytes in
        if iePlurals.contains(where: { ends(bytes, $0) }) { return 1 }
        if ends(bytes, "ies") { return n > 5 ? 3 : 0 }
        if ends(bytes, "ches") || ends(bytes, "shes") || ends(bytes, "xes") || ends(bytes, "oes") || ends(bytes, "sses") { return 2 }
        if ends(bytes, "y") && n > 4 { return 1 }
        // "Turkeys" and "Wendy's" end like "turkey" and "Wendy" do.
        if ends(bytes, "ys") && n > 5 { return 2 }
        if ends(bytes, "ss") || ends(bytes, "us") || ends(bytes, "is") { return 0 }
        return ends(bytes, "s") ? 1 : 0
    }
    guard let drop = counted else {
        var copy = word
        copy.makeContiguousUTF8()
        return stem(copy)
    }
    return drop == 0 ? word : String(decoding: word.utf8.dropLast(drop), as: UTF8.self)
}

/// Both sides are stemmed, so a match may only differ by an ending a word takes on: a plural's
/// ("pie" is "pies") or a participle's ("toast" is "toasted", "smoke" is "smoked"). Any two letters
/// more made "pea" a pear, a peach and a pearl, "bun" a bunch, "mac" mace and "bran" brandy.
@inline(__always) func same(_ word: String, _ form: String) -> Bool {
    if word == form { return true }
    guard length(form) > 2, starts(word, form) else { return false }
    let ending = word.utf8.dropFirst(form.utf8.count)
    switch ending.count {
    case 1: return ending.first == UInt8(ascii: "s") || (ending.first == UInt8(ascii: "d") && form.utf8.last == UInt8(ascii: "e"))
    case 2: return ending.elementsEqual("es".utf8) || ending.elementsEqual("ed".utf8)
    default: return false
    }
}

/// A word without the "s" of its plural or possessive, for telling a brand's word from a word that
/// only shares its stem: "joes" and "joe" name the same brand, "wheats" doesn't name Wheaty.
func bare(_ word: String) -> String {
    length(word) > 3 && word.utf8.last == UInt8(ascii: "s") ? String(word.dropLast()) : word
}

/// The catalog's wordings of a word the model said, including looser ones.
func forms(_ word: String) -> [String] { alternatives[word] ?? [stem(word)] }

/// The wordings a typed word is searched by.
func searchForms(_ word: String) -> [String] {
    var result = [stem(word)]
    if typedAlternatives.contains(word) { for form in forms(word) where !result.contains(form) { result.append(form) } }
    return result
}

private func either(_ options: [String]) -> String {
    options.count == 1 ? options[0] : "(\(options.joined(separator: " OR ")))"
}

private func unique(_ list: [String]) -> [String] {
    var seen = Set<String>()
    return list.filter { seen.insert($0).inserted }
}

/// A word the model said in the catalog's full-text syntax, with every wording of it.
func term(_ word: String) -> String { either(forms(word).map { "\"\($0)\"*" }) }

/// A typed word in the catalog's full-text syntax; a number, or a letter on its own, matches only
/// itself. Its fixes are searched too, as prefixes or, for a word typed without its space, the two
/// words together or a word apart: "membermark" is Member's Mark, whose "s" is a word to the index.
/// With `only`, the fixes stand in for the word instead of beside it.
func searchTerm(_ word: String, _ fixes: Fixes = [:], only: Bool = false) -> String {
    if isNumber(word) || length(word) == 1 { return "\"\(word)\"" }
    return either(
        unique((only ? [] : searchForms(word)) + (fixes[word] ?? [])).map { form in
            let parts = form.split(separator: " ")
            guard parts.count > 1 else { return "\"\(form)\"*" }
            return "NEAR(" + parts.map { "\"\($0)\"" }.joined(separator: " ") + "*, 1)"
        })
}

/// The catalog's full-text expression for a search: each word as a stemmed prefix.
func searchExpression(_ query: String) -> String {
    readQuery(query).words.map { searchTerm($0) }.joined(separator: " AND ")
}

// MARK: - Reading a typed search

/// What a typed search asks for: `words` must all match, `counts` are numbers before a food that
/// may be part of its name ("12 grain bread"), searched as an optional phrase, and `sizes` are
/// sizes in inches ("14 inch pepperoni"), which rank a food of that size first without being words
/// a food must have.
struct QueryReading: Equatable {
    var words: [String]
    var counts: [(String, String)]
    var sizes: [String] = []

    static func == (a: QueryReading, b: QueryReading) -> Bool {
        a.words == b.words && a.counts.elementsEqual(b.counts, by: { $0 == $1 }) && a.sizes == b.sizes
    }
}

private enum Role { case name, amount, stop, size }

/// "200g" and "12oz" are amounts; "7up" is a name.
private func measured(_ word: String) -> Bool {
    guard let first = word.unicodeScalars.first, isDigit(first) else { return false }
    return unitWords.contains(String(word.unicodeScalars.drop(while: isDigit)))
}

/// The number of a size written as one word: "14in", "6inch".
private func inchSize(_ word: String) -> String? {
    let digits = String(word.unicodeScalars.prefix(while: isDigit))
    guard !digits.isEmpty, inchWords.contains(String(word.dropFirst(digits.count))) else { return nil }
    return digits
}

/// Whether the number at `i` is a size in inches: `14"`, "14 inch", "14-inch". USDA writes a
/// chain's pizza as `PAPA JOHN'S 14" Pepperoni Pizza`, so "inch" itself is a word few foods have.
private func inches(_ i: Int, _ found: [Token], _ text: [Unicode.Scalar]) -> Bool {
    let end = found[i].end
    if end < text.count && inchMarks.contains(text[end]) { return true }
    guard i + 1 < found.count, inchWords.contains(found[i + 1].word) else { return false }
    return text[end..<found[i + 1].start].allSatisfy { isSpace($0) || $0 == "-" }
}

/// Whether a number is written as part of a name: "2% milk", "93/7 beef", "7-up" and "v-8".
private func writtenIntoName(_ word: String, before: ArraySlice<Unicode.Scalar>, after: ArraySlice<Unicode.Scalar>) -> Bool {
    func percent(_ text: ArraySlice<Unicode.Scalar>) -> Bool {
        var rest = text.drop(while: isSpace)
        return rest.popFirst() == "%"
    }
    // A percentage, also with decimals: "2%", "3.25 %".
    if percent(after) { return true }
    if let first = after.first, first == "." || first == ",", after.dropFirst().first.map(isDigit) == true,
        percent(after.dropFirst().drop(while: isDigit))
    {
        return true
    }
    if before.count >= 2, let last = before.last, last == "." || last == ",", isDigit(before[before.endIndex - 2]), percent(after) {
        return true
    }
    // Hyphenated with letters: "7-up", "v-8".
    if after.first == "-", let next = after.dropFirst().first, isLetter(next) { return true }
    if before.last == "-", let previous = before.dropLast().last, isLetter(previous) { return true }
    // A lean-to-fat ratio, not a fraction like 1/2.
    func number(_ digits: ArraySlice<Unicode.Scalar>) -> Double? {
        digits.isEmpty ? nil : Double(String(String.UnicodeScalarView(digits)))
    }
    let value = Double(word) ?? 0
    var next = after.drop(while: isSpace)
    if next.popFirst() == "/", let other = number(next.drop(while: isSpace).prefix(while: isDigit)), value >= other { return true }
    var previous = before
    while let last = previous.last, isSpace(last) { previous = previous.dropLast() }
    if previous.last == "/" {
        previous = previous.dropLast()
        while let last = previous.last, isSpace(last) { previous = previous.dropLast() }
        let end = previous.endIndex
        while let last = previous.last, isDigit(last) { previous = previous.dropLast() }
        if let other = number(before[previous.endIndex..<end]), other >= value { return true }
    }
    return false
}

/// What a typed search asks for. Amounts go ("2 eggs", "200 g", "1/2 cup", "cup of coffee", "large
/// egg"), sizes in inches are kept aside ("14 inch pizza"), while numbers written into a name ("2%
/// milk") and count words that name the food ("cup noodles") stay. Typed alone, small words stay:
/// "or" and "to" are the start of orange and toast.
func readQuery(_ query: String) -> QueryReading {
    let text = plainScalars(query)
    let found = scanTokens(text)
    var roles: [Role] = []
    var sizes: [String] = []
    for (i, token) in found.enumerated() {
        let word = token.word
        // Counted ("2 cups rice"), measured ("cup of coffee") or sized ("large egg"), it's an amount.
        let much =
            (i > 0 && (roles[i - 1] == .amount || roles[i - 1] == .size)) || (i + 1 < found.count && found[i + 1].word == "of")
            || (sizeWords.contains(word) && found[(i + 1)...].contains { !stopWords.contains($0.word) })
        if isNumber(word) && inches(i, found, text) {
            roles.append(.size)
            sizes.append(word)
        } else if i > 0 && roles[i - 1] == .size && inchWords.contains(word) {
            roles.append(.amount)
        } else if let size = inchSize(word) {
            roles.append(.size)
            sizes.append(size)
        } else if isNumber(word) {
            roles.append(writtenIntoName(word, before: text[..<token.start], after: text[token.end...]) ? .name : .amount)
        } else if measured(word) {
            roles.append(.amount)
        } else if stopWords.contains(word) {
            roles.append(.stop)
        } else {
            roles.append(much && (countWords.contains(word) || unitWords.contains(word)) ? .amount : .name)
        }
    }
    func pick(_ role: Role) -> [String] {
        zip(found, roles).filter { $0.1 == role && !($0.0.word.unicodeScalars.first.map(isDigit) ?? false) }.map(\.0.word)
    }
    let names = zip(found, roles).filter { $0.1 == .name }.map(\.0.word)
    if names.isEmpty {
        // Only amounts and small words: "cups" or "or" is still a search, a number alone isn't.
        let measures = pick(.amount)
        return QueryReading(words: Array((measures.isEmpty ? pick(.stop) : measures).prefix(8)), counts: [])
    }
    var counts: [(String, String)] = []
    for i in found.indices
    where roles[i] == .amount && isNumber(found[i].word) && i + 1 < found.count
        && roles[i + 1] == .name && !isNumber(found[i + 1].word)
    {
        counts.append((found[i].word, found[i + 1].word))
    }
    return QueryReading(words: Array(names.prefix(8)), counts: counts, sizes: sizes)
}

/// The words a typed search looks for: a last word of one letter waits for its second, unless it
/// is a digit ("chicken b" searches chicken).
func searchedWords(_ words: [String]) -> [String] {
    guard let last = words.last, length(last) < 2, !isNumber(last) else { return words }
    return Array(words.dropLast())
}

// MARK: - Typos

/// Typos a word may have and still be recognized: none under four letters, one to six, then two.
func allowedTypos(_ word: String) -> Int { allowedTypos(length: length(word)) }

func allowedTypos(length: Int) -> Int { length < 4 ? 0 : length < 7 ? 1 : 2 }

/// Edit distance with a swapped pair of letters counting as one ("protien"), stopping early once
/// two words are further apart than a limit. Reuses its rows across calls.
struct TypoMeter {
    private var before: [Int] = []
    private var previous: [Int] = []
    private var current: [Int] = []

    /// Edits between `a` and `b`, or `limit + 1` once they are further apart than `limit`.
    mutating func distance(_ a: ArraySlice<UInt16>, _ b: ArraySlice<UInt16>, limit: Int) -> Int {
        let n = a.count
        let m = b.count
        if abs(n - m) > limit { return limit + 1 }
        if previous.count < m + 1 {
            before = Array(repeating: 0, count: m + 1)
            previous = before
            current = before
        }
        for j in 0...m { previous[j] = j }
        let a0 = a.startIndex
        let b0 = b.startIndex
        var i = 1
        while i <= n {
            current[0] = i
            var best = i
            let ai = a[a0 + i - 1]
            var j = 1
            while j <= m {
                let bj = b[b0 + j - 1]
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ai == bj ? 0 : 1))
                if i > 1 && j > 1 && ai == b[b0 + j - 2] && a[a0 + i - 2] == bj { value = min(value, before[j - 2] + 1) }
                current[j] = value
                best = min(best, value)
                j += 1
            }
            if best > limit { return limit + 1 }
            swap(&before, &previous)
            swap(&previous, &current)
            i += 1
        }
        return min(previous[m], limit + 1)
    }

    /// How a typed word, which may still be half typed, reads a catalog word: the start of it that
    /// is fewest edits away ("chikc" is one from "chick" in chicken), or nil past the allowance.
    mutating func misread(_ typed: [UInt16], _ word: [UInt16]) -> (edits: Int, length: Int)? {
        let limit = allowedTypos(length: typed.count)
        if limit == 0 || word.count < typed.count - limit { return nil }
        var found: (edits: Int, length: Int)?
        var tried: [Int] = []
        // The whole word first, so "brocoli" means broccoli rather than its start "brocco".
        for size in [word.count, typed.count - 1, typed.count, typed.count + 1] where !tried.contains(size) {
            tried.append(size)
            guard size >= 3 && size <= word.count else { continue }
            let edits = distance(typed[...], word[..<size], limit: limit)
            if edits <= limit && (found == nil || edits < found!.edits) { found = (edits, size) }
        }
        return found
    }
}

/// A typed word the catalogs barely know, kept to compare with each food's own words: "gali" is
/// the Galli of Galli's roasted chestnuts, though "gala" is on far more labels. The catalogs' words
/// can only say what a typo usually means; the foods the other words found say what it means here.
struct Misspelling: Sendable {
    private let units: [UInt16]
    private let limit: Int

    /// Nil for a word too short to allow a typo, or with a digit in it.
    init?(_ word: String) {
        let limit = allowedTypos(word)
        guard limit > 0, !word.unicodeScalars.contains(where: isDigit) else { return nil }
        self.limit = limit
        units = Array(stem(word).utf16)
    }

    /// Whether one of a food's words, stemmed, is the word typed with a typo or two.
    func reads(_ words: [String]) -> Bool {
        var meter = TypoMeter()
        return words.contains { word in
            let count = word.utf16.count
            guard count > 3, abs(count - units.count) <= limit else { return false }
            return meter.distance(units[...], Array(word.utf16)[...], limit: limit) <= limit
        }
    }
}

func typos(_ a: String, _ b: String, limit: Int) -> Int {
    var meter = TypoMeter()
    return meter.distance(Array(a.utf16)[...], Array(b.utf16)[...], limit: limit)
}

func misread(_ typed: String, _ word: String) -> (edits: Int, meant: String)? {
    var meter = TypoMeter()
    guard let found = meter.misread(Array(typed.utf16), Array(word.utf16)) else { return nil }
    return (found.edits, String(decoding: Array(word.utf16.prefix(found.length)), as: UTF16.self))
}
