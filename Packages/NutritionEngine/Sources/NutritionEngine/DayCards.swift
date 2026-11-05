import Foundation
import SystemCore

/// One piece of a day on the Log tab: a meal, something held at a time, the hour it is, or the open
/// hours between them.
public enum DayItem: Hashable, Sendable, Identifiable {
    case meal(Moment)
    /// An hour with something to place in it: a usual time to catch up, or a planned meal.
    case held(HourGroup)
    /// The hour it is, on today.
    case now(HourGroup)
    /// Open hours in a row, each a tap from logging at it.
    case hours([HourGroup])

    public var id: String {
        switch self {
        case .meal(let moment): "meal-\(moment.id)"
        case .held(let group): "held-\(group.start.timeIntervalSince1970)"
        case .now(let group): "now-\(group.start.timeIntervalSince1970)"
        case .hours(let groups): "hours-\((groups.first?.start ?? .distantPast).timeIntervalSince1970)"
        }
    }
}

/// A day read as meals, the way the Log tab's cards show it. A meal is a ``Moment``, so it can run
/// across an hour; every hour with nothing in it stays a place to log at.
public enum DayCards {
    /// The day's meals in time order, with the open hours between them. `held` are times something
    /// is waiting at, and `now` is given on today only.
    public static func items(_ groups: [HourGroup], held: [Date] = [], now: Date? = nil) -> [DayItem] {
        let meals = Timeline.moments(groups.flatMap(\.entries))
        var items: [DayItem] = []
        var open: [HourGroup] = []
        for group in groups {
            let starting = meals.filter { meal in meal.entries.first.map(group.entries.contains) ?? false }
            let isHeld = held.contains { group.start <= $0 && $0 < group.end }
            let isNow = now.map { group.start <= $0 && $0 < group.end } ?? false
            // A meal that ran on from the hour before takes this one too: the hour isn't open.
            guard !group.entries.isEmpty || isHeld || isNow else {
                open.append(group)
                continue
            }
            if !open.isEmpty { items.append(.hours(open)) }
            open = []
            if isHeld { items.append(.held(group)) }
            // Food logged for later in this same hour goes after now.
            let later = starting.filter { meal in isNow && now.map { meal.start > $0 } ?? false }
            items += starting.filter { !later.contains($0) }.map(DayItem.meal)
            if isNow { items.append(.now(group)) }
            items += later.map(DayItem.meal)
        }
        if !open.isEmpty { items.append(.hours(open)) }
        return items
    }

    /// Where a day opens: at the hour it is, else its first meal, else what's waiting, else the top.
    public static func opening(_ items: [DayItem]) -> DayItem? {
        items.first { if case .now = $0 { true } else { false } }
            ?? items.first { if case .meal = $0 { true } else { false } }
            ?? items.first { if case .held = $0 { true } else { false } }
            ?? items.first
    }

    /// When a meal's + logs: now, if that's still the same meal, otherwise a minute after its last
    /// food, and always on its day.
    public static func addTime(to meal: Moment, now: Date, calendar: Calendar = .current) -> Date {
        let last = meal.end
        if now >= last, now.timeIntervalSince(last) < Timeline.gap, Day(now, calendar: calendar) == Day(last, calendar: calendar) { return now }
        let dayEnd = Day(last, calendar: calendar).adding(days: 1).date(calendar: calendar)
        return min(last.addingTimeInterval(60), dayEnd.addingTimeInterval(-1))
    }
}

/// Which hours the Log tab offers as slots. The rest stay a tap away, and food in them always shows.
public enum LogHours {
    public static let standard = 7...20

    /// The hours to show: the person's own first and last where set, else from when they wake and
    /// go to bed (minutes from midnight; a bedtime past midnight runs to the end of the day), else
    /// ``standard``. Set the wrong way round, they're read the right way round.
    public static func window(first: Int? = nil, last: Int? = nil, wake: Int? = nil, bed: Int? = nil) -> ClosedRange<Int> {
        let start = first ?? wake.map { max(0, min(23, $0 / 60)) } ?? standard.lowerBound
        // The hour before bed, since a slot means eating in it: bed at 10 PM ends on 9 PM.
        let end = last ?? bed.map { max(0, min(23, ($0 - 1) / 60)) } ?? standard.upperBound
        return min(start, end)...max(start, end)
    }

    /// Open hours by where they fall against the window.
    public static func split(_ hours: [HourGroup], window: ClosedRange<Int>) -> (earlier: [HourGroup], shown: [HourGroup], later: [HourGroup]) {
        (
            hours.filter { $0.hour < window.lowerBound }, hours.filter { window.contains($0.hour) },
            hours.filter { $0.hour > window.upperBound }
        )
    }
}

/// What a meal is called on its card, from when it was and how much it was.
public enum MealName {
    /// Under this, a meal at any hour is a snack.
    public static let snackKcal = 200.0

    public static func of(_ meal: Moment, calendar: Calendar = .current) -> String {
        if !meal.entries.isEmpty, meal.entries.allSatisfy({ $0.fluid != nil }) { return "Drink" }
        if meal.nutrients.kcal < snackKcal { return "Snack" }
        switch calendar.component(.hour, from: meal.start) {
        case 4..<11: return "Breakfast"
        case 11..<15: return "Lunch"
        case 16..<22: return "Dinner"
        default: return "Snack"
        }
    }
}

/// A catalog's long name as someone would say it: "Chicken, broilers or fryers, breast, meat only"
/// is "Chicken breast", with the rest kept as its detail. The full name stays on the entry.
public enum FoodLabel {
    /// Heads that only file a food: "Nuts, almonds" is almonds.
    private static let filing: Set<String> = [
        "fish", "nuts", "cereals", "beverage", "beverages", "alcoholic beverage", "alcoholic beverages", "spices", "crustaceans", "mollusks",
        "snacks", "candies",
    ]
    /// Words that go in front of the head: "Rice, white" is white rice.
    private static let describing: Set<String> = [
        "white", "brown", "wild", "greek", "sweet", "whole", "whole-wheat", "whole-grain", "olive", "coconut", "canola", "peanut", "black", "red",
        "green", "kidney", "pinto",
    ]
    private static let meats: Set<String> = ["chicken", "turkey", "beef", "pork", "lamb"]
    /// The part of a meat a person names.
    private static let cuts = ["breast", "thigh", "wing", "drumstick", "leg", "tenderloin", "sirloin", "ribeye", "loin", "chop", "ground"]

    public static func parts(of name: String) -> (title: String, detail: String?) {
        var parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A restaurant's name is written first and in capitals: "McDONALD'S, BIG MAC" stays whole.
        guard parts.count > 1, parts[1] != parts[1].uppercased() else { return (name, nil) }
        var title = parts.removeFirst()
        let head = title.lowercased()
        if filing.contains(head), !parts.isEmpty {
            title = parts.removeFirst()
        } else if let first = parts.first, describing.contains(first.lowercased()) {
            title = "\(first) \(head)"
            parts.removeFirst()
        } else if meats.contains(head), let index = parts.firstIndex(where: { part in cuts.contains { part.lowercased().contains($0) } }) {
            let cut = parts.remove(at: index).lowercased()
            title = cut.contains("ground") ? "Ground \(head)" : "\(head) \(cut)"
            parts.removeAll { $0.lowercased().hasPrefix("broilers") }
        }
        let detail = parts.joined(separator: ", ")
        return (title.prefix(1).uppercased() + title.dropFirst(), detail.isEmpty ? nil : detail)
    }
}

/// The small picture beside a food. The catalogs say what a food is only in its name, so this reads
/// the name, the most particular words first; anything it doesn't know gets a plate.
public enum FoodMarker {
    public static let unknown = "🍽️"

    /// In order: "sweet potato" before "potato", "eggplant" before "egg".
    private static let table: [(words: [String], marker: String)] = [
        (["coffee", "espresso", "latte"], "☕️"), (["tea"], "🍵"), (["water"], "💧"), (["juice"], "🧃"), (["beer"], "🍺"), (["wine"], "🍷"),
        (["soda", "cola", "shake", "smoothie", "whey"], "🥤"),
        (["burger", "hamburger", "cheeseburger"], "🍔"), (["pizza"], "🍕"), (["taco"], "🌮"), (["burrito"], "🌯"), (["sandwich"], "🥪"),
        (["hot dog", "sausage", "frankfurter"], "🌭"), (["fries"], "🍟"), (["popcorn"], "🍿"), (["ice cream"], "🍨"),
        (["sweet potato"], "🍠"), (["eggplant"], "🍆"), (["peanut"], "🥜"), (["pineapple"], "🍍"),
        (["chicken", "turkey"], "🍗"), (["bacon"], "🥓"), (["beef", "steak", "pork", "lamb"], "🥩"), (["ham"], "🍖"),
        (["salmon", "tuna", "cod", "tilapia", "trout", "fish"], "🐟"), (["shrimp", "prawn"], "🍤"), (["egg"], "🥚"),
        (["yogurt", "milk"], "🥛"), (["cheese"], "🧀"), (["butter"], "🧈"),
        (["oat", "oatmeal", "cereal", "granola", "muesli"], "🥣"), (["rice"], "🍚"), (["pasta", "spaghetti", "noodle", "macaroni"], "🍝"),
        (["bread", "toast", "bagel", "bun"], "🍞"), (["soup", "stew", "chili"], "🍲"),
        (["potato"], "🥔"), (["broccoli"], "🥦"), (["carrot"], "🥕"), (["tomato"], "🍅"), (["corn"], "🌽"), (["avocado"], "🥑"),
        (["pepper"], "🫑"), (["onion"], "🧅"), (["garlic"], "🧄"), (["mushroom"], "🍄"), (["cucumber"], "🥒"),
        (["salad", "lettuce", "spinach", "kale", "greens"], "🥗"), (["bean", "lentil", "chickpea", "tofu"], "🫘"),
        (["banana"], "🍌"), (["apple"], "🍎"), (["orange", "clementine"], "🍊"), (["lemon", "lime"], "🍋"), (["strawberr"], "🍓"),
        (["blueberr"], "🫐"), (["grape"], "🍇"), (["mango"], "🥭"), (["peach", "nectarine"], "🍑"), (["pear"], "🍐"), (["cherr"], "🍒"),
        (["melon"], "🍉"), (["almond", "walnut", "cashew", "pecan", "pistachio", "nuts"], "🌰"), (["oil"], "🫒"), (["honey"], "🍯"),
        (["chocolate"], "🍫"), (["cookie"], "🍪"), (["cake", "muffin"], "🍰"), (["donut", "doughnut"], "🍩"), (["candy", "candies"], "🍬"),
    ]

    public static func of(_ name: String) -> String {
        // What it's called first: "Chicken, broilers, with rice" is chicken.
        match(FoodLabel.parts(of: name).title) ?? match(name) ?? unknown
    }

    private static func match(_ text: String) -> String? {
        let lowered = text.lowercased()
        let tokens = lowered.split { !$0.isLetter }.map(String.init)
        let found = table.first { entry in
            entry.words.contains { word in word.contains(" ") ? lowered.contains(word) : tokens.contains { $0.hasPrefix(word) } }
        }
        return found?.marker
    }
}
