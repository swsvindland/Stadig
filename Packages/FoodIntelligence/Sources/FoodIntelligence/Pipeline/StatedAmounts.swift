import Foundation

/// Amounts the person said ("8 oz steak", "two eggs", "half a bagel", "ate 3 slices") override the
/// model's, which sometimes drops or rewrites them. Read by rule, so a stated amount is never lost.
enum StatedAmounts {
    private static let numbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "single": 1, "two": 2, "couple": 2, "pair": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "dozen": 12, "half": 0.5,
    ]
    private static let separators = Pattern(#",|;|\band\b|\bwith\b|\bplus\b|\bthen\b"#)
    private static let amount = Pattern(#"(?:^|\s)(\d+(?:\.\d+)?|\d+/\d+|[½¼¾⅓⅔]|a|an|one|single|two|couple(?: of)?|pair(?: of)?|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozen|half(?: an?)?)\s*"#
        + #"(g|grams?|gr|kg|kilos?|oz|ounces?|lbs?|pounds?|ml|l|lit(?:er|re)s?|fl\.? ?oz|cups?|tbsp|tablespoons?|tsp|teaspoons?|slices?|pieces?|cans?|bottles?|glass(?:es)?|mugs?|scoops?|strips?|bowls?|plates?|servings?)?\b\.?\s*(?:of\s+)?(.*)$"#)

    static func apply(_ foods: [SeenFood], said: String) -> [SeenFood] {
        guard !foods.isEmpty else { return foods }
        var foods = foods
        for segment in separators.splitKeepingMatches(FoodText.plain(said)).enumerated().filter({ $0.offset.isMultiple(of: 2) }).map(\.element) {
            guard let parts = amount.allMatches(in: segment).first else { continue }
            let word = parts[1].replacingOccurrences(of: " of", with: "").replacingOccurrences(of: " an", with: "").replacingOccurrences(of: " a", with: "")
            guard let count = numbers[word] ?? Measures.parseAmount(word), count > 0 else { continue }
            let unit = parts[2], rest = parts[3]
            let target: Int?
            if FoodText.words(rest).isEmpty {
                // "ate 3 slices" counts the one food measured that way, or the only food.
                guard !unit.isEmpty else { continue }
                let same = foods.indices.filter { Measures.unitKey(foods[$0].unit) == Measures.unitKey(unit) }
                target = same.count == 1 ? same[0] : foods.count == 1 ? 0 : nil
            } else {
                target = food(named: rest, in: foods)
            }
            guard let i = target else { continue }
            foods[i] = restate(foods[i], count: count, unit: unit)
        }
        return foods
    }

    /// The seen food whose main word the text names: "chicken breast" names "Grilled chicken breast".
    private static func food(named text: String, in foods: [SeenFood]) -> Int? {
        let said = FoodText.words(text).map(FoodText.stem)
        return foods.indices.first { i in
            guard let head = FoodText.nameWords(foods[i].name).last else { return false }
            return FoodText.forms(head).contains { form in said.contains { FoodText.same($0, form) || FoodText.same(form, $0) } }
        }
    }

    private static func restate(_ food: SeenFood, count: Double, unit: String) -> SeenFood {
        var food = food
        let key = Measures.unitKey(unit), had = Measures.unitKey(food.unit)
        if unit.isEmpty {
            // "Two eggs": a count of whatever the model counted, unless it measured them.
            guard !Measures.measures.contains(had) || had == "serving", food.quantity != count else { return food }
            food.grams = food.grams.map { $0 * count / food.quantity }
        } else {
            // "12 oz" of a drink the model already measured in fluid ounces is the same 12.
            guard key != had || food.quantity != count, !(key == "oz" && had == "floz" && food.quantity == count) else { return food }
            // A weight is exact; a volume converts through the food; a bowl or a glass keeps the
            // model's weight for what it is.
            if let weight = Measures.weights[key] {
                food.grams = weight * count
            } else if key == had {
                food.grams = food.grams.map { $0 * count / food.quantity }
            } else if Measures.volumes[key] != nil {
                food.grams = nil
            }
            food.unit = unit
        }
        food.quantity = count
        return food
    }
}
