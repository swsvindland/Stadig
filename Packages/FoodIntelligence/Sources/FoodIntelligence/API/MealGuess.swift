import FoodDatabase
import Foundation
import SystemCore

/// Which of Apple's models answered.
public enum MealEngine: String, Hashable, Sendable {
    /// `SystemLanguageModel`, on this device.
    case onDevice
    /// Apple's Private Cloud Compute (iOS 27).
    case privateCloud
}

/// A meal read from a photo or a description: the foods seen, each matched to the catalog with an
/// amount. Nothing here is logged until the person confirms it.
public struct MealGuess: Sendable {
    /// What a photo really shows, in a few words ("a plate of spaghetti", "a dog on a couch"); nil
    /// for a description.
    public var scene: String?
    /// False when a photo shows no recognizable food: `items` is empty and `scene` says what it shows.
    public var isFood: Bool
    public var items: [GuessedItem]
    public var engine: MealEngine
    /// Wall-clock time of the whole recognition.
    public var seconds: Double

    public init(scene: String?, isFood: Bool, items: [GuessedItem], engine: MealEngine, seconds: Double) {
        self.scene = scene
        self.isFood = isFood
        self.items = items
        self.engine = engine
        self.seconds = seconds
    }

    /// The meal's total from the matched foods.
    public var nutrients: Nutrients { Nutrients.sum(items.map(\.nutrients)) }
}

/// One food the model named, matched to a catalog food. The model only names foods and amounts;
/// `nutrients` always come from the matched catalog food.
public struct GuessedItem: Sendable, Identifiable {
    public var id: UUID
    /// What the model called it: "Pepperoni pizza", "Scrambled eggs".
    public var seenName: String
    /// A brand or restaurant chain read in the photo or said in the description.
    public var seenBrand: String?
    /// The best catalog match; nil when the catalog had nothing.
    public var match: FoodMatch?
    /// Other matches to swap to with one tap, best first, at most five; never includes `match`.
    /// A branded guess keeps a plain food here, so a misread brand costs one tap.
    public var alternatives: [FoodMatch]
    /// What `count` counts: one of `FoodUnits.units(for:)` when the catalog offers a matching unit,
    /// otherwise an equivalent unit of the same size. Nil without a match.
    public var unit: PortionUnit?
    public var count: Double
    /// For `count` of `unit` of the matched food; zero without a match.
    public var nutrients: Nutrients
    /// The match is strong enough to log without asking. When false, `match` is a weak best guess
    /// to confirm or swap: a wrong food in the log is worse than a missing one.
    public var sure: Bool
    /// The amount is an estimate ("≈"): the model's weight guess, a photo, or a size the person
    /// didn't state.
    public var approximate: Bool

    public init(
        id: UUID = UUID(), seenName: String, seenBrand: String?, match: FoodMatch?, alternatives: [FoodMatch],
        unit: PortionUnit?, count: Double, nutrients: Nutrients, sure: Bool, approximate: Bool
    ) {
        self.id = id
        self.seenName = seenName
        self.seenBrand = seenBrand
        self.match = match
        self.alternatives = alternatives
        self.unit = unit
        self.count = count
        self.nutrients = nutrients
        self.sure = sure
        self.approximate = approximate
    }
}

/// A nutrition label photo read into a custom food's values.
public struct LabelResult: Sendable {
    /// The parsed panel, per serving; nil when no panel could be read.
    public var reading: LabelReading?
    /// The text read from the photo, top to bottom, each printed row joined left to right.
    public var lines: [String]
    /// A product name the model suggests from the label's text (the panel itself rarely names it).
    public var suggestedName: String?
    public var brand: String?

    public init(reading: LabelReading?, lines: [String], suggestedName: String?, brand: String?) {
        self.reading = reading
        self.lines = lines
        self.suggestedName = suggestedName
        self.brand = brand
    }
}

/// Why recognition could not run or finish. Messages are written for the person.
public enum MealAIError: Error, LocalizedError, Equatable, Sendable {
    /// No model can do this on this device right now (the reason says why and what to change).
    case unavailable(String)
    /// A description named no food or drink.
    case notFood(String)
    /// The model is busy or took too long; try again in a moment.
    case busy
    /// The model declined the request.
    case refused
    /// The description is too long for the model.
    case tooLong
    /// Private Cloud Compute's quota is used up until the date, when known.
    case quotaReached(Date?)
    /// Private Cloud Compute couldn't be reached.
    case network
    /// The model's reply could not be used, or another unexpected failure.
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .notFood(let reason): reason
        case .busy: "The model is busy. Try again in a moment."
        case .refused: "The model declined this request. Try describing the meal differently."
        case .tooLong: "That description is too long. Try a shorter one."
        case .quotaReached(let date):
            date.map { "The Private Cloud Compute limit is reached until \($0.formatted(date: .omitted, time: .shortened))." }
                ?? "The Private Cloud Compute limit is reached. Try again later."
        case .network: "Private Cloud Compute couldn't be reached. Check the connection and try again."
        case .failed(let reason): reason
        }
    }
}

/// A Supplement Facts photo, read.
public struct SupplementLabelResult: Sendable {
    /// The panel's serving and lines; nil when no panel could be read. Its name is empty.
    public var facts: SupplementFacts?
    public var lines: [String]
    public var suggestedName: String?
    public var brand: String?

    public init(facts: SupplementFacts?, lines: [String], suggestedName: String?, brand: String?) {
        self.facts = facts
        self.lines = lines
        self.suggestedName = suggestedName
        self.brand = brand
    }
}
