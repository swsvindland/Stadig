import Foundation
import SystemCore

/// What the scale read on prep day, against what the plan asked for. A batch is shared evenly
/// between its containers, so 412 g of rice where the plan said 400 puts 3% more rice, and 3% more
/// of the rice's numbers, in every container that has it.
public struct PrepReadings: Hashable, Sendable {
    /// Grams read off the scale, by step id. A reading of zero or less is no reading.
    public var grams: [Int: Double]

    public init(grams: [Int: Double] = [:]) {
        self.grams = grams
    }

    /// Read over planned for each weighed part of each dish: recipe id, then ingredient id.
    func factors(in guide: PrepGuide) -> [String: [String: Double]] {
        var factors: [String: [String: Double]] = [:]
        for step in guide.steps {
            guard let weigh = step.weigh, weigh.grams > 0, let read = grams[step.id], read > 0 else { continue }
            for dish in weigh.dishes { factors[dish, default: [:]][weigh.ingredientID] = read / weigh.grams }
        }
        return factors
    }

    /// The dishes as weighed: each part read off the scale holds read over planned of its planned
    /// grams in every container, its nutrients and micronutrients with it. Parts and dishes nothing
    /// was read for are as planned. Always from the dishes as planned, so a reading changed twice
    /// isn't applied twice.
    public func apply(to recipes: [PlannedRecipe], guide: PrepGuide) -> [PlannedRecipe] {
        let factors = factors(in: guide)
        guard !factors.isEmpty else { return recipes }
        return recipes.map { recipe in
            guard let parts = factors[recipe.id] else { return recipe }
            var recipe = recipe
            recipe.items = recipe.items.map { item in
                guard let factor = parts[item.ingredientID], !item.onTheDay else { return item }
                return item.scaled(factor)
            }
            return recipe
        }
    }

    /// A step's reading, container by container: for each dish the batch goes in, what one
    /// container gains or loses against the plan.
    public func changes(for step: PrepStep, in recipes: [PlannedRecipe], guide: PrepGuide) -> [PrepChange] {
        guard let weigh = step.weigh, let read = grams[step.id], read > 0 else { return [] }
        let alone = PrepReadings(grams: [step.id: read]).apply(to: recipes, guide: guide)
        return zip(recipes, alone).compactMap { planned, weighed in
            guard weigh.dishes.contains(planned.id) else { return nil }
            let a = planned.nutrients
            let b = weighed.nutrients
            return PrepChange(
                recipeID: planned.id, title: planned.title, servings: planned.servings, kcal: b.kcal - a.kcal, protein: b.protein - a.protein)
        }
    }
}

/// What one container of a dish gains (or loses) from a reading.
public struct PrepChange: Hashable, Sendable, Identifiable {
    public var recipeID: String
    public var title: String
    /// Containers of it.
    public var servings: Int
    public var kcal: Double
    public var protein: Double

    public var id: String { recipeID }
}

extension PlannedItem {
    /// The same food, `factor` times as much.
    func scaled(_ factor: Double) -> PlannedItem {
        var item = self
        item.grams *= factor
        item.nutrients = nutrients.scaled(factor)
        item.micros = micros.mapValues { $0 * factor }
        return item
    }
}
