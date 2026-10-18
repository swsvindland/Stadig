import Foundation
import SystemCore

/// One line of the shopping list: how much to buy, raw or dry, in the units it's sold in.
public struct GroceryItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var aisle: Aisle
    /// Grams to buy: raw meat, dry rice, drained beans.
    public var grams: Double
    /// Whole units, when it's sold that way: 3 cans.
    public var count: Int?
    public var unit: String?
    /// The size on the shelf: "500 g".
    public var size: String?
    /// Millilitres rather than grams.
    public var liquid: Bool
    /// A kitchen staple that's probably already there.
    public var pantry: Bool
    /// The dishes it's for.
    public var uses: [String]
}

public enum Groceries {
    /// Everything the week's prepped and planned meals need, by aisle, with spices last.
    public static func list(for plan: MealPlan) -> [GroceryItem] {
        var byName: [String: (ingredient: Ingredient, grams: Double, uses: [String])] = [:]
        for recipe in plan.recipes {
            for item in recipe.items {
                guard let ingredient = Library.ingredient(item.ingredientID) else { continue }
                // Eggs for muffins and eggs to boil are one carton.
                let key = ingredient.name
                let bought = item.grams * Double(recipe.servings) / ingredient.yield
                var entry = byName[key] ?? (ingredient, 0, [])
                entry.grams += bought
                if !entry.uses.contains(recipe.title) { entry.uses.append(recipe.title) }
                byName[key] = entry
            }
        }
        var items = byName.map { name, entry -> GroceryItem in
            let ingredient = entry.ingredient
            var count: Int?
            var unit: String?
            var size: String?
            if let buy = ingredient.unit {
                size = buy.size
                // Within a tenth of a whole unit is close enough: 2.08 cans is 2.
                let n = max(1, Int((entry.grams / buy.grams - 0.1).rounded(.up)))
                count = n
                unit = n == 1 ? buy.name : buy.plural
            }
            return GroceryItem(
                id: ingredient.id, name: name, aisle: ingredient.aisle, grams: roundUp(entry.grams), count: count, unit: unit,
                size: size, liquid: ingredient.liquid, pantry: ingredient.pantry, uses: entry.uses)
        }
        let aisles = Aisle.allCases
        items.sort { a, b in
            a.pantry != b.pantry
                ? !a.pantry
                : (a.aisle != b.aisle ? aisles.firstIndex(of: a.aisle)! < aisles.firstIndex(of: b.aisle)! : a.name < b.name)
        }
        return items
            + spices(for: plan).map {
                GroceryItem(
                    id: "spice:\($0)", name: $0, aisle: .pantry, grams: 0, count: nil, unit: nil, size: nil, liquid: false, pantry: true,
                    uses: [])
            }
    }

    /// The herbs, spices and aromatics the week's flavours use, with salt and pepper.
    public static func spices(for plan: MealPlan) -> [String] {
        var seen: [String] = []
        for recipe in plan.recipes {
            for spice in recipe.profileID.flatMap(Library.profile)?.spices ?? [] where !seen.contains(spice) { seen.append(spice) }
        }
        return seen.isEmpty ? [] : seen + ["Salt and pepper"]
    }

    /// To the next 10 g, or 50 g above 200 g: what a scale at the counter shows.
    static func roundUp(_ grams: Double) -> Double {
        let step = grams >= 200 ? 50.0 : 10.0
        return (grams / step).rounded(.up) * step
    }
}
