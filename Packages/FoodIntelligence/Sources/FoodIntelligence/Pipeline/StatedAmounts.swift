import Foundation

/// Amounts the person said ("8 oz steak", "two eggs", "half a bagel", "ate 3 slices") override the
/// model's, which sometimes drops or rewrites them. Read by rule, so a stated amount is never lost.
enum StatedAmounts {
    private static let numbers: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "single": 1, "two": 2, "couple": 2, "pair": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "dozen": 12, "half": 0.5, "half dozen": 6,
    ]
    private static let separators = Pattern(#",|;|\band\b|\bwith\b|\bplus\b|\bthen\b"#)
    private static let units = #"g|grams?|gr|kg|kilos?|oz|ounces?|lbs?|pounds?|ml|l|lit(?:er|re)s?|fl\.? ?oz|cups?|tbsp|tablespoons?|"#
        + #"tsp|teaspoons?|slices?|pieces?|cans?|bottles?|glass(?:es)?|mugs?|scoops?|strips?|bowls?|plates?|servings?"#
    // Longest first: alternation takes the first branch that works, so "1/2" would otherwise be 1.
    private static let number = #"\d+\s+\d+/\d+|\d+/\d+|\d+\s?[½¼¾⅓⅔]|\d+(?:\.\d+)?|[½¼¾⅓⅔]"#
    // "a" or "an" is one only when nothing more exact follows: "an 8 oz steak" is 8 oz, "a couple
    // of" is two, and "a few" or "a handful" is no amount at all. "A 6 inch sub" is still one sub.
    private static let article = #"an?(?!\s+(?:(?:"# + number + #")\s*(?:"# + units + #")\b"#
        + #"|(?:few|couple|pair|dozen|half|handful|bunch|lot|little|bit|several)\b))"#
    // "2% milk" and "a 6 inch sub" give a fat level and a size, not a count, and a number is never
    // the start of a longer one: "1.5% milk" is not 1 of "5% milk".
    private static let amount = Pattern(#"(?:^|\s)((?:"# + number + #")(?!\s*%|\s*-?\s*inch|"|[.,/]?\d)|"# + article
        + #"|one|single|two|couple(?: of)?|pair(?: of)?|three|four|five|six|seven|eight|nine|ten|eleven|twelve|dozen|half(?: a)? dozen"#
        + #"|half(?: an?)?)\s*"#
        + #"("# + units + #")?\b\.?\s*(?:of\s+)?(.*)$"#)

    /// The description's items, each with its own amount: "toast", "2 slices of bacon".
    static func segments(_ said: String) -> [String] {
        separators.splitKeepingMatches(FoodText.plain(said)).enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
    }

    static func apply(_ foods: [SeenFood], said: String) -> [SeenFood] {
        guard !foods.isEmpty else { return foods }
        var foods = foods
        for segment in segments(said) {
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
