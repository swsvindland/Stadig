import Foundation

/// The model's first reply as plain values: what a photo shows and the foods it names.
struct MealReply: Sendable {
    struct Item: Hashable, Sendable {
        var brand: String
        var name: String
        var quantity: Double
        var unit: String
        var grams: Double?
    }

    /// What a photo really shows; nil for a description.
    var scene: String?
    /// The model's verdict that a photo shows food; nil for a description.
    var food: Bool?
    var items: [Item]
}

/// One food the model saw or read about, before it is matched to the catalog.
struct SeenFood: Hashable, Sendable {
    var name: String
    /// Empty when no brand was seen or said.
    var brand: String
    var quantity: Double
    var unit: String
    /// The model's estimate of the whole quantity's edible weight.
    var grams: Double?
    /// What the person would call it when `name` is a part of it: "flat white" for its espresso.
    var label: String? = nil
}

/// Turns the model's reply into the foods to match: validated, deduplicated, with chains moved
/// into the brand and a chain's dish kept whole.
enum SeenFoods {
    static let maxFoods = 12

    /// `photo` says the foods were seen; otherwise they were read from `description` alone.
    static func read(_ reply: MealReply, description: String = "", photo: Bool = false) -> [SeenFood] {
        let said = description.trimmingCharacters(in: .whitespacesAndNewlines)
        // Foods listed anyway for a photo judged not to show any are guesses; a description is not.
        if said.isEmpty && reply.food == false { return [] }
        var foods: [SeenFood] = []
        var keys: Set<String> = []
        for item in reply.items {
            var name = FoodText.clean(item.name)
            let maker = FoodText.clean(item.brand)
            var brand = noBrand.matches(maker) ? "" : maker
            let chain = Chain.find(in: brand.isEmpty ? name : brand)
            if let chain, brand.isEmpty {
                // "dominos pepperoni pizza" is Domino's "pepperoni pizza".
                let rest = FoodText.clean(edgeLinks.replacing(in: chain.pattern.replacing(in: chain.text, with: " ", all: false), with: ""))
                if !FoodText.words(rest).isEmpty { name = rest }
            }
            if let chain { brand = chain.brand } else if brand.isEmpty, let implied = Chain.implied(by: name) { brand = implied.brand }
            guard !name.isEmpty else { continue }
            // "1 slice" in the unit field would otherwise double the count; "150 g" with a quantity
            // of 1 is 150 g.
            let written = FoodText.clean(item.unit)
            let unit = FoodText.clean(leadingCount.replacing(in: written, with: "")).nilIfEmpty ?? "serving"
            let lead = leadingCount.firstMatch(in: written).flatMap { Measures.parseAmount(FoodText.clean($0)) }
            let said = lead.flatMap { item.quantity == 1 && $0 > 0 ? $0 : nil } ?? item.quantity
            // Repeated entries are a generation loop, not extra food.
            guard keys.insert("\(brand)|\(name)".lowercased()).inserted else { continue }
            let quantity = said.isFinite && said > 0 && said <= most(unit) ? said : 1
            let grams = item.grams.flatMap { $0.isFinite && $0 >= 1 && $0 <= 3000 ? $0 : nil }
            foods.append(SeenFood(name: name, brand: brand, quantity: quantity, unit: unit, grams: grams))
        }
        if !photo && !said.isEmpty { foods = grounded(foods, in: description) }
        if !said.isEmpty { foods = StatedAmounts.apply(foods, said: description) }
        if let chain = Chain.find(in: description) ?? Chain.implied(by: description) {
            // The person's description can name the chain when the model didn't.
            if !foods.contains(where: { !$0.brand.isEmpty }),
               let dish = foods.firstIndex(where: { wholeDish.matches($0.name) }) ?? (foods.count == 1 ? 0 : nil) {
                foods[dish].brand = chain.brand
            }
            foods = collapse(foods, chain: chain)
        }
        return Array(CoffeeDrinks.expand(dropToppings(foods), description: description).prefix(maxFoods))
    }

    /// "big mac from mcdonalds" split into bun, patties and toppings is still one Big Mac. Foods the
    /// description names on their own ("and a banana") are not its parts, and a dish that is already
    /// listed ("blueberry muffin", "chicken nuggets" for "mcnuggets") is not rebuilt.
    private static func collapse(_ foods: [SeenFood], chain: Chain.Found) -> [SeenFood] {
        let (dish, others) = dishNamed(by: chain)
        let named = FoodText.words(dish).filter { !FoodText.countWords.contains($0) }.map(FoodText.stem)
        let parts = foods.filter { food in
            isPart(food.name) && !FoodText.nameWords(food.name).contains { others.contains(FoodText.stem($0)) }
        }
        func listed(_ food: SeenFood) -> Bool {
            let own = FoodText.nameWords(food.name).map(FoodText.stem)
            return wholeDish.matches(food.name) || named.allSatisfy(own.contains)
                || (!parts.contains(food) && own.contains { word in
                    named.contains { $0 == word || (word.count > 3 && $0.hasSuffix(word)) }
                })
        }
        guard !named.isEmpty, parts.count > 1, !foods.contains(where: listed) else { return foods }
        return [SeenFood(name: dish, brand: chain.brand, quantity: 1, unit: "serving", grams: nil)] + foods.filter { !parts.contains($0) }
    }

    /// A description's foods are the ones it names. A small model sometimes echoes its instructions'
    /// examples instead ("a can of diet coke" with a chicken breast, lettuce and a bun) or guesses a
    /// brand ("Burger King" for a Big Mac): such foods are dropped and such brands cleared. A dish the
    /// description names ("a cheeseburger", "a smoothie") may be split into parts it doesn't name.
    static func grounded(_ foods: [SeenFood], in description: String) -> [SeenFood] {
        let said = FoodText.words(description).map(FoodText.stem)
        func mentioned(_ word: String) -> Bool {
            FoodText.forms(word).contains { form in
                said.contains { FoodText.same($0, form) || FoodText.same(form, $0) || (min($0.count, form.count) >= 4 && ($0.hasPrefix(form) || form.hasPrefix($0))) }
            }
        }
        let foods = foods.map { food in
            var food = food
            if !food.brand.isEmpty && !FoodText.words(food.brand).contains(where: mentioned) { food.brand = "" }
            return food
        }
        let named = foods.filter { FoodText.nameWords($0.name).contains(where: mentioned) }
        if dishWords.matches(description) {
            // A dish listed whole ("pepperoni pizza") already has the toppings it wasn't said to have.
            let whole = named.contains { wholeDish.matches($0.name) }
            return foods.filter { !whole || named.contains($0) || !isOnDish($0) }
        }
        // Nothing recognisably named ("pb&j") leaves the model's reading as it is.
        return named.isEmpty ? foods : named
    }

    /// A chain's pizza or burger already includes its toppings, which small models still list.
    private static func dropToppings(_ foods: [SeenFood]) -> [SeenFood] {
        let whole = foods.contains { !$0.brand.isEmpty && wholeDish.matches($0.name) }
        return Array(foods.filter { !whole || !$0.brand.isEmpty || !isOnDish($0) }.prefix(maxFoods))
    }

    /// The dish a description names, without the chain or chatter ("big mac from mcdonalds" is
    /// "big mac"), and the stems of everything else it names.
    static func dishNamed(by chain: Chain.Found) -> (dish: String, others: Set<String>) {
        func clean(_ text: String) -> String {
            let text = digits.replacing(in: chatter.replacing(in: chain.pattern.replacing(in: text, with: " ", all: false), with: " "), with: " ")
            return FoodText.clean(text, limit: 500)
        }
        // Separators stay at odd indexes.
        let pieces = separators.splitKeepingMatches(chain.text)
        func find(_ test: (String) -> Bool) -> Int? {
            pieces.indices.first { $0.isMultiple(of: 2) && test(pieces[$0]) }
        }
        // A whole dish, else the item the chain names ("a starbucks latte", not "fries from
        // mcdonalds"), else the first thing named.
        let via = Pattern(#"\b(?:from|at|by)\s+(?:"# + chain.pattern.regex.pattern + ")")
        let at = find { wholeDish.matches($0) }
            ?? find { chain.pattern.matches($0) && !via.matches($0) && !clean($0).isEmpty }
            ?? find { !clean($0).isEmpty }
        let start = at ?? 0
        var end = start
        // Menu items name their egg or cheese: "sausage mcmuffin with egg".
        while end + 2 < pieces.count, withWord.matches(pieces[end + 1]), eggOrCheese.matches(pieces[end + 2]) { end += 2 }
        let rest = pieces.indices.filter { $0.isMultiple(of: 2) && ($0 < start || $0 > end) }.map { clean(pieces[$0]) }
        let dish = clean(pieces[start...end].joined(separator: " ")).split(separator: " ").prefix(6).joined(separator: " ")
        return (dish, Set(FoodText.words(rest.joined(separator: " ")).map(FoodText.stem)))
    }

    /// Counts above 50 are a generation loop, but 200 g is an ordinary weight.
    static func most(_ unit: String) -> Double {
        let key = Measures.unitKey(unit)
        guard let size = Measures.weights[key] ?? Measures.volumes[key] else { return 50 }
        return max(50, 3000 / size)
    }

    // MARK: Words

    private static let noBrand = Pattern(#"^(?:none|n/?a|unknown|generic|homemade|no brand|unbranded|-)$"#)
    private static let edgeLinks = Pattern(#"^\W*(?:from|at|by)\b|\b(?:from|at|by)\W*$"#)
    private static let leadingCount = Pattern(#"^[\d./\s]+"#)
    private static let chatter = Pattern(#"\b(?:i|had|ate|got|some|my|a|an|the|from|at|of|for|lunch|dinner|breakfast)\b"#)
    private static let digits = Pattern(#"\d+"#)
    private static let separators = Pattern(#",|\band\b|\bwith\b|\bplus\b"#)
    private static let withWord = Pattern("^with$")
    private static let eggOrCheese = Pattern(#"^\s*(?:eggs?|cheese)\s*$"#)

    /// Words for a dish of several foods, which may be split into parts the description doesn't name.
    private static let dishWords = Pattern(#"\b(?:pizza|burger|cheeseburger|sandwich|sub|burrito|taco|wrap|bowl|salad|quesadilla|"#
        + #"hot ?dog|big mac|whopper|blt|club|panini|toastie|toast|omelett?e|breakfast|brunch|lunch|dinner|supper|meal|platter|combo|"#
        + #"stir[- ]?fry|curry|stew|soup|casserole|bento|poke|fry[- ]up|smoothie|shake|parfait)s?\b"#)

    static let wholeDish = Pattern(
        #"\b(?:pizza|burger|cheeseburger|sandwich|sub|burrito|taco|wrap|bowl|salad|quesadilla|hot ?dog|big mac|whopper)\b"#)

    /// Words that only ever describe what is on or in a dish: its toppings, fillings and sauces.
    private static let toppingWords: Set<String> = Set(("bacon ham pepperoni salami sausage beef ground chicken turkey steak patty "
        + "meatball meatballs mushroom mushrooms onion onions pepper peppers olive olives cheese mozzarella cheddar parmesan "
        + "provolone american swiss lettuce tomato tomatoes pickle pickles jalapeno jalapenos pineapple spinach sauce marinara "
        + "pizza bbq ketchup mustard mayo mayonnaise dressing guacamole guac salsa sour cream rice beans bean corn sliced diced "
        + "chopped shredded grilled fried crispy fresh green red black white brown pinto refried banana bell hot mild spicy "
        + "crumbled extra").split(separator: " ").map(String.init))
    private static let toppingUnits: Set<String> = ["slice", "strip", "leaf", "leave", "tbsp", "tsp", "pinch", "dash", "sprinkle",
                                                    "dollop", "drizzle", "pat"]
    private static let partWords = Pattern(#"\b(?:buns?|rolls?|bread|patty|patties|tortilla|crust|muffins?|biscuits?|eggs?|sauces?)\b"#)

    static func isTopping(_ name: String) -> Bool {
        let list = FoodText.words(name).filter { !FoodText.countWords.contains($0) }
        return !list.isEmpty && list.allSatisfy(toppingWords.contains)
    }

    /// A topping word in a topping's amount; a real side (a banana, beans and rice) weighs more.
    static func isOnDish(_ food: SeenFood) -> Bool {
        isTopping(food.name) && ((food.grams.map { $0 <= 40 } ?? false) || toppingUnits.contains(Measures.unitKey(food.unit)))
    }

    static func isPart(_ name: String) -> Bool { isTopping(name) || partWords.matches(name) }
}

/// Chains whose menu items are catalogued whole. Small models often write the chain into the name.
enum Chain {
    struct Found: Sendable {
        var pattern: Pattern
        var brand: String
        /// The text it was found in, with curly apostrophes made straight.
        var text: String
    }

    static let all: [(Pattern, String)] = [
        (#"\bdomino'?s\b"#, "Domino's"), (#"\bpizza hut\b"#, "Pizza Hut"), (#"\bpapa john'?s\b"#, "Papa John's"),
        (#"\blittle caesar'?s\b"#, "Little Caesars"), (#"\bmc ?donald'?s\b"#, "McDonald's"), (#"\bburger king\b"#, "Burger King"),
        (#"\bwendy'?s\b"#, "Wendy's"), (#"\btaco bell\b"#, "Taco Bell"), (#"\bkfc\b|\bkentucky fried chicken\b"#, "KFC"),
        (#"\bsubway\b"#, "Subway"), (#"\bstarbucks\b"#, "Starbucks"), (#"\bdunkin'?(?: donuts)?\b"#, "Dunkin'"),
        (#"\bchick-?fil-?a\b"#, "Chick-fil-A"), (#"\bpopeyes\b"#, "Popeyes"), (#"\bpanera\b"#, "Panera"),
        (#"\bfive guys\b"#, "Five Guys"), (#"\bin-?n-?out\b"#, "In-N-Out"), (#"\barby'?s\b"#, "Arby's"),
        (#"\bjack in the box\b"#, "Jack in the Box"), (#"\bdairy queen\b"#, "Dairy Queen"), (#"\bwhataburger\b"#, "Whataburger"),
        (#"\bpanda express\b"#, "Panda Express"), (#"\bshake shack\b"#, "Shake Shack"), (#"\bolive garden\b"#, "Olive Garden"),
        (#"\bapplebee'?s\b"#, "Applebee's"), (#"\bdenny'?s\b"#, "Denny's"), (#"\bihop\b"#, "IHOP"), (#"\bcarl'?s jr\.?"#, "Carl's Jr."),
        (#"\bhardee'?s\b"#, "Hardee's"), (#"\bjimmy john'?s\b"#, "Jimmy John's"),
        (#"\bchipotle (?:mexican grill|bowl|burrito)"#, "Chipotle"),
    ].map { (Pattern($0.0), $0.1) }

    /// Menu items only one chain sells: a Big Mac is McDonald's whether or not anyone says so.
    static let signatures: [(Pattern, String)] = [
        (#"\bbig ?macs?\b|\bquarter ?pounders?\b|\bmc ?nuggets?\b|\bmc ?muffins?\b|\bmc ?flurr(?:y|ies)\b|\bmc ?chickens?\b|\bmc ?griddles?\b|\bfilet-o-fish\b"#,
         "McDonald's"),
        (#"\bwhoppers?\b"#, "Burger King"), (#"\bbaconators?\b"#, "Wendy's"), (#"\bcrunchwraps?\b|\bchalupas?\b"#, "Taco Bell"),
        (#"\bfrappuccinos?\b"#, "Starbucks"),
    ].map { (Pattern($0.0), $0.1) }

    /// A chain a signature item implies. Its pattern matches nothing, so the item keeps its name.
    static func implied(by value: String) -> Found? {
        signatures.first { $0.0.matches(value) }.map { Found(pattern: never, brand: $0.1, text: value) }
    }

    private static let never = Pattern("(?!)")

    static func find(in value: String) -> Found? {
        let text = value.replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
        return all.first { $0.0.matches(text) }.map { Found(pattern: $0.0, brand: $0.1, text: text) }
    }
}
