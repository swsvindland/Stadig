import FoodDatabase
import Foundation

/// Drinks versus food, so a match of the wrong kind (rice for a flat white, a cappuccino powder for
/// a cappuccino) is never taken as sure.
enum Drinks {
    private static let words: Set<String> = Set(
        ("water coffee espresso latte cappuccino americano macchiato cortado mocha "
            + "frappuccino tea chai matcha juice lemonade limeade soda cola coke pepsi sprite fanta beer lager ale wine cider cocktail "
            + "smoothie shake milkshake kombucha beverage beverages drink drinks milk gatorade powerade redbull "
            + "whiskey whisky vodka rum gin tequila bourbon scotch brandy sake champagne soymilk oatmilk almondmilk eggnog kefir "
            + "cognac mezcal liqueur prosecco pilsner stout ipa seltzer tonic colada margarita mojito martini daiquiri sangria mimosa spritz")
            .split(separator: " ")
            .map { FoodText.stem(String($0)) })
    private static let phrases = Pattern(#"\b(?:flat white|hot chocolate|iced tea|soft drink|energy drink|red bull|sports drink)\b"#)

    /// Named after a drink and none: baking soda.
    private static let foods = Pattern(#"\b(?:baking soda|bicarbonate of soda)\b"#)

    /// A drink by its name: what its last word, the head noun, names ("chocolate milk", not
    /// "milk chocolate").
    static func isDrink(_ name: String) -> Bool {
        if foods.matches(name) { return false }
        if phrases.matches(name) { return true }
        guard let head = FoodText.nameWords(name).last else { return false }
        return words.contains(FoodText.stem(head))
    }

    /// A catalog food that is a drink as poured: measured in millilitres, or named one in its first
    /// part ("Beverages, coffee, brewed", "Milk, whole", "Diet Coke").
    static func isDrink(_ food: Food) -> Bool {
        food.basis == .ml || isDrink(String(food.name.split(separator: ",").first ?? ""))
    }

    /// The match is the same kind of thing as what was seen. A drink's match must be a drink as
    /// poured; food must not match one. A powder or concentrate of a drink (over 200 kcal per
    /// 100 g) isn't one as poured, so it's no match for the drink and is one for the powder:
    /// USDA files whey protein powder under "Beverages".
    static func sameKind(_ name: String, _ food: Food) -> Bool {
        // Spirits are over that as poured: USDA's vodka is 231 kcal per 100 g.
        let poured =
            isDrink(food)
            && (food.basis != .g || food.nutrients.kcal <= 200 || FoodText.words(Matching.firstPart(food.name)).contains("alcoholic"))
        return isDrink(name) == poured
    }
}

/// Espresso drinks made with milk, which catalogs list mostly as powders, capsules and bottled
/// products, are logged as what is in the cup: espresso and milk, both from the catalog.
enum CoffeeDrinks {
    struct Recipe {
        /// Millilitres of espresso, milk, and chocolate sauce (grams) in a regular one.
        var espresso: Double
        var milk: Double
        var chocolate: Double = 0
        /// Brewed coffee rather than espresso.
        var brewed = false
    }

    // Longest names first, so "latte macchiato" is a latte and "iced americano" an americano.
    static let recipes: [(Pattern, Recipe)] = [
        (#"\blatte macchiato\b"#, Recipe(espresso: 60, milk: 280)),
        (#"\b(?:flat white)\b"#, Recipe(espresso: 60, milk: 120)),
        (#"\bcortados?\b"#, Recipe(espresso: 60, milk: 60)),
        (#"\bmacchiatos?\b"#, Recipe(espresso: 60, milk: 15)),
        (#"\bcappuccinos?\b"#, Recipe(espresso: 60, milk: 120)),
        (#"\b(?:caff?[eè] )?mochas?\b"#, Recipe(espresso: 60, milk: 250, chocolate: 25)),
        (#"\b(?:caff?[eè] )?lattes?\b"#, Recipe(espresso: 60, milk: 280)),
        (#"\bamericanos?\b|\blong blacks?\b"#, Recipe(espresso: 0, milk: 0, brewed: true)),
        (#"\bdoppio\b|\bdouble espresso\b|\bespresso doppio\b"#, Recipe(espresso: 60, milk: 0)),
        (#"\bristretto\b"#, Recipe(espresso: 20, milk: 0)),
        (#"\bespressos?\b|\bshots? of espresso\b"#, Recipe(espresso: 30, milk: 0)),
    ].map { (Pattern($0.0), $0.1) }

    private static let milks: [(Pattern, String)] = [
        (#"\boat\b"#, "oat milk"), (#"\balmond\b"#, "almond milk"), (#"\bsoy\b"#, "soy milk"), (#"\bcoconut\b"#, "coconut milk"),
        (#"\b(?:skim|skimmed|nonfat|non-fat|fat-free)\b"#, "nonfat milk"),
        // A \b after "2%" would need a letter to follow it, so "a 2% latte" never matched.
        (#"\b2\s?%|\b(?:semi-skimmed|reduced fat|low-fat|lowfat)\b"#, "2% milk"),
    ].map { (Pattern($0.0), $0.1) }

    private static let cupParts = Pattern(
        #"^(?:(?:whole|oat|almond|soy|coconut|skim|skimmed|nonfat|steamed|2%|semi-skimmed|low-fat|lowfat)\s+)*(?:milk|espresso|espresso shots?|shots? of espresso|coffee)$"#
    )
    private static let cupWords: Set<String> = ["milk", "espresso", "coffee", "shot"]
    private static let larger = Pattern(#"\b(?:large|grande|venti|big|extra large)\b"#)
    private static let smaller = Pattern(#"\b(?:small|tall|short|mini)\b"#)
    /// Where a description moves on to its next item. "With" stays inside one: "a latte with oat
    /// milk" is one drink.
    private static let itemSeparators = Pattern(#",|;|&|\band\b|\bplus\b|\bthen\b"#)
    private static let withWord = Pattern(#"\bwith\b"#)
    private static let milkWord = Pattern(#"\bmilk\b"#)

    /// Unbranded espresso drinks as their parts, sized by count and size words; everything else as
    /// it was. A chain's drink stays whole: its nutrition is published. Milk and size words count
    /// only in the item of the description that orders the drink, so "an almond croissant" or "a
    /// large muffin" beside it changes nothing.
    static func expand(_ foods: [SeenFood], description: String = "") -> [SeenFood] {
        let drinks = foods.filter { food in food.brand.isEmpty && recipes.contains { $0.0.matches(food.name) } }
        guard !drinks.isEmpty else { return foods }
        let items =
            description.isEmpty
            ? [] : itemSeparators.splitKeepingMatches(FoodText.plain(description)).enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        // The milk or espresso the model listed beside the drink is the drink's own, unless the
        // person ordered it as an item of its own: "a mocha and a glass of milk".
        let inCup = foods.filter { $0.brand.isEmpty && cupParts.matches($0.name) && !drinks.contains($0) && isInADrink($0, items: items) }
        return foods.filter { !inCup.contains($0) }.flatMap { food -> [SeenFood] in
            guard food.brand.isEmpty, let (pattern, recipe) = recipes.first(where: { $0.0.matches(food.name) }) else { return [food] }
            // The drink's own words before any "with", and what it comes with when that is milk.
            let pieces = item(ordering: food, recipe: pattern, in: items).map(withWord.splitKeepingMatches) ?? []
            let ordered = pieces.first ?? ""
            let added = pieces.indices.filter { $0 > 0 && $0.isMultiple(of: 2) }.map { pieces[$0] }.filter(milkWord.matches)
            let said = food.name + " " + food.unit + " " + ordered
            // A drink's ounces are fluid ounces.
            let unit = Measures.unitKey(food.unit) == "oz" ? "floz" : Measures.unitKey(food.unit)
            let cup = recipe.brewed ? 240 : recipe.espresso + recipe.milk
            // "12 oz" of one is that much; "2 lattes" or "2 cups" are two of them.
            let poured = unit == "cup" ? nil : Measures.volumes[unit].map { $0 * food.quantity }
            let size = poured.map { $0 / cup } ?? (larger.matches(said) ? 1.4 : smaller.matches(said) ? 0.75 : 1)
            let count = poured == nil ? food.quantity : 1
            // The drink's own name first ("soy cappuccino"), then its order, then the milk listed beside the only drink.
            let milk =
                milks.first { $0.0.matches(food.name) }?.1
                ?? ([ordered] + added).lazy.compactMap { text in milks.first { $0.0.matches(text) }?.1 }.first
                ?? (drinks.count == 1 ? milks.first { milk in inCup.contains { milk.0.matches($0.name) } }?.1 : nil)
                ?? "whole milk"
            let label = FoodText.clean(food.name)
            func part(_ name: String, _ amount: Double, unit: String = "ml") -> SeenFood? {
                amount > 0 ? SeenFood(name: name, brand: "", quantity: (amount * count * size).rounded(), unit: unit, grams: nil, label: label) : nil
            }
            let parts = [
                recipe.brewed ? part("brewed coffee", 240) : part("espresso", recipe.espresso),
                part(milk, recipe.milk),
                part("chocolate syrup", recipe.chocolate, unit: "g"),
            ].compactMap { $0 }
            return parts
        }
    }

    /// The item of a description that orders this drink: the one naming it in full, else the first
    /// naming its kind, else the only item there is.
    private static func item(ordering drink: SeenFood, recipe: Pattern, in items: [String]) -> String? {
        let named = items.filter(recipe.matches)
        let words = FoodText.nameWords(drink.name).map(FoodText.stem)
        return named.first { Set(FoodText.words($0).map(FoodText.stem)).isSuperset(of: words) } ?? named.first
            ?? (items.count == 1 ? items.first : nil)
    }

    /// A milk or coffee belongs to a drink unless the person listed it as an item of its own: "a
    /// mocha and a glass of milk", "cereal with milk and a latte". Without a description (a photo),
    /// or when the description never says it, it is the drink's, and so is one only added "with"
    /// ("a latte, with oat milk", or a photo's note "with oat milk").
    private static func isInADrink(_ part: SeenFood, items: [String]) -> Bool {
        let words = FoodText.nameWords(part.name).map(FoodText.stem)
        func naming(_ wanted: [String]) -> [String] {
            items.filter { Set(FoodText.words($0).map(FoodText.stem)).isSuperset(of: wanted) }
        }
        // "Oat milk" is the item that says "oat milk"; "whole milk" is whichever says "milk".
        let full = naming(words)
        let mentioned = full.isEmpty ? naming(words.filter(cupWords.contains)) : full
        return !mentioned.contains { item in
            !recipes.contains { $0.0.matches(item) } && !FoodText.words(withWord.splitKeepingMatches(item).first ?? "").isEmpty
        }
    }
}
