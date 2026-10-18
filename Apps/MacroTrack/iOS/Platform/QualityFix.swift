import FoodDatabase
import Foundation
import NutritionEngine
import SystemCore

/// A fermented food at a portion people eat, for a week short of them: one tap to log. What to
/// offer and at what portion is `FoodFix`'s; this finds it. (The swap for an ultra-processed food
/// is `QualitySwap`, in NutritionEngine.)
nonisolated struct FermentedFix: Hashable, Sendable {
    var food: Food
    var unit: PortionUnit
    var count: Double
    var kcal: Double
    /// One the person already eats.
    var yours: Bool

    var portion: String { FoodUnits.label(count: count, unit: unit) }

    /// The person's own fermented foods first (the one they log most), else the first everyday one
    /// the catalog has.
    static func find(personal: [PersonalFood], catalog: FoodCatalog) -> FermentedFix? {
        let yours = personal.filter { $0.food.fermented ?? Fermented.isFermented($0.food.name) }
            .filter { $0.food.processing != .ultraProcessed }
            .sorted { $0.score > $1.score }
        for p in yours {
            if Task.isCancelled { return nil }
            if let fix = make(p.food, lastUnitID: p.lastUnitID, lastCount: p.lastCount, lastAmount: p.lastAmount, yours: true) { return fix }
        }
        for name in FoodFix.fermentedStaples {
            if Task.isCancelled { return nil }
            guard let match = catalog.candidates(name: name, brand: nil, limit: 3).first, match.score >= FoodFix.minimumMatchScore,
                match.food.fermented == true || Fermented.isFermented(match.food.name),
                let fix = make(match.food, lastUnitID: nil, lastCount: nil, lastAmount: nil, yours: false)
            else { continue }
            return fix
        }
        return nil
    }

    /// The usual portion, unless it's a whole container: then the portion nearest a snack's calories.
    static func make(_ food: Food, lastUnitID: String?, lastCount: Double?, lastAmount: Double?, yours: Bool) -> FermentedFix? {
        guard food.isPlausible else { return nil }
        func option(_ unit: PortionUnit, _ count: Double) -> FermentedFix {
            FermentedFix(food: food, unit: unit, count: count, kcal: FoodUnits.nutrients(food, count: count, unit: unit).kcal, yours: yours)
        }
        let s = FoodUnits.suggested(for: food, lastUnitID: lastUnitID, lastCount: lastCount, lastAmount: lastAmount)
        return FoodFix.portion(
            usual: option(s.unit, s.count), others: FoodFix.otherPortions(of: food).map { option($0.unit, $0.count) }, kcal: \.kcal)
    }
}
