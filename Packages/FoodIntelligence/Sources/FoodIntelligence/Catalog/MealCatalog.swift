import FoodDatabase
import Foundation

/// What meal recognition needs from a food catalog. `FoodCatalog` conforms; tests use a small
/// in-memory one.
public protocol MealCatalog: Sendable {
    /// Candidates for a food a model saw or a person described: specific to broad, ranked best
    /// first, with the person's own foods where they match.
    func candidates(name: String, brand: String?, personal: [PersonalFood], limit: Int) -> [FoodMatch]

    /// Every sensible unit for a food, the most natural first.
    func units(for food: Food) -> [PortionUnit]
}

extension MealCatalog {
    public func units(for food: Food) -> [PortionUnit] { FoodUnits.units(for: food) }
}

extension FoodCatalog: MealCatalog {}
