import Foundation
import FoodDatabase

/// Drinks versus food, so a match of the wrong kind (rice for a flat white, a cappuccino powder for
/// a cappuccino) is never taken as sure.
enum Drinks {
    private static let words: Set<String> = Set(("water coffee espresso latte cappuccino americano macchiato cortado mocha "
        + "frappuccino tea chai matcha juice lemonade limeade soda cola coke pepsi sprite fanta beer lager ale wine cider cocktail "
        + "smoothie shake milkshake kombucha beverage beverages drink drinks milk gatorade powerade redbull").split(separator: " ")
        .map { FoodText.stem(String($0)) })
    private static let phrases = Pattern(#"\b(?:flat white|hot chocolate|iced tea|soft drink|energy drink|red bull|sports drink)\b"#)

    /// A drink by its name: what its last word, the head noun, names ("chocolate milk", not
    /// "milk chocolate").
    static func isDrink(_ name: String) -> Bool {
        if phrases.matches(name) { return true }
        guard let head = FoodText.nameWords(name).last else { return false }
        return words.contains(FoodText.stem(head))
    }

    /// A catalog food that is a drink as poured: measured in millilitres, or named one in its first
    /// part ("Beverages, coffee, brewed", "Milk, whole", "Diet Coke").
    static func isDrink(_ food: Food) -> Bool {
        food.basis == .ml || isDrink(String(food.name.split(separator: ",").first ?? ""))
    }

    /// The match is the same kind of thing as what was seen. A drink's match must be a drink, and
    /// not a powder or concentrate of one (over 200 kcal per 100 g); food must not match a drink.
    static func sameKind(_ name: String, _ food: Food) -> Bool {
        let drink = isDrink(name)
        guard drink == isDrink(food) else { return false }
        return !drink || food.basis != .g || food.nutrients.kcal <= 200
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
        (#"\b(?:skim|skimmed|nonfat|non-fat|fat-free)\b"#, "nonfat milk"), (#"\b(?:2%|semi-skimmed|reduced fat|low-fat|lowfat)\b"#, "2% milk"),
    ].map { (Pattern($0.0), $0.1) }

    private static let cupParts = Pattern(#"^(?:(?:whole|oat|almond|soy|coconut|skim|skimmed|nonfat|steamed|2%|semi-skimmed|low-fat|lowfat)\s+)*(?:milk|espresso|espresso shots?|shots? of espresso|coffee)$"#)
    private static let larger = Pattern(#"\b(?:large|grande|venti|big|extra large)\b"#)
    private static let smaller = Pattern(#"\b(?:small|tall|short|mini)\b"#)

    /// Unbranded espresso drinks as their parts, sized by count and size words; everything else as
    /// it was. A chain's drink stays whole: its nutrition is published.
    static func expand(_ foods: [SeenFood], description: String = "") -> [SeenFood] {
        let drinks = foods.filter { food in food.brand.isEmpty && recipes.contains { $0.0.matches(food.name) } }
        guard !drinks.isEmpty else { return foods }
        // The milk or espresso the model listed beside the drink is the drink's own.
        let inCup = foods.filter { $0.brand.isEmpty && cupParts.matches($0.name) && !drinks.contains($0) }
        let sized = drinks.count == 1 ? description : ""
        return foods.filter { !inCup.contains($0) }.flatMap { food -> [SeenFood] in
            guard food.brand.isEmpty, let recipe = recipes.first(where: { $0.0.matches(food.name) })?.1 else { return [food] }
            let said = food.name + " " + food.unit + " " + sized
            // A drink's ounces are fluid ounces.
            let unit = Measures.unitKey(food.unit) == "oz" ? "floz" : Measures.unitKey(food.unit)
            let cup = recipe.brewed ? 240 : recipe.espresso + recipe.milk
            // "12 oz" of one is that much; "2 lattes" or "2 cups" are two of them.
            let poured = unit == "cup" ? nil : Measures.volumes[unit].map { $0 * food.quantity }
            let size = poured.map { $0 / cup } ?? (larger.matches(said) ? 1.4 : smaller.matches(said) ? 0.75 : 1)
            let count = poured == nil ? food.quantity : 1
            let milk = milks.first { $0.0.matches(food.name) || $0.0.matches(description) }?.1 ?? "whole milk"
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
}
