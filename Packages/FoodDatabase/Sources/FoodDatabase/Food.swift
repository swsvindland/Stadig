import Foundation
import SystemCore

/// What a food's nutrient values are per: 100 g, 100 ml, or one serving (custom foods without a weight).
public enum FoodBasis: String, Codable, Sendable {
    case g, ml, serving
}

/// A household measure: "1 cup, sliced" is 150 g. `amount` is in the food's basis units.
public struct Portion: Hashable, Codable, Sendable {
    public var label: String
    public var amount: Double

    public init(label: String, amount: Double) {
        self.label = label
        self.amount = amount
    }
}

public enum FoodSource: String, Codable, Sendable {
    case usda, off, custom, recipe, label
}

/// A food from a catalog, or one of the person's own.
public struct Food: Hashable, Codable, Sendable, Identifiable {
    /// "usda:171287", "off:00016000275287", "custom:<uuid>", "recipe:<uuid>".
    public var id: String
    public var name: String
    public var brand: String?
    /// 14-digit GTIN key, when packaged.
    public var barcode: String?
    public var basis: FoodBasis
    /// Per 100 g or 100 ml, or per serving when the basis is `.serving`. Missing values are unknown, never zero.
    public var nutrients: Nutrients
    /// Further nutrients by key (cholesterol, calcium, caffeine…), same basis.
    public var extras: [String: Double]
    public var portions: [Portion]
    public var source: FoodSource
    /// For recipes and custom foods: bumps when edited, so old entries keep their snapshot.
    public var sourceVersion: Int
    /// log(1 + scans) for packaged foods; used in ranking.
    public var popularity: Double

    public init(id: String, name: String, brand: String? = nil, barcode: String? = nil, basis: FoodBasis, nutrients: Nutrients,
                extras: [String: Double] = [:], portions: [Portion] = [], source: FoodSource, sourceVersion: Int = 1,
                popularity: Double = 0) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.basis = basis
        self.nutrients = nutrients
        self.extras = extras
        self.portions = portions
        self.source = source
        self.sourceVersion = sourceVersion
        self.popularity = popularity
    }

    /// Nutrients for an amount in basis units (grams, millilitres, or servings).
    public func nutrients(for amount: Double) -> Nutrients {
        basis == .serving ? nutrients.scaled(amount) : nutrients.scaled(amount / 100)
    }

    /// `extras` for an amount in the basis: grams, millilitres or servings.
    public func extras(for amount: Double) -> [String: Double] {
        let factor = basis == .serving ? amount : amount / 100
        return extras.mapValues { $0 * factor }
    }

    /// "Cheerios · General Mills", or just the name.
    public var title: String { brand.map { "\(name) · \($0)" } ?? name }

    public var isPackaged: Bool { source == .off || barcode != nil }
}

/// One of the person's own foods (custom, recipe, favorite or recently logged), with how strongly
/// it should rank, and the amount they last logged it in.
public struct PersonalFood: Hashable, Sendable {
    public var food: Food
    /// Recency and time-of-day weighting from the log; higher ranks higher.
    public var score: Double
    public var favorite: Bool
    public var lastCount: Double?
    public var lastUnitID: String?

    public init(food: Food, score: Double, favorite: Bool = false, lastCount: Double? = nil, lastUnitID: String? = nil) {
        self.food = food
        self.score = score
        self.favorite = favorite
        self.lastCount = lastCount
        self.lastUnitID = lastUnitID
    }
}

/// A search result.
public struct FoodMatch: Hashable, Sendable, Identifiable {
    public var food: Food
    public var score: Double
    /// One of the person's own foods.
    public var personal: Bool

    public var id: String { food.id }

    public init(food: Food, score: Double, personal: Bool) {
        self.food = food
        self.score = score
        self.personal = personal
    }
}

/// Where a catalog came from and what its licence asks for.
public struct CatalogInfo: Hashable, Sendable {
    public var name: String
    public var version: String
    public var license: String
    public var attribution: String
    public var source: String
    public var foods: Int

    public init(name: String, version: String, license: String, attribution: String, source: String, foods: Int) {
        self.name = name
        self.version = version
        self.license = license
        self.attribution = attribution
        self.source = source
        self.foods = foods
    }
}
