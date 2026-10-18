import Foundation
import SystemCore

/// Water drunk, logged with a tap. Every other drink is in the food log, where its calories and
/// caffeine already are; it counts toward the day's fluid from there.
public struct WaterLog: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var day: Day
    public var ml: Double
    public var updatedAt: Date

    public init(id: UUID = UUID(), date: Date, day: Day? = nil, ml: Double, updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.day = day ?? Day(date)
        self.ml = ml
        self.updatedAt = updatedAt
    }
}

/// A day's drinks against the day's aim.
public struct HydrationDay: Hashable, Sendable {
    public var day: Day
    /// Millilitres of water tapped in.
    public var water: Double
    /// Millilitres from drinks in the food log: coffee, tea, milk, juice, energy drinks.
    public var drinks: Double
    public var target: Double

    public var total: Double { water + drinks }
    public var fraction: Double { target > 0 ? total / target : 0 }
}

public enum Hydration {
    /// What to drink a day: the National Academies' adequate intake of water (3.7 L for men, 2.7 L
    /// for women), less the fifth or so that comes from food.
    public static func target(sex: BiologicalSex) -> Double {
        switch sex {
        case .male: 3000
        case .female: 2200
        case .unspecified: 2600
        }
    }

    public static func day(_ day: Day, water: [WaterLog], entries: [FoodEntry], target: Double) -> HydrationDay {
        HydrationDay(
            day: day, water: water.filter { $0.day == day }.map(\.ml).reduce(0, +),
            drinks: entries.filter { $0.day == day }.compactMap(fluid).reduce(0, +), target: target)
    }

    /// The fluid in a logged food: what was set when it was logged, else its weight when its name
    /// says it's a drink (a gram of a drink is about a millilitre).
    public static func fluid(of entry: FoodEntry) -> Double? {
        if let fluid = entry.fluid { return fluid > 0 ? fluid : nil }
        return isDrink(entry.name) ? entry.grams : nil
    }

    private static let drinkWords: Set<String> = [
        "coffee", "espresso", "latte", "cappuccino", "americano", "macchiato", "mocha", "cortado", "tea", "chai", "matcha", "juice",
        "soda", "cola", "coke", "pepsi", "lemonade", "limeade", "kombucha", "smoothie", "shake", "kefir", "seltzer", "tonic",
        "beverage", "beverages", "drink", "gatorade", "powerade", "electrolyte", "milk", "buttermilk", "sparkling", "redbull",
        "energy", "punch",
    ]
    private static let drinkPhrases = [
        "cold brew", "flat white", "energy drink", "sports drink", "coconut water", "red bull", "dr pepper",
        "mountain dew", "iced tea", "sweet tea",
    ]
    /// Words that make a drink's name mean something eaten: coffee cake, milk chocolate, tea biscuits.
    private static let notDrinks: Set<String> = [
        "cake", "cakes", "creamer", "powder", "powdered", "dry", "dried", "condensed", "evaporated", "cookie", "cookies", "candy",
        "bar", "bars", "bread", "beans", "grounds", "granules", "crystals", "biscuit", "biscuits", "pudding", "cereal", "cereals",
        "cheese", "pie", "thistle", "teaspoon", "mix", "bites", "gel", "gels", "chews", "gummies",
    ]
    private static let notDrinkPhrases = ["milk chocolate", "ice cream", "frozen yogurt"]
    private static let alcohol: Set<String> = [
        "beer", "wine", "vodka", "whiskey", "whisky", "rum", "gin", "tequila", "liqueur", "cocktail",
        "cider", "lager", "ale",
    ]

    /// Whether a food is something drunk, by name.
    public static func isDrink(_ name: String) -> Bool {
        let lower = name.lowercased()
        let words = Set(lower.split { !$0.isLetter }.map(String.init))
        guard words.isDisjoint(with: alcohol), words.isDisjoint(with: notDrinks), !notDrinkPhrases.contains(where: lower.contains) else {
            return false
        }
        if !words.isDisjoint(with: drinkWords) || drinkPhrases.contains(where: lower.contains) {
            // Named only for milk: "oats cooked with milk" is food; "coffee with milk" is still coffee.
            let named = words.subtracting(["milk", "beverage", "beverages"])
            if named.isDisjoint(with: drinkWords) && !drinkPhrases.contains(where: lower.contains) {
                return !lower.contains("with milk") && !lower.contains("in milk")
            }
            return true
        }
        guard words.contains("water") else { return false }
        // Water something was cooked or packed in isn't drunk.
        return !["with water", "in water", "with tap water", "water-packed", "water packed", "and water", "water chestnut"].contains(
            where: lower.contains)
    }
}

/// A gradual cut in caffeine: down a step each week from where it started to the goal, so
/// withdrawal (headaches, fog) stays mild.
public struct CaffeineCutBack: Hashable, Codable, Sendable {
    public var start: Day
    /// The daily amount when it started: the week's average.
    public var from: Double
    public var goal: Double

    public init(start: Day, from: Double, goal: Double) {
        self.start = start
        self.from = max(from, goal)
        self.goal = goal
    }

    /// A week's step: a fifth of the starting amount, and at least 25 mg.
    public var step: Double { max(25, from * 0.2) }

    /// The most to have on a day: one step down in the first week, another each week after, then the goal.
    public func limit(on day: Day) -> Double {
        let week = max(0, start.days(until: day)) / 7
        return max(goal, from - step * Double(week + 1))
    }

    public var weeks: Int { max(1, Int(((from - goal) / step).rounded(.up))) }

    /// The first day of the last step: from then on, the goal holds.
    public var reachesGoal: Day { start.adding(weeks: weeks - 1) }
}

/// Caffeine taken, from a food entry or a supplement.
public struct CaffeineDose: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var mg: Double
    public var name: String
}

/// The day's caffeine: how much, against today's limit, and how much will still be active at bedtime.
public struct CaffeineReport: Hashable, Sendable {
    public var day: Day
    public var doses: [CaffeineDose]
    public var limit: Double
    public var bedtime: Date
    /// Still active at bedtime, at an average five-hour half-life.
    public var atBedtime: Double
    /// When the last caffeine of the day should be, for little of it to be left at bedtime.
    public var cutoff: Date
    /// The daily average over the last week's known days, before today.
    public var weekAverage: Double?
    public var cutBack: CaffeineCutBack?

    public var total: Double { doses.map(\.mg).reduce(0, +) }
    public var over: Bool { total > limit + 0.5 }
    public var last: CaffeineDose? { doses.last }
}

public enum Caffeine {
    /// Caffeine's half-life in an average adult; it ranges from about 2 to 10 hours.
    public static let halfLife: TimeInterval = 5 * 3600
    /// Up to 400 mg a day is fine for most adults (FDA, EFSA).
    public static let defaultLimit = 400.0
    /// Coffee within about 8 hours of bed measurably cuts sleep (Gardiner et al., 2023).
    public static let cutoffBeforeBed: TimeInterval = 8 * 3600
    /// Still active at bedtime that's worth a word.
    public static let bedtimeConcern = 50.0

    /// A day's caffeine from foods and supplements, earliest first.
    public static func doses(on day: Day, entries: [FoodEntry], supplements: [SupplementLog]) -> [CaffeineDose] {
        let food = entries.filter { $0.day == day }.compactMap { entry -> CaffeineDose? in
            guard let mg = entry.micros?["caffeine"], mg >= 1 else { return nil }
            return CaffeineDose(id: entry.id, date: entry.date, mg: mg, name: entry.name)
        }
        let pills = supplements.filter { $0.day == day && $0.taken }.compactMap { log -> CaffeineDose? in
            guard let mg = log.amounts["caffeine"], mg >= 1 else { return nil }
            return CaffeineDose(id: log.id, date: log.date, mg: mg, name: log.name)
        }
        return (food + pills).sorted { $0.date < $1.date }
    }

    /// What's still active at a moment from doses taken before it.
    public static func active(_ doses: [CaffeineDose], at moment: Date) -> Double {
        doses.filter { $0.date <= moment }.map { $0.mg * pow(0.5, moment.timeIntervalSince($0.date) / halfLife) }.reduce(0, +)
    }

    /// The day's report. `bedtime` is that day's bedtime; `known` are days whose log can be trusted
    /// to say how much caffeine there was (complete days, and any day with caffeine logged).
    public static func report(
        day: Day, entries: [FoodEntry], supplements: [SupplementLog], bedtime: Date, limit: Double,
        cutBack: CaffeineCutBack?, complete: Set<Day>
    ) -> CaffeineReport {
        let doses = doses(on: day, entries: entries, supplements: supplements)
        let limit = cutBack.map { min(limit, $0.limit(on: day)) } ?? limit
        // The last week before today: complete days, and days with caffeine logged (a coffee is
        // often the only thing logged on a busy day).
        var totals: [Double] = []
        for offset in 1...7 {
            let d = day.adding(days: -offset)
            let mg = Caffeine.doses(on: d, entries: entries, supplements: supplements).map(\.mg).reduce(0, +)
            if mg > 0 || complete.contains(d) { totals.append(mg) }
        }
        let average = totals.count >= 3 ? totals.reduce(0, +) / Double(totals.count) : nil
        // Bedtime after midnight belongs to the night of `day`.
        return CaffeineReport(
            day: day, doses: doses, limit: limit, bedtime: bedtime, atBedtime: active(doses, at: bedtime),
            cutoff: bedtime.addingTimeInterval(-cutoffBeforeBed), weekAverage: average, cutBack: cutBack)
    }

    /// Typical caffeine in mg per 100 ml, for drinks logged without a value (a café's latte, a can
    /// Open Food Facts lists without it). The first match wins, so decaf and brands come first.
    private static let typical: [(words: [String], mg: Double)] = [
        (["decaf", "decaffeinated", "caffeine free", "caffeine-free", "no caffeine"], 1),
        (["herbal", "rooibos", "chamomile", "peppermint", "hibiscus", "fruit tea", "ginger tea"], 0),
        (["bang"], 63), (["reign"], 63), (["celsius"], 56), (["alani"], 56), (["prime energy"], 56), (["c4"], 42), (["ghost"], 42),
        (["monster"], 34), (["rockstar"], 34), (["red bull", "redbull"], 32), (["energy drink", "energy"], 32),
        (["espresso", "ristretto", "shot"], 212),
        (["cold brew"], 60),
        (["latte", "cappuccino", "flat white", "macchiato", "cortado", "mocha"], 32),
        (["americano", "coffee", "brew"], 40),
        (["matcha"], 25), (["green tea"], 12), (["chai"], 20), (["tea"], 20),
        (["mountain dew"], 15), (["diet coke"], 13), (["cola", "coke", "pepsi", "dr pepper"], 10),
        (["hot chocolate", "cocoa"], 2),
    ]

    /// About how much caffeine a drink has, from its name, when it was logged without a value.
    public static func estimate(name: String, brand: String?, grams: Double?) -> Double? {
        guard let grams, grams > 0, Hydration.isDrink("\(name) \(brand ?? "")") else { return nil }
        let text =
            " " + ([name, brand ?? ""].joined(separator: " ").lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")) + " "
        guard let match = typical.first(where: { $0.words.contains { text.contains(" \($0) ") } }) else { return nil }
        return match.mg * grams / 100
    }
}
