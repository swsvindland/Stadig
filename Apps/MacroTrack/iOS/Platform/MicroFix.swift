import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore

/// A food that closes a nutrient gap, at a portion people eat: one tap to log. Which foods and
/// portions count is `FoodFix`'s; this finds them in the catalog and the person's foods.
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

    /// The best fix: the most of the nutrient for the calories, at an ordinary portion that covers
    /// enough of the target, with the person's own foods preferred.
    static func find(for nutrient: NutrientInfo, target: Double, personal: [PersonalFood], catalog: FoodCatalog) -> MicroFix? {
        func make(_ food: Food, _ unit: PortionUnit, _ count: Double, yours: Bool) -> MicroFix? {
            let n = FoodUnits.nutrients(food, count: count, unit: unit)
            let amount = nutrient.key == "fiber" ? n.fiber : FoodUnits.micros(food, count: count, unit: unit)[nutrient.key]
            // Calories are `FoodFix.portion`'s to judge: it offers only a portion that fits.
            guard let amount, FoodFix.covers(amount, target: target) else { return nil }
            return MicroFix(nutrient: nutrient, food: food, unit: unit, count: count, amount: amount, kcal: n.kcal, yours: yours)
        }
        func fix(_ food: Food, lastUnitID: String?, lastCount: Double?, lastAmount: Double?, yours: Bool) -> MicroFix? {
            guard food.isPlausible else { return nil }
            let s = FoodUnits.suggested(for: food, lastUnitID: lastUnitID, lastCount: lastCount, lastAmount: lastAmount)
            return FoodFix.portion(
                usual: make(food, s.unit, s.count, yours: yours),
                others: FoodFix.otherPortions(of: food).compactMap { make(food, $0.unit, $0.count, yours: yours) }, kcal: \.kcal)
        }
        var options: [MicroFix] = []
        for p in personal {
            // Superseded by a newer search: stop rather than finish for nothing.
            if Task.isCancelled { return nil }
            if let found = fix(p.food, lastUnitID: p.lastUnitID, lastCount: p.lastCount, lastAmount: p.lastAmount, yours: true) {
                options.append(found)
            }
        }
        for name in FoodFix.nutrientStaples[nutrient.key] ?? [] {
            if Task.isCancelled { return nil }
            guard let match = catalog.candidates(name: name, brand: nil, limit: 3).first, match.score >= FoodFix.minimumMatchScore,
                let found = fix(match.food, lastUnitID: nil, lastCount: nil, lastAmount: nil, yours: false),
                !options.contains(where: { $0.food.id == found.food.id })
            else { continue }
            options.append(found)
        }
        return FoodFix.best(options, amount: \.amount, kcal: \.kcal, yours: \.yours)
    }
}

nonisolated extension FoodFix {
    /// What to try when a food's usual portion is a whole container ("1 bottle" of kefir is a
    /// quart): one of each of its own portions and servings, and the weights `gramPortions` lists.
    static func otherPortions(of food: Food) -> [(unit: PortionUnit, count: Double)] {
        let units = FoodUnits.units(for: food)
        var options = units.filter { $0.kind == .portion || $0.kind == .serving }.map { (unit: $0, count: 1.0) }
        if let grams = units.first(where: { $0.kind == .mass && $0.amount == 1 }) { options += gramPortions.map { (unit: grams, count: $0) } }
        return options
    }
}
