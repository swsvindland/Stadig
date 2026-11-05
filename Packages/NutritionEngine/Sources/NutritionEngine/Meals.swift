import Foundation
import SystemCore

/// Foods eaten together, kept under a name so the lot is one tap the next time: a sandwich of five
/// ingredients, the usual breakfast. Each food is kept as it was logged and goes back in as an entry
/// of its own, so the timeline, food quality and each food's next portion work as if it had been
/// logged by hand, and one food can be changed or left out on the day.
public struct SavedMeal: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// The foods as they were logged, in order. Their ids, times and sources mean nothing here:
    /// logging the meal copies them (``entries(at:skipping:)``).
    public var foods: [FoodEntry]
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, foods: [FoodEntry], updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.foods = foods
        self.updatedAt = updatedAt
    }

    /// A meal of foods logged together, in the order they were eaten.
    public init(name: String, from entries: [FoodEntry], updatedAt: Date = Date()) {
        self.init(name: name, foods: entries.sorted { $0.date < $1.date }, updatedAt: updatedAt)
    }

    public var nutrients: Nutrients { Nutrients.sum(foods.map(\.nutrients)) }

    /// The meal eaten at `date`, as new entries a second apart so they keep their order, leaving
    /// out the foods in `skipping` (by their ids in ``foods``, which are unique in a meal).
    public func entries(at date: Date, skipping: Set<UUID> = []) -> [FoodEntry] {
        foods.filter { !skipping.contains($0.id) }.enumerated().map { i, food in
            LogAgain.copy(food, to: date.addingTimeInterval(Double(i)), source: .recipe)
        }
    }

    /// Each food once, by catalog id, else by name and brand: what a moment has to hold to be this meal.
    public var keys: Set<String> { Set(foods.map(LogAgain.key)) }

    /// Whether these entries are this meal's foods in the same amounts, to the calorie and the
    /// tenth of a gram (or of a portion): a meal logged and then changed is offered as an update,
    /// one logged as it is isn't. The amount tells apart what has next to no calories (water,
    /// black coffee, a diet drink).
    public func hasSameAmounts(as entries: [FoodEntry]) -> Bool {
        func amounts(_ foods: [FoodEntry]) -> [String] {
            foods.map { food in
                let amount = Int(((food.grams ?? food.count ?? 0) * 10).rounded())
                return "\(LogAgain.key(food))|\(Int(food.nutrients.kcal.rounded()))|\(amount)"
            }
            .sorted()
        }
        return amounts(foods) == amounts(entries)
    }
}

/// A saved meal, and how well it fits now.
public struct MealSuggestion: Hashable, Sendable, Identifiable {
    public var meal: SavedMeal
    /// Each time it was eaten adds `0.5^(daysAgo/21) × timeFit`, as ``LogAgain/rank(_:now:calendar:limit:)`` scores a food.
    public var score: Double
    /// Eaten within ``SavedMeals/usualWindow`` of this time of day on another day in the last month,
    /// and not already within that long of the time ranked for: worth offering on Today.
    public var usualNow: Bool

    public var id: UUID { meal.id }
}

public enum SavedMeals {
    /// How close to the clock time of an earlier eating counts as "about now".
    public static let usualWindow: TimeInterval = 90 * 60

    /// Saved meals, best first for `time` (now unless given: a time picked in the logger, or one on
    /// a day being caught up), with days ago counted from now, as Log Again counts them. A meal
    /// counts as eaten in any moment of the last 180 days that holds every one of its foods, whether
    /// it was logged as the meal or food by food (and with a drink beside it). Meals never eaten keep
    /// the order they were saved in, newest first. `logged` is the log around `time` where `entries`
    /// leaves food for later out: a meal already planned then isn't offered as well, and what's only
    /// planned doesn't count towards how often it's eaten.
    public static func rank(
        _ meals: [SavedMeal], entries: [FoodEntry], logged: [FoodEntry]? = nil, now: Date, at time: Date? = nil, calendar: Calendar = .current
    ) -> [MealSuggestion] {
        guard !meals.isEmpty else { return [] }
        let today = Day(now, calendar: calendar)
        let time = time ?? now
        let timeDay = Day(time, calendar: calendar)
        let hourNow = LogAgain.hourOfDay(time, calendar)
        // By day, as Log Again reads them: a meal's foods go in a second apart, so the last of one
        // just logged is still a moment ahead of the clock.
        func read(_ entries: [FoodEntry]) -> [(day: Day, start: Date, end: Date, keys: Set<String>)] {
            Dictionary(grouping: entries, by: \.day).flatMap { day, entries in
                Timeline.moments(entries).map { (day: day, start: $0.start, end: $0.end, keys: Set($0.entries.map(LogAgain.key))) }
            }
        }
        let moments = read(entries.filter { $0.day <= today && $0.day > today.adding(days: -180) })
        let around = logged.map(read) ?? moments
        return meals.map { meal in
            let keys = meal.keys
            var score = 0.0
            var usual = false
            for moment in moments where !keys.isEmpty && keys.isSubset(of: moment.keys) {
                let days = Double(moment.day.days(until: today))
                var diff = abs(LogAgain.hourOfDay(moment.start, calendar) - hourNow)
                diff = min(diff, 24 - diff)
                let fit = max(0.1, exp(-(diff * diff) / (2 * LogAgain.hourSpread * LogAgain.hourSpread)))
                score += pow(0.5, days / LogAgain.halfLife) * fit
                if moment.day != timeDay, days <= 30, diff * 3600 <= usualWindow { usual = true }
            }
            // Already eaten around now, or planned: lunch isn't offered again once it's logged. By
            // the clock, not the day: dinner logged at 11:30 PM is still just eaten at 12:15 AM.
            let eatenNow = around.contains { moment in
                !keys.isEmpty && keys.isSubset(of: moment.keys) && moment.end >= time.addingTimeInterval(-usualWindow)
                    && moment.start <= time.addingTimeInterval(usualWindow)
            }
            return MealSuggestion(meal: meal, score: score, usualNow: usual && !eatenNow)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.meal.updatedAt > $1.meal.updatedAt }
    }

    /// Meals with every typed word in their name, then those with every word in one of their foods
    /// ("turkey" finds the sandwich), each in the order given.
    public static func matching(_ query: String, in meals: [SavedMeal]) -> [SavedMeal] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func holds(_ text: String) -> Bool { words.allSatisfy { text.localizedStandardContains($0) } }
        let byName = meals.filter { holds($0.name) }
        let byFood = meals.filter { meal in !holds(meal.name) && meal.foods.contains { holds("\($0.name) \($0.brand ?? "")") } }
        return byName + byFood
    }

    /// The saved meal of exactly these foods, so a moment already saved isn't offered for saving
    /// again: of two with the same foods ("Sandwich" and "Light sandwich"), the one with the same
    /// amounts, else the first.
    public static func meal(for entries: [FoodEntry], in meals: [SavedMeal]) -> SavedMeal? {
        let keys = Set(entries.map(LogAgain.key))
        guard !keys.isEmpty else { return nil }
        let same = meals.filter { $0.keys == keys }
        return same.first { $0.hasSameAmounts(as: entries) } ?? same.first
    }

    /// A name to start from: the three foods with the most calories, in the order eaten, by the part
    /// of their names before the first comma ("Bread, turkey and cheese +2").
    public static func suggestedName(_ foods: [FoodEntry]) -> String {
        let ordered = foods.sorted { $0.date < $1.date }
        let biggest = Set(ordered.indices.sorted { ordered[$0].nutrients.kcal > ordered[$1].nutrients.kcal }.prefix(3))
        let names = ordered.indices.filter { biggest.contains($0) }.enumerated().map { i, index in short(ordered[index].name, first: i == 0) }
        guard let last = names.last else { return "" }
        let listed = names.count == 1 ? last : "\(names.dropLast().joined(separator: ", ")) and \(last)"
        return foods.count > names.count ? "\(listed) +\(foods.count - names.count)" : listed
    }

    /// A food's name up to its first comma, for a line naming several: "Bread, whole-wheat,
    /// commercially prepared" is "Bread".
    public static func shortName(_ name: String) -> String {
        name.split(separator: ",", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }

    /// The short name, lower-cased after the first ("bread"), unless it has capitals past its
    /// first letter ("KIND bar", "Coca-Cola").
    static func short(_ name: String, first: Bool) -> String {
        let head = shortName(name)
        guard !first, let initial = head.first, !head.dropFirst().contains(where: \.isUppercase) else { return head }
        return initial.lowercased() + head.dropFirst()
    }
}

extension Timeline {
    /// The moment a food logged at `date` would join, as ``moments(_:gap:)`` would group it, without
    /// that food; nil when it would start a moment of its own. `entries` are the day's.
    public static func moment(joining date: Date, in entries: [FoodEntry], gap: TimeInterval = gap) -> Moment? {
        let probe = FoodEntry(id: UUID(), date: date, name: "", amountLabel: "", nutrients: .zero, source: .quickAdd)
        guard let found = moments(entries + [probe], gap: gap).first(where: { $0.entries.contains { $0.id == probe.id } }) else { return nil }
        let others = found.entries.filter { $0.id != probe.id }
        return others.isEmpty ? nil : Moment(entries: others)
    }
}
