import Foundation
import SystemCore

/// What to eat instead of an ultra-processed food, in a line: the same job done by whole foods.
public enum QualitySwap {
    public static func advice(for source: QualityReport.Source) -> String {
        advice(name: source.name, nutrients: source.entry.nutrients)
    }

    /// The swap for a food by its name, or by what's in it when the name doesn't say.
    public static func advice(name: String, nutrients n: Nutrients) -> String {
        let name = Words(name)
        let kcal = max(1, n.kcal)
        let processedMeat = name.has(
            "sausage", "bacon", "hot dog", "hotdog", "frankfurter", "nugget", "salami", "pepperoni", "pastrami",
            "bologna", "deli", "luncheon", "ham")
        // Lean cured meats (pastrami, sliced ham) are mostly protein too, but what to change is the
        // salt and the curing, so their name decides, not their protein.
        if name.has("shake", "powder", "whey", "protein", "isolate") || n.protein * 4 / kcal >= 0.3 && !name.has("bar") && !processedMeat {
            return "Greek yogurt, skyr, eggs or cottage cheese give the same protein as whole food."
        }
        if name.has("bar") {
            return "Fruit and a handful of nuts, or Greek yogurt if it's the protein you're after."
        }
        if name.has(
            "soda", "cola", "coke", "pepsi", "sprite", "fanta", "lemonade", "energy drink", "soft drink", "iced tea", "sports drink",
            "red bull", "monster", "gatorade", "drink")
        {
            return "Water, sparkling water or milk: drinks are the easiest calories to cut, and don't fill you up."
        }
        if name.has("cookie", "brownie", "donut", "doughnut", "candy", "chocolate chip") {
            return "Fruit, or yogurt with honey, for the sweet spot."
        }
        if name.has("chip", "crisp", "cracker", "pretzel", "puff", "cheeto", "dorito", "pringle", "snack") {
            return "A handful of nuts, or popcorn you pop yourself, for the salty crunch."
        }
        let meal = "The same meal cooked from whole foods: meat or fish, rice or potatoes, and vegetables. Cooked in a batch, it's as quick."
        if name.has("pizza", "burger", "hamburger", "cheeseburger", "burrito", "lasagna", "entree", "dinner", "meal", "sandwich", "taco") {
            return meal
        }
        if processedMeat {
            return "Chicken, eggs or fish cooked plain do the same job with less salt."
        }
        if name.has(
            "cereal", "pop-tart", "pop tart", "poptart", "toaster", "waffle", "pancake", "pastry", "muffin", "granola", "croissant",
            "danish")
        {
            return "Oats with fruit fill the same spot, with fiber that keeps you full until lunch."
        }
        if name.has("bread", "bun", "bagel", "wrap", "tortilla") {
            return "A bakery loaf, or potatoes and rice for the starch."
        }
        if let sugar = n.sugar, sugar * 4 / kcal >= 0.35 {
            return "Fruit, or yogurt with honey, for the sweet spot."
        }
        return meal
    }

    /// A food's name as whole words (and their plurals), so "chocolate" isn't a cola, "barbecue" a
    /// bar or "delicious" deli meat. A key with a space or hyphen is a phrase, found as written.
    struct Words {
        let name: String
        let words: Set<String>

        init(_ name: String) {
            self.name = name.lowercased()
            words = Set(self.name.split { !$0.isLetter }.map(String.init))
        }

        func has(_ keys: String...) -> Bool {
            keys.contains { key in
                if key.contains(where: { !$0.isLetter }) { return name.contains(key) }
                return words.contains(key) || words.contains(key + "s") || words.contains(key + "es")
                    || (key.hasSuffix("y") && words.contains(String(key.dropLast()) + "ies"))
            }
        }
    }
}

/// The rules behind Stadig Macro's one-tap fixes: a food that closes a nutrient gap, or something
/// fermented for a week short of it, at a portion people eat. The app finds the foods and works out
/// their portions from the catalog; these say which to offer.
public enum FoodFix {
    /// More than this is a meal, not something added to the day.
    public static let maxKcal = 300.0
    /// A snack's calories: the portion offered when the usual one is a whole container ("1
    /// bottle" of kefir is a quart).
    public static let snackKcal = 150.0
    /// Weights tried, in grams, beside a food's own portions.
    public static let gramPortions = [100.0, 150]
    /// A nutrient fix covers at least this share of the day's target.
    public static let minimumShare = 1.0 / 6
    /// The person's own foods count for this much more per calorie: one already eaten is the one
    /// that gets logged.
    public static let yoursBonus = 1.3
    /// A staple found by name counts only when the catalog's best match scores at least this.
    public static let minimumMatchScore = 1.5

    /// Everyday foods rich in each nutrient, by catalog key, to find in the catalog by name.
    public static let nutrientStaples: [String: [String]] = [
        "fiber": ["raspberries", "lentils", "black beans", "chia seeds", "pear", "oatmeal", "split peas"],
        "potassium": ["potato", "banana", "white beans", "spinach", "avocado", "plain yogurt", "lentils"],
        "magnesium": ["pumpkin seeds", "almonds", "spinach", "black beans", "cashews", "edamame"],
        "calcium": ["greek yogurt", "milk", "cheddar cheese", "tofu", "sardines", "kefir"],
        "iron": ["lentils", "beef", "spinach", "tofu", "chickpeas", "pumpkin seeds"],
        "vitaminC": ["orange", "kiwi", "red bell pepper", "strawberries", "broccoli"],
        "folate": ["lentils", "spinach", "asparagus", "avocado", "edamame", "chickpeas"],
        "vitaminB12": ["salmon", "eggs", "milk", "greek yogurt", "beef", "tuna"],
    ]

    /// Fermented foods to offer when the person eats none of their own, plain ones first:
    /// flavoured yogurts are often ultra-processed.
    public static let fermentedStaples = ["plain greek yogurt", "kefir", "plain yogurt", "skyr", "sauerkraut", "kimchi"]

    /// Whether a portion with this much of a nutrient covers enough of the day's target to offer.
    public static func covers(_ amount: Double, target: Double) -> Bool { amount >= target * minimumShare }

    /// A portion worth offering: some calories, but not a meal's.
    public static func fits(kcal: Double) -> Bool { kcal > 0 && kcal <= maxKcal }

    /// The usual portion when it fits, else whichever other portion that fits is nearest a snack's
    /// calories (the first of a tie). Nil when none fits.
    public static func portion<Option>(usual: Option?, others: [Option], kcal: (Option) -> Double) -> Option? {
        if let usual, fits(kcal: kcal(usual)) { return usual }
        return others.filter { fits(kcal: kcal($0)) }.min { abs(kcal($0) - snackKcal) < abs(kcal($1) - snackKcal) }
    }

    /// The best nutrient fix: the most of the nutrient per calorie, with the person's own foods a
    /// little ahead.
    public static func best<Option>(
        _ options: [Option], amount: (Option) -> Double, kcal: (Option) -> Double,
        yours: (Option) -> Bool
    ) -> Option? {
        func score(_ option: Option) -> Double { amount(option) / kcal(option) * (yours(option) ? yoursBonus : 1) }
        return options.max { score($0) < score($1) }
    }
}
