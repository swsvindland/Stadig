import Foundation

/// Energy and nutrients for an amount of food. Every app and the hub count food the same way.
public struct Nutrients: Hashable, Codable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double?
    public var sugar: Double?
    public var saturatedFat: Double?
    /// Milligrams.
    public var sodium: Double?

    public init(kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double? = nil, sugar: Double? = nil,
                saturatedFat: Double? = nil, sodium: Double? = nil) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.sodium = sodium
    }

    public static let zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0)

    /// Energy from the macros (Atwater: 4/4/9), for checking a label or a guess.
    public var macroKcal: Double { protein * 4 + carbs * 4 + fat * 9 }

    public func scaled(_ factor: Double) -> Nutrients {
        Nutrients(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
                  fiber: fiber.map { $0 * factor }, sugar: sugar.map { $0 * factor },
                  saturatedFat: saturatedFat.map { $0 * factor }, sodium: sodium.map { $0 * factor })
    }

    public static func + (a: Nutrients, b: Nutrients) -> Nutrients {
        func add(_ x: Double?, _ y: Double?) -> Double? { x == nil && y == nil ? nil : (x ?? 0) + (y ?? 0) }
        return Nutrients(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat,
                         fiber: add(a.fiber, b.fiber), sugar: add(a.sugar, b.sugar),
                         saturatedFat: add(a.saturatedFat, b.saturatedFat), sodium: add(a.sodium, b.sodium))
    }

    public static func sum(_ list: [Nutrients]) -> Nutrients { list.reduce(.zero, +) }
}
