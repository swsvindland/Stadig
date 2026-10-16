import Foundation
import FoodDatabase
import NutritionEngine
import SystemCore

/// A fermented food at a portion people eat, for a week short of them: one tap to log.
nonisolated struct FermentedFix: Hashable, Sendable {
    var food: Food
    var unit: PortionUnit
    var count: Double
    var kcal: Double
    /// One the person already eats.
    var yours: Bool

    var portion: String { FoodUnits.label(count: count, unit: unit) }

    /// Plain ones first: flavoured yogurts are often ultra-processed.
    static let staples = ["plain greek yogurt", "kefir", "plain yogurt", "skyr", "sauerkraut", "kimchi"]

    /// The person's own fermented foods first (the one they log most), else the first everyday one
    /// the catalog has.
    static func find(personal: [PersonalFood], catalog: FoodCatalog) -> FermentedFix? {
        let yours = personal.filter { $0.food.fermented ?? Fermented.isFermented($0.food.name) }
            .filter { $0.food.processing != .ultraProcessed }
            .sorted { $0.score > $1.score }
        for p in yours {
            if let fix = make(p.food, lastUnitID: p.lastUnitID, lastCount: p.lastCount, yours: true) { return fix }
        }
        for name in staples {
            guard let match = catalog.candidates(name: name, brand: nil, limit: 3).first, match.score >= 1.5,
                  match.food.fermented == true || Fermented.isFermented(match.food.name),
                  let fix = make(match.food, lastUnitID: nil, lastCount: nil, yours: false) else { continue }
            return fix
        }
        return nil
    }

    /// The usual portion, unless it's a whole container: then the portion nearest a snack's 150 kcal.
    static func make(_ food: Food, lastUnitID: String?, lastCount: Double?, yours: Bool) -> FermentedFix? {
        guard food.isPlausible else { return nil }
        func option(_ unit: PortionUnit, _ count: Double) -> FermentedFix? {
            let kcal = FoodUnits.nutrients(food, count: count, unit: unit).kcal
            return kcal > 0 && kcal <= 300 ? FermentedFix(food: food, unit: unit, count: count, kcal: kcal, yours: yours) : nil
        }
        let s = FoodUnits.suggested(for: food, lastUnitID: lastUnitID, lastCount: lastCount)
        if let usual = option(s.unit, s.count) { return usual }
        let units = FoodUnits.units(for: food)
        var options = units.filter { $0.kind == .portion || $0.kind == .serving }.compactMap { option($0, 1) }
        if let grams = units.first(where: { $0.kind == .mass && $0.amount == 1 }) { options += [100.0, 150].compactMap { option(grams, $0) } }
        return options.min { abs($0.kcal - 150) < abs($1.kcal - 150) }
    }
}

/// What to eat instead of an ultra-processed food, in a line: the same job done by whole foods.
nonisolated enum QualitySwap {
    static func advice(for source: QualityReport.Source) -> String {
        let name = source.name.lowercased()
        let n = source.entry.nutrients
        let kcal = max(1, n.kcal)
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        if has("shake", "powder", "whey", "protein", "isolate") || n.protein * 4 / kcal >= 0.3 && !has("bar") {
            return "Greek yogurt, skyr, eggs or cottage cheese give the same protein as whole food."
        }
        if has("bar") {
            return "Fruit and a handful of nuts, or Greek yogurt if it's the protein you're after."
        }
        if has("soda", "cola", "coke", "pepsi", "sprite", "fanta", "lemonade", "energy drink", "soft drink", "iced tea", "sports drink",
               "red bull", "monster", "gatorade", "drink") {
            return "Water, sparkling water or milk: drinks are the easiest calories to cut, and don't fill you up."
        }
        if has("chip", "crisp", "cracker", "pretzel", "puff", "cheeto", "dorito", "pringle", "snack") {
            return "A handful of nuts, or popcorn you pop yourself, for the salty crunch."
        }
        let meal = "The same meal cooked from whole foods: meat or fish, rice or potatoes, and vegetables. Cooked in a batch, it's as quick."
        if has("pizza", "burger", "burrito", "lasagna", "entree", "dinner", " meal", "sandwich", "taco") { return meal }
        if has("sausage", "bacon", "hot dog", "frankfurter", "nugget", "salami", "pepperoni", "bologna", "deli", "luncheon", "ham") {
            return "Chicken, eggs or fish cooked plain do the same job with less salt."
        }
        if has("cereal", "pop-tart", "pop tart", "toaster", "waffle", "pancake", "pastr", "muffin", "granola", "croissant", "danish") {
            return "Oats with fruit fill the same spot, with fiber that keeps you full until lunch."
        }
        if has("bread", "bun", "bagel", "wrap", "tortilla") {
            return "A bakery loaf, or potatoes and rice for the starch."
        }
        if let sugar = n.sugar, sugar * 4 / kcal >= 0.35 {
            return "Fruit, or yogurt with honey, for the sweet spot."
        }
        return meal
    }
}
