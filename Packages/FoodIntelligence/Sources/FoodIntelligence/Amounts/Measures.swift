import Foundation
import FoodDatabase

/// Weights, volumes and the words people and catalogs write them with.
enum Measures {
    /// Grams in one.
    static let weights: [String: Double] = ["g": 1, "oz": 28.3495, "lb": 453.592, "kg": 1000]
    /// Millilitres in one.
    static let volumes: [String: Double] = [
        "ml": 1, "l": 1000, "cup": 240, "tbsp": 15, "tsp": 5, "floz": 29.5735, "pint": 473, "quart": 946, "gallon": 3785,
    ]

    /// Units that measure food, not count it: "2 cups" is an amount, "2 slices" a count.
    static let measures: Set<String> = [
        "cup", "tbsp", "tablespoon", "tsp", "teaspoon", "oz", "ounce", "lb", "pound", "g", "gram", "kg", "ml", "fl", "floz", "l",
        "liter", "pint", "quart", "gallon", "package", "pkg", "container", "can", "bottle", "jar", "box", "bag", "scoop", "stick",
        "pat", "serving", "order", "portion", "cubic", "inch", "unit", "yield", "onz", "kcal",
    ]

    // stem() leaves words of three letters alone, so short plurals are listed too.
    private static let unitNames: [String: String] = [
        "tablespoon": "tbsp", "tbs": "tbsp", "teaspoon": "tsp", "ounce": "oz", "ozs": "oz", "pound": "lb", "lbs": "lb",
        "gram": "g", "grams": "g", "gms": "g", "gm": "g", "kilogram": "kg", "kilo": "kg", "kgs": "kg", "milliliter": "ml",
        "mls": "ml", "millilitre": "ml", "liter": "l", "litre": "l", "qt": "quart", "gal": "gallon", "portion": "serving",
        "order": "serving", "plate": "serving", "bowl": "serving", "helping": "serving", "pc": "piece", "each": "piece",
        "item": "piece", "whole": "piece", "unit": "piece", "count": "piece", "onz": "oz", "cal": "kcal", "calorie": "kcal",
    ]

    private static let fluidOunce = Pattern(#"\bfl(?:uid)?\.?\s*(?:oz|ounces?)\b"#)

    /// The unit a seen amount counts, normalised: "tablespoons" → "tbsp", "fl. oz." → "floz", "each" → "piece".
    static func unitKey(_ unit: String) -> String {
        let list = FoodText.words(fluidOunce.replacing(in: unit, with: "floz"))
        let first = list.first ?? "piece"
        let word = FoodText.stem(first)
        return unitNames[word] ?? unitNames[first] ?? word
    }

    private static let measureNames: [(Pattern, String)] = [
        (Pattern(#"^f(?:l(?:uid)?)?\.? ?(?:oz|ounces?)$"#), "floz"),
        (Pattern("^(?:g|gr|gms?|grams?|grammes?)$"), "g"),
        (Pattern("^(?:oz|oza|onz|ounces?)$"), "oz"),
        (Pattern("^(?:lbs?|pounds?)$"), "lb"),
        (Pattern("^(?:kg|kgs|kilos?|kilograms?)$"), "kg"),
        (Pattern("^(?:ml|mls|milliliters?|millilitres?)$"), "ml"),
        (Pattern("^(?:l|liters?|litres?)$"), "l"),
        (Pattern("^cups?$"), "cup"),
        (Pattern("^(?:tbsp|tbs|tbl|tablespoons?)$"), "tbsp"),
        (Pattern("^(?:tsp|teaspoons?)$"), "tsp"),
        (Pattern("^servings?$"), "serving"),
    ]

    /// The measure a catalog portion's unit spells exactly: "floz" for "fl. oz.", "cup" for "cups"; nil for "slice".
    static func measureKey(_ name: String) -> String? {
        var text = FoodText.clean(name.lowercased(), limit: 200)
        if text.hasSuffix(".") { text.removeLast() }
        return measureNames.first { $0.0.matches(text) }?.1
    }

    private static let glyphs: [(Double, Character)] = [(0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")]
    private static let glyphAmount = Pattern("^(\\d+)? ?([¼⅓½⅔¾])$")
    private static let fractionAmount = Pattern(#"^(?:(\d+) )?(\d+)/(\d+)$"#)
    private static let decimalAmount = Pattern(#"^(?:\d+\.?\d*|\.\d+)$"#)

    /// "1 1/2", "1½", ".5" → a number.
    static func parseAmount(_ input: String) -> Double? {
        let text = FoodText.clean(input.replacingOccurrences(of: ",", with: "."), limit: 40)
        if let parts = glyphAmount.allMatches(in: text).first, let glyph = parts[2].first,
           let part = glyphs.first(where: { $0.1 == glyph })?.0 {
            return (Double(parts[1]) ?? 0) + part
        }
        if let parts = fractionAmount.allMatches(in: text).first, let top = Double(parts[2]), let bottom = Double(parts[3]) {
            return bottom > 0 ? (Double(parts[1]) ?? 0) + top / bottom : nil
        }
        return decimalAmount.matches(text) ? Double(text) : nil
    }

    private static let portionCount = Pattern(#"^\s*(\d+\s+\d+/\d+|\d+/\d+|\d*\.\d+|\d+)\s+(.+)$"#)
    private static let portionCut = Pattern(#"[,(]|\s\d"#)

    /// A catalog portion as a count of a named unit: "2 SLICES (57 g)" is 2 of a 28.5 g "slice".
    struct ParsedPortion: Hashable, Sendable {
        var index: Int
        var count: Double
        /// "slice", "cup", "large".
        var name: String
        /// Basis units in one.
        var perUnit: Double
        /// The word one portion counts: "slice" in "1 slice, medium", "serving" in "1 large serving".
        var noun: String
        /// "1 cup, sliced" is its own unit, unlike a plain "1 cup".
        var qualified: Bool
        /// The label without its count, as a unit's name: "cup, sliced".
        var fullName: String
    }

    static func parsePortion(_ portion: Portion, index: Int) -> ParsedPortion? {
        let parts = portionCount.allMatches(in: portion.label).first
        let count = parts.map { parseAmount($0[1]) ?? 0 } ?? 1
        // "1 roll 1 serving" and "1 cup, chopped (1/2" pieces)" are a "roll" and a "cup".
        let rest = parts?[2] ?? portion.label
        var name = (portionCut.splitKeepingMatches(rest).first ?? rest).trimmingCharacters(in: .whitespaces).lowercased()
        // Some packaged-food portions are only a weight ("1 151.0g"), which names no unit.
        guard !name.isEmpty, !(name.first?.isNumber ?? true), count > 0, portion.amount > 0 else { return nil }
        if count > 1 && measureKey(name) == nil { name = singular(name) }
        let words = FoodText.words(name).map(FoodText.stem)
        let noun = words.first { !FoodText.sizes.contains($0) } ?? words.first ?? ""
        let unqualified = brackets.replacing(in: portion.label, with: "")
        return ParsedPortion(index: index, count: count, name: name, perUnit: portion.amount / count, noun: noun,
                             qualified: unqualified.contains(","), fullName: String(rest.lowercased().prefix(32)))
    }

    static func portions(of food: Food) -> [ParsedPortion] {
        food.portions.enumerated().compactMap { parsePortion($0.element, index: $0.offset) }
    }

    private static let brackets = Pattern(#"\([^)]*\)"#)
    private static let esPlural = Pattern("(?:ch|sh|x)es$")
    private static let sPlural = Pattern("[^su]s$")

    private static func singular(_ name: String) -> String {
        if esPlural.matches(name) { return String(name.dropLast(2)) }
        if sPlural.matches(name) { return String(name.dropLast()) }
        return name
    }

    private static let sizeAmounts = Pattern(#"(\d+\s+\d+/\d+|\d+/\d+|\d*\.\d+|\d+)\s*(fl(?:uid)?\.?\s*(?:oz|ounces?)\b|[a-z]+)"#)

    /// A per-serving food's serving weight (g) and volume (ml), when its label gives them:
    /// "1 serving (30 g)", "1 serving (2 tbsp (32g))".
    static func servingSize(_ food: Food) -> (weight: Double?, volume: Double?) {
        var weight: Double?, volume: Double?
        for portion in food.portions {
            for match in sizeAmounts.allMatches(in: portion.label) {
                let unit = measureKey(match[2]) ?? ""
                let per = weights[unit] ?? volumes[unit] ?? 0
                let amount = (parseAmount(match[1]) ?? 0) * per / portion.amount
                guard amount > 0, amount.isFinite else { continue }
                if weights[unit] != nil { weight = weight ?? amount } else { volume = volume ?? amount }
            }
        }
        return (weight, volume)
    }

    /// How many of something one serving of a per-serving food holds, when its first portion says
    /// and it isn't one: "1 serving (3 cookies)" is 3 of a "cookie", "1 serving (1/2 bar)" half a
    /// "bar". Weights and volumes are left to `servingSize`.
    static func servingCount(_ food: Food) -> (count: Double, noun: String)? {
        guard let portion = food.portions.first, let serving = parsePortion(portion, index: 0), measureKey(serving.name) == "serving",
              let inside = brackets.firstMatch(in: portion.label).map({ String($0.dropFirst().dropLast()) }),
              let held = parsePortion(Portion(label: inside, amount: portion.amount), index: 0), measureKey(held.name) == nil
        else { return nil }
        let count = held.count / portion.amount
        return count.isFinite && count > 0 && abs(count - 1) > 1e-9 ? (count, held.noun) : nil
    }
}
