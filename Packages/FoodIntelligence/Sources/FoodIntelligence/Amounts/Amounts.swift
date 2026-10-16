import Foundation
import FoodDatabase

/// What a resolved count counts.
enum CountUnit: Hashable, Sendable {
    /// The food's basis: grams, millilitres or servings.
    case basis
    /// A measure the food converts: "oz", "cup", "floz", "g", "kcal"…, with basis units in one.
    case measure(String, perUnit: Double)
    /// One of the food's own portions ("slice", "large", "cup, cooked").
    case portion(index: Int, label: String, perUnit: Double)
}

/// A seen amount in a food's terms.
struct ResolvedAmount: Hashable, Sendable {
    /// Basis units: grams, millilitres or servings.
    var amount: Double
    var unit: CountUnit
    var count: Double
    /// The seen quantity converted exactly (a stated weight, a counted catalog portion), not the
    /// model's weight guess, a density assumption or a capped amount.
    var exact: Bool
}

/// Converts what the model saw to an amount of a catalog food. Catalog portions ("1 slice =
/// 113 g") beat the model's own weight guess, which is the least reliable thing it produces.
enum Amounts {
    /// No single food in a meal plausibly weighs more than 2 kg.
    static let most = 2000.0

    static func resolve(_ seen: SeenFood, food: Food) -> ResolvedAmount {
        let quantity = seen.quantity
        let unit = Measures.unitKey(seen.unit)
        let serving = food.basis == .serving

        func done(_ amount: Double, _ counted: CountUnit = .basis, count: Double? = nil, exact: Bool) -> ResolvedAmount {
            let floor = serving ? 0.1 : 1
            let capped = min(max(amount, floor), most)
            let value = (capped * (serving ? 100 : 10)).rounded() / (serving ? 100 : 10)
            let perUnit = Amounts.perUnit(counted)
            // The seen count, unless the cap changed the amount.
            let shown = count.flatMap { abs($0 * perUnit - value) <= value * 0.01 ? $0 : nil } ?? value / perUnit
            return ResolvedAmount(amount: value, unit: counted, count: rounded(shown), exact: exact && abs(capped - amount) < 1e-9)
        }

        // Grams, cups or kcal the food converts itself.
        if let perUnit = directUnits(food)[unit] { return done(quantity * perUnit, .measure(unit, perUnit: perUnit), count: quantity, exact: true) }
        let measured = Measures.weights[unit] ?? Measures.volumes[unit]
        let portions = Measures.portions(of: food)
        if serving {
            let first = portions.first { $0.index == 0 }.map(portionUnit)
            guard let measured else { return done(quantity, first ?? .basis, count: quantity, exact: true) }
            // "30 g" is 30 g worth of servings, not 30 of them. Without a serving weight it is one
            // serving, which is only a guess.
            let size = Measures.servingSize(food)
            guard let per = Measures.weights[unit] != nil ? size.weight : size.volume else { return done(1, first ?? .basis, exact: false) }
            return done(quantity * measured / per, exact: true)
        }
        if food.basis == .g, let grams = Measures.weights[unit] { return done(quantity * grams, exact: true) }
        if food.basis == .ml, let ml = Measures.volumes[unit] { return done(quantity * ml, exact: true) }

        // "1 cup, dry, yields" is what a cup of the dry food makes, not a cup of this one.
        func pick(_ list: [Measures.ParsedPortion]) -> Measures.ParsedPortion? {
            list.first { mediumOrRegular.matches(food.portions[$0.index].label) } ?? list.first { !yields.matches(food.portions[$0.index].label) }
                ?? list.first
        }
        let forms = FoodText.forms(unit)
        if let portion = pick(portions.filter({ p in forms.contains { p.noun == FoodText.stem($0) } })) {
            return done(quantity * portion.perUnit, portionUnit(portion), count: quantity, exact: true)
        }
        // "250 ml" of milk goes through its own "1 fl oz" of 30.5 g; without one, or for a drink logged
        // by weight, the model's weight or water's density.
        if let across = food.basis == .g ? Measures.volumes[unit] : Measures.weights[unit] {
            let own = food.basis == .g ? portions.first { Measures.volumes[Measures.unitKey($0.name)] != nil } : nil
            if own != nil || seen.grams == nil {
                let density = own.map { $0.perUnit / Measures.volumes[Measures.unitKey($0.name)]! } ?? 1
                return done(quantity * across * density, exact: own != nil)
            }
        }
        // "1 piece" of a food means its natural unit: a chicken breast's "breast", an egg's "large".
        // That guess is checked against the model's weight, so a lettuce "piece" never becomes a head.
        // "1 serving" of a croissant is a croissant, when the food has a portion named for it.
        if unit == "piece" || unit == "serving" || !Measures.measures.contains(unit) {
            let natural = portions.filter { !Measures.measures.contains($0.noun) }
            let own = FoodText.nameWords(seen.name).map(FoodText.stem)
            let named = pick(natural.filter { p in own.contains { FoodText.same(p.noun, $0) } })
            if let portion = named ?? (unit == "serving" ? nil : pick(natural)) {
                let grams = quantity * portion.perUnit
                // Several of something are small pieces: ten nigiri are not ten salmon fillets.
                let small = quantity < 3 || portion.perUnit <= 150
                // Counted pieces of the food, a portion named for it ("1 cookie") beats a heavier
                // guess; otherwise ("a handful" is not one almond) it may only be the guess's size,
                // give or take four times.
                let itself = named != nil && unit == "piece"
                if small, seen.grams.map({ grams < $0 * 4 && (itself || grams > $0 / 4) }) ?? true {
                    return done(grams, portionUnit(portion), count: quantity, exact: true)
                }
            }
        }
        if let grams = seen.grams { return done(quantity >= 3 ? min(grams, quantity * 75) : grams, exact: false) }
        if let first = portions.first { return done(quantity * first.perUnit, portionUnit(first), count: quantity, exact: false) }
        return done(100 * quantity, exact: false)
    }

    /// Weights, volumes and energy the food converts exactly, in basis units per one: mass for a
    /// weighed food, volume for a drink, the other kind through a plain measured portion, a
    /// serving's printed weight or volume, and kcal.
    static func directUnits(_ food: Food) -> [String: Double] {
        let massKeys = ["g", "oz"], volumeKeys = ["ml", "floz", "cup", "tbsp", "tsp"]
        var units: [String: Double] = [:]
        // The first plain portion of each measure of the other kind: "1 cup" of a weighed food.
        var own: [(String, Double)] = []
        for portion in Measures.portions(of: food) where !portion.qualified {
            guard var key = Measures.measureKey(portion.name) else { continue }
            if key == "oz" && food.basis == .ml { key = "floz" }
            let other = food.basis == .g ? Measures.volumes[key] != nil : food.basis == .ml && Measures.weights[key] != nil
            if other && !own.contains(where: { $0.0 == key }) { own.append((key, portion.perUnit)) }
        }
        switch food.basis {
        case .g:
            for key in massKeys { units[key] = Measures.weights[key] }
            if let (measure, grams) = own.first(where: { Measures.volumes[$0.0] != nil }) {
                for key in volumeKeys { units[key] = grams / Measures.volumes[measure]! * Measures.volumes[key]! }
            }
        case .ml:
            for key in volumeKeys { units[key] = Measures.volumes[key] }
            if let (measure, ml) = own.first(where: { Measures.weights[$0.0] != nil }) {
                for key in massKeys { units[key] = ml / Measures.weights[measure]! * Measures.weights[key]! }
            }
        case .serving:
            let size = Measures.servingSize(food)
            if let weight = size.weight { for key in massKeys { units[key] = Measures.weights[key]! / weight } }
            if let volume = size.volume { for key in volumeKeys { units[key] = Measures.volumes[key]! / volume } }
        }
        for (key, value) in own { units[key] = value }
        if food.nutrients.kcal > 0 { units["kcal"] = (food.basis == .serving ? 1 : 100) / food.nutrients.kcal }
        return units.filter { $0.value > 0 && $0.value.isFinite }
    }

    static func perUnit(_ unit: CountUnit) -> Double {
        switch unit {
        case .basis: 1
        case .measure(_, let perUnit), .portion(_, _, let perUnit): perUnit
        }
    }

    private static func portionUnit(_ portion: Measures.ParsedPortion) -> CountUnit {
        // A portion that is a plain serving counts servings.
        if portion.name == "serving" && abs(portion.perUnit - 1) < 1e-6 { return .measure("serving", perUnit: 1) }
        // A qualified measure ("1 cup, sliced") is its own unit, named in full; "1 breast, …" is a breast.
        let full = portion.qualified && Measures.measureKey(portion.name) != nil
        return .portion(index: portion.index, label: full ? portion.fullName : portion.name, perUnit: portion.perUnit)
    }

    /// Two decimals, or an exact third.
    private static func rounded(_ count: Double) -> Double {
        let thirds = (count * 3).rounded()
        if abs(count * 3 - thirds) < 0.015 && abs(count * 4 - (count * 4).rounded()) > 1e-9 { return thirds / 3 }
        return (count * 100).rounded() / 100
    }

    private static let mediumOrRegular = Pattern(#"\b(?:medium|regular)\b"#)
    private static let yields = Pattern(#"\byields?\b"#)
}
