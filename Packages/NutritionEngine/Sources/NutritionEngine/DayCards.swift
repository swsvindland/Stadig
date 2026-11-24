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

    /// Where breakfast, lunch and dinner usually are: the hours an empty day offers first.
    public static let mealHours = [8, 12, 18]

    /// The few hours of a run of open ones that the Log tab offers in a single row, the rest a tap
    /// away: on today (`now`), the soonest hours after it, or, before it, the latest (what's most
    /// likely still to log); on another day, breakfast, lunch and dinner where the run has them,
    /// then its first hours. Only hours in the window: a run outside it offers none, and stays
    /// behind Earlier or Later. In time order.
    public static func offered(_ hours: [HourGroup], window: ClosedRange<Int>, now: Date? = nil, count: Int = 3) -> [HourGroup] {
        let candidates = hours.filter { window.contains($0.hour) }
        guard candidates.count > count else { return candidates }
        if let now {
            let ahead = candidates.filter { $0.end > now }
            return ahead.isEmpty ? Array(candidates.suffix(count)) : Array(ahead.prefix(count))
        }
        var picked = candidates.filter { mealHours.contains($0.hour) }.prefix(count).map(\.self)
        for hour in candidates where picked.count < count && !picked.contains(hour) { picked.append(hour) }
        return picked.sorted { $0.start < $1.start }
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
        "green", "kidney", "pinto", "wheat", "rye", "iced", "bubble", "sparkling", "light", "fried", "mashed", "scalloped",
    ]
    private static let meats: Set<String> = ["chicken", "turkey", "beef", "pork", "lamb"]
    /// The part of a meat a person names.
    private static let cuts = ["breast", "thigh", "wing", "drumstick", "leg", "tenderloin", "sirloin", "ribeye", "loin", "chop", "ground"]
    /// Parts that name the food better than the head they're filed under, with the parts they say
    /// already: "Beverages, coffee, brewed, espresso" is espresso, and "Coffee, Latte, nonfat" a latte.
    private static let naming: [String: Set<String>] = [
        "espresso": ["coffee", "brewed"], "latte": ["coffee"], "iced latte": ["coffee"], "cappuccino": ["coffee"], "macchiato": ["coffee"],
        "cafe mocha": ["coffee"], "iced cafe mocha": ["coffee"], "cafe con leche": ["coffee"],
        // Fries and hash browns are potatoes, and a brownie is filed with the cookies.
        "french fries": ["potato"], "home fries": ["potato"], "hash brown": ["potato"], "brownie": ["cookie"], "brownies": ["cookies"],
    ]
    /// Dishes a catalog files with their kind after them, which is said before them: "Soup,
    /// tomato" is tomato soup, "Pie, apple" apple pie, "Taco, fish" a fish taco. The value is
    /// how the dish is said after its kind, where that isn't the head itself.
    private static let dishes: [String: String] = [
        "soup": "soup", "stew": "stew", "pie": "pie", "pot pie": "pot pie", "pizza": "pizza", "cake": "cake", "cookie": "cookie",
        "cookies": "cookies", "doughnut": "doughnut", "muffin": "muffin", "muffins": "muffins", "pudding": "pudding", "puddings": "pudding",
        "cobbler": "cobbler", "crisp": "crisp", "taco": "taco", "burrito": "burrito", "quesadilla": "quesadilla", "enchilada": "enchilada",
        "tamale": "tamale", "fajita": "fajita", "nachos": "nachos", "lasagna": "lasagna", "gravy": "gravy", "frozen yogurt": "frozen yogurt",
        "ice cream": "ice cream", "ice creams": "ice cream", "sushi roll": "roll",
    ]
    /// Words that say how a dish comes, is made or is sold, not which kind it is: "Pizza, no
    /// cheese" and "Soup, canned" stay as they're filed.
    private static let notKinds: Set<String> = [
        "with", "without", "from", "no", "on", "in", "made", "for", "not", "topped", "filled", "plain", "regular", "light", "lite", "diet",
        "reduced", "low", "nonfat", "lowfat", "fat", "free", "sugar", "frozen", "canned", "cooked", "raw", "dry", "instant", "commercially",
        "home", "homemade", "prepared", "ready", "restaurant", "fast", "food", "school", "bakery", "type", "style", "topping", "crust",
        "tortilla", "only", "other", "flavors", "mix", "recipe", "nfs", "thin", "thick", "medium", "small", "large", "unsweetened", "sweetened",
        "condensed", "dehydrated",
    ]
    /// Soups that are named without the word: "Soup, New England clam chowder" is the chowder.
    private static let soups: Set<String> = ["chowder", "bisque", "pho", "minestrone", "gazpacho", "borscht", "pozole", "menudo", "broth"]

    /// A dish's kind as it's said before it, when the part is one: a few plain words.
    private static func kind(_ part: String) -> [String]? {
        let words = part.lowercased().split(separator: " ").map(String.init)
        guard (1...4).contains(words.count), words.allSatisfy({ word in word.allSatisfy(\.isLetter) && !notKinds.contains(word) }) else {
            return nil
        }
        return words
    }

    /// USDA's notes in brackets, which say where a food came from or how it was measured rather
    /// than what it is: "(Includes foods for USDA's Food Distribution Program)".
    private static let notes = #"\s*\((?i:includes|for reference)[^)]*\)"#

    public static func parts(of name: String) -> (title: String, detail: String?) {
        // Most names have no brackets, and a marker reads every row's name: skip the pattern for them.
        let name = name.contains("(") ? name.replacingOccurrences(of: notes, with: "", options: .regularExpression) : name
        var parts = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A restaurant's name is written first and in capitals: "McDONALD'S, BIG MAC" stays whole.
        guard parts.count > 1, parts[1] != parts[1].uppercased() else { return (name, nil) }
        var title = parts.removeFirst()
        let head = title.lowercased()
        if let index = parts.firstIndex(where: { naming[$0.lowercased()] != nil }) {
            title = parts.remove(at: index)
            let said = naming[title.lowercased()] ?? []
            parts.removeAll { said.contains($0.lowercased()) }
        } else if filing.contains(head), !parts.isEmpty {
            title = parts.removeFirst()
        } else if head == "egg", parts.first?.lowercased() == "whole" {
            // An egg is whole unless it's said to be the white or the yolk.
            parts.removeFirst()
        } else if let said = dishes[head], let first = parts.first, let words = kind(first) {
            title = head == "soup" && soups.contains(words[words.count - 1]) ? first : "\(first) \(said)"
            parts.removeFirst()
        } else if let first = parts.first, describing.contains(first.lowercased()) {
            title = "\(first) \(head)"
            parts.removeFirst()
        } else if meats.contains(head), let index = parts.firstIndex(where: { part in cuts.contains { part.lowercased().contains($0) } }) {
            let cut = parts.remove(at: index).lowercased()
            title = cut.contains("ground") ? "Ground \(head)" : "\(head) \(cut)"
        }
        // How a chicken was raised isn't what anyone calls it.
        if meats.contains(head) { parts.removeAll { $0.lowercased().hasPrefix("broilers") } }
        let detail = parts.joined(separator: ", ")
        return (title.prefix(1).uppercased() + title.dropFirst(), detail.isEmpty ? nil : detail)
    }

    /// How a food was cooked, the most particular way first: "cooked, roasted" was roasted.
    private static let cooking: Set<String> = [
        "roasted", "grilled", "baked", "boiled", "hard-boiled", "soft-boiled", "steamed", "fried", "pan-fried", "deep-fried", "stir-fried",
        "broiled", "braised", "stewed", "poached", "scrambled", "toasted", "microwaved", "smoked", "sauteed", "sautéed", "mashed", "omelet",
    ]
    /// The state it's in, when it wasn't cooked any particular way.
    private static let states: Set<String> = ["cooked", "raw", "uncooked", "dry", "dried", "canned", "frozen", "brewed", "instant"]
    /// How much fat a dairy food has, said as the whole part: "Yogurt, Greek, plain, lowfat".
    private static let fats: Set<String> = [
        "nonfat", "non-fat", "lowfat", "low fat", "low-fat", "reduced fat", "fat free", "fat-free", "skim", "skim milk", "whole milk", "part skim",
    ]
    /// The markers of fruit and vegetables, which are eaten raw: "Bananas, raw" is bananas.
    private static let produce: Set<String> = [
        "🍠", "🍆", "🍍", "🥔", "🥦", "🥕", "🍅", "🌽", "🥑", "🫑", "🧅", "🧄", "🍄", "🥒", "🥗", "🍌", "🍎", "🍊", "🍋", "🍓", "🫐", "🍇", "🥭",
        "🍑", "🍐", "🍒", "🍉",
    ]
    /// Names this short are already how someone would write them: "Coffee, black".
    private static let alreadyShort = 24

    /// A food's name on a line of its own, as Today's thread says it: what it is, and how it was
    /// cooked or how much fat it has when the catalog says ("Chicken breast, roasted", "White rice,
    /// cooked", "Greek yogurt, lowfat"). `rest` is the rest of the catalog's detail, for where foods
    /// must be told apart (the composer's matches); nil when nothing's left.
    public static func spoken(_ name: String) -> (short: String, rest: String?) {
        let (title, detail) = parts(of: name)
        guard let detail else { return (title, nil) }
        var rest = detail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let fresh = produce.contains(FoodMarker.of(title))
        let written = name.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        // Nothing to cut from a short name read as written, except the raw of a fruit.
        if written?.lowercased() == title.lowercased(), rest.count == 1, name.count <= alreadyShort, !(fresh && rest[0].lowercased() == "raw") {
            return (name, nil)
        }
        func leading(_ part: String) -> String { part.lowercased().split(separator: " ").first.map(String.init) ?? "" }
        var said: String?
        if let index = rest.firstIndex(where: { cooking.contains(leading($0)) }) {
            said = leading(rest.remove(at: index))
            // "Cooked" says less than "roasted" beside it.
            rest.removeAll { leading($0) == "cooked" }
        } else if let index = rest.firstIndex(where: { $0.lowercased() == "decaffeinated" }) {
            rest.remove(at: index)
            said = "decaf"
        } else if let index = rest.firstIndex(where: { states.contains(leading($0)) }), !(fresh && leading(rest[index]) == "raw") {
            said = leading(rest.remove(at: index))
        } else if let index = rest.firstIndex(where: { fats.contains($0.lowercased()) }) {
            said = rest.remove(at: index).lowercased()
        }
        let short = said.map { "\(title), \($0)" } ?? title
        return (short, rest.isEmpty ? nil : rest.joined(separator: ", "))
    }

    /// ``spoken(_:)``'s short name alone.
    public static func short(_ name: String) -> String { spoken(name).short }

    /// What a food is, for a tile or a list of several: "Chicken breast", "Greek yogurt".
    public static func title(_ name: String) -> String { parts(of: name).title }
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
