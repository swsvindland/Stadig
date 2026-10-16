import Foundation
import FoodDatabase
import NutritionEngine
import SystemCore

/// A food that closes a nutrient gap, at a portion people eat: one tap to log.
nonisolated struct MicroFix: Hashable, Sendable {
    var nutrient: NutrientInfo
    var food: Food
    var unit: PortionUnit
    var count: Double
    /// How much of the nutrient the portion has.
    var amount: Double
    var kcal: Double
    /// One the person already eats.
    var yours: Bool

    var portion: String { FoodUnits.label(count: count, unit: unit) }

    /// Everyday foods rich in each nutrient, found in the catalog by name.
    static let staples: [String: [String]] = [
        "fiber": ["raspberries", "lentils", "black beans", "chia seeds", "pear", "oatmeal", "split peas"],
        "potassium": ["potato", "banana", "white beans", "spinach", "avocado", "plain yogurt", "lentils"],
        "magnesium": ["pumpkin seeds", "almonds", "spinach", "black beans", "cashews", "edamame"],
        "calcium": ["greek yogurt", "milk", "cheddar cheese", "tofu", "sardines", "kefir"],
        "iron": ["lentils", "beef", "spinach", "tofu", "chickpeas", "pumpkin seeds"],
        "vitaminC": ["orange", "kiwi", "red bell pepper", "strawberries", "broccoli"],
        "folate": ["lentils", "spinach", "asparagus", "avocado", "edamame", "chickpeas"],
        "vitaminB12": ["salmon", "eggs", "milk", "greek yogurt", "beef", "tuna"],
    ]

    /// The best fix: the most of the nutrient for the calories, at an ordinary portion that covers
    /// at least a sixth of the target, with the person's own foods preferred.
    static func find(for nutrient: NutrientInfo, target: Double, personal: [PersonalFood], catalog: FoodCatalog) -> MicroFix? {
        func make(_ food: Food, _ unit: PortionUnit, _ count: Double, yours: Bool) -> MicroFix? {
            let n = FoodUnits.nutrients(food, count: count, unit: unit)
            let amount = nutrient.key == "fiber" ? n.fiber : FoodUnits.micros(food, count: count, unit: unit)[nutrient.key]
            guard let amount, amount >= target / 6, n.kcal > 0 else { return nil }
            return MicroFix(nutrient: nutrient, food: food, unit: unit, count: count, amount: amount, kcal: n.kcal, yours: yours)
        }
        func fix(_ food: Food, lastUnitID: String?, lastCount: Double?, yours: Bool) -> MicroFix? {
            guard food.isPlausible else { return nil }
            // The usual portion, unless it's a whole container ("1 bottle" of kefir is a quart):
            // then the food's portion nearest a snack's 150 kcal.
            let s = FoodUnits.suggested(for: food, lastUnitID: lastUnitID, lastCount: lastCount)
            if let usual = make(food, s.unit, s.count, yours: yours), usual.kcal <= 300 { return usual }
            let units = FoodUnits.units(for: food)
            var options = units.filter { $0.kind == .portion || $0.kind == .serving }.compactMap { make(food, $0, 1, yours: yours) }
            if let grams = units.first(where: { $0.kind == .mass && $0.amount == 1 }) {
                options += [100.0, 150].compactMap { make(food, grams, $0, yours: yours) }
            }
            return options.filter { $0.kcal <= 300 }.min { abs($0.kcal - 150) < abs($1.kcal - 150) }
        }
        var options = personal.compactMap { fix($0.food, lastUnitID: $0.lastUnitID, lastCount: $0.lastCount, yours: true) }
        for name in staples[nutrient.key] ?? [] {
            guard let match = catalog.candidates(name: name, brand: nil, limit: 3).first, match.score >= 1.5,
                  let found = fix(match.food, lastUnitID: nil, lastCount: nil, yours: false),
                  !options.contains(where: { $0.food.id == found.food.id }) else { continue }
            options.append(found)
        }
        // Per calorie, and a little ahead for a food already eaten.
        return options.max { a, b in a.amount / a.kcal * (a.yours ? 1.3 : 1) < b.amount / b.kcal * (b.yours ? 1.3 : 1) }
    }
}
