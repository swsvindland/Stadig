import Foundation
import SystemCore

/// The day's targets a plan is sized to.
public struct PlanTargets: Hashable, Codable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public func scaled(_ share: Double) -> PlanTargets {
        PlanTargets(kcal: kcal * share, protein: protein * share, carbs: carbs * share, fat: fat * share)
    }

    public static func - (a: PlanTargets, b: Nutrients) -> PlanTargets {
        PlanTargets(kcal: max(0, a.kcal - b.kcal), protein: max(0, a.protein - b.protein), carbs: max(0, a.carbs - b.carbs),
                    fat: max(0, a.fat - b.fat))
    }
}

/// What to plan this week, and what to leave out.
public struct PlanPreferences: Hashable, Codable, Sendable {
    public enum Diet: String, Codable, Sendable, CaseIterable, Identifiable {
        case everything, pescatarian, vegetarian

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .everything: "Everything"
            case .pescatarian: "Pescatarian"
            case .vegetarian: "Vegetarian"
            }
        }

        var excluded: FoodTags {
            switch self {
            case .everything: []
            case .pescatarian: [.meat, .poultry, .pork]
            case .vegetarian: [.meat, .poultry, .pork, .fish, .shellfish]
            }
        }
    }

    /// The meals to prep. The rest are left to the person, with room kept in the targets.
    public var slots: Set<MealSlot>
    public var diet: Diet
    /// Ingredient ids and tag words ("fish", "dairy") to leave out.
    public var avoid: Set<String>
    /// Ingredient and profile ids to lean toward.
    public var want: Set<String>
    /// Lean toward the cheaper building blocks.
    public var cheaper: Bool
    /// Lean toward the quicker ones: pan and short roasts over long simmers.
    public var quicker: Bool

    public init(slots: Set<MealSlot> = [.lunch, .dinner], diet: Diet = .everything, avoid: Set<String> = [], want: Set<String> = [],
                cheaper: Bool = false, quicker: Bool = false) {
        self.slots = slots
        self.diet = diet
        self.avoid = avoid
        self.want = want
        self.cheaper = cheaper
        self.quicker = quicker
    }

    /// Tags no ingredient may have.
    var excludedTags: FoodTags {
        var tags = diet.excluded
        for word in avoid { for named in FoodTags.named where named.word == word { tags.formUnion(named.tags) } }
        return tags
    }

    /// Whether an ingredient fits the diet and isn't avoided.
    public func allows(_ ingredient: Ingredient) -> Bool {
        !avoid.contains(ingredient.id) && ingredient.tags.isDisjoint(with: excludedTags)
    }
}

/// One part of a planned meal, as eaten, with its numbers from the catalog.
public struct PlannedItem: Hashable, Codable, Sendable {
    public var ingredientID: String
    public var foodID: String
    public var name: String
    /// Grams per serving, as eaten.
    public var grams: Double
    public var nutrients: Nutrients
    public var micros: [String: Double]
    public var processing: Processing?
    public var fermented: Bool?
    /// Added when eating (kimchi, a spoon of yogurt, a banana), not packed with the rest.
    public var onTheDay: Bool

    public init(ingredientID: String, foodID: String, name: String, grams: Double, nutrients: Nutrients, micros: [String: Double],
                processing: Processing?, fermented: Bool?, onTheDay: Bool) {
        self.ingredientID = ingredientID
        self.foodID = foodID
        self.name = name
        self.grams = grams
        self.nutrients = nutrients
        self.micros = micros
        self.processing = processing
        self.fermented = fermented
        self.onTheDay = onTheDay
    }
}

/// A dish made in a batch: the same in every container.
public struct PlannedRecipe: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Protein, carb and a vegetable in a flavour.
        case bowl
        case template
    }

    /// Stable for the same dish: "bowl:teriyaki:chicken-breast:rice-white:broccoli".
    public var id: String
    public var kind: Kind
    public var title: String
    public var slots: [MealSlot]
    public var items: [PlannedItem]
    public var servings: Int
    /// Fridge days once made (0: made on the day), and whether the rest can be frozen.
    public var keeps: Int
    public var freezes: Bool
    /// For a bowl, its profile; for a template, its id.
    public var profileID: String?
    public var templateID: String?

    public var nutrients: Nutrients { items.map(\.nutrients).reduce(.zero, +) }
    /// Made fresh each day rather than on prep day.
    public var madeOnTheDay: Bool { keeps == 0 }

    public func item(_ ingredientID: String) -> PlannedItem? { items.first { $0.ingredientID == ingredientID } }
}

/// One meal on one day.
public struct PlannedMeal: Hashable, Codable, Sendable, Identifiable {
    /// Where the day's serving waits until it's eaten.
    public enum Storage: String, Codable, Sendable {
        case fridge, freezer, onTheDay
    }

    public var day: Day
    public var slot: MealSlot
    public var recipeID: String
    public var storage: Storage

    public var id: String { "\(day.iso).\(slot.rawValue)" }
}

/// A week of meals from one prep day.
public struct MealPlan: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// The first day eaten from it; prep is the day before.
    public var start: Day
    public var preferences: PlanPreferences
    public var targets: PlanTargets
    public var recipes: [PlannedRecipe]
    public var meals: [PlannedMeal]
    /// Grocery items ticked off.
    public var checked: Set<String>
    /// Planned meals logged, by meal id, with the entries made: undoing those un-logs the meal.
    public var logged: [String: [UUID]]
    public var createdAt: Date
    public var updatedAt: Date

    public static let length = 7

    public var prepDay: Day { start.adding(days: -1) }
    public var days: [Day] { (0..<Self.length).map { start.adding(days: $0) } }
    public var end: Day { start.adding(days: Self.length - 1) }

    public func recipe(_ id: String) -> PlannedRecipe? { recipes.first { $0.id == id } }
    public func meals(on day: Day) -> [PlannedMeal] { meals.filter { $0.day == day }.sorted { $0.slot < $1.slot } }
    public func covers(_ day: Day) -> Bool { day >= start && day <= end }

    /// What the planned meals add up to on a day.
    public func planned(on day: Day) -> Nutrients {
        meals(on: day).compactMap { recipe($0.recipeID)?.nutrients }.reduce(.zero, +)
    }

    /// The meals left to the person on a day, each with the room the targets keep for it.
    public func unplanned(on day: Day) -> [(slot: MealSlot, room: PlanTargets)] {
        let open = MealSlot.allCases.filter { !preferences.slots.contains($0) }
        let share = open.map(\.share).reduce(0, +)
        guard share > 0 else { return [] }
        let left = targets - planned(on: day)
        return open.map { ($0, left.scaled($0.share / share)) }
    }
}
