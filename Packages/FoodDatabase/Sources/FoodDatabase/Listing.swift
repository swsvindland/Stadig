import Foundation
import SystemCore

/// Which foods a food browser lists: everything the catalogs and the person know, what was logged
/// lately, favourites, or the person's own foods.
public enum FoodScope: String, CaseIterable, Identifiable, Sendable {
    case all, recent, favorites, mine

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: "All"
        case .recent: "Recent"
        case .favorites: "Favorites"
        case .mine: "My Foods"
        }
    }
}

/// A food as a row of a table: the portion it would log (the person's last one, or its natural
/// one) and that portion's numbers, so foods compare as they'd be eaten rather than per 100 g.
public struct FoodListing: Identifiable, Hashable, Sendable {
    public var food: Food
    public var unit: PortionUnit
    public var count: Double
    /// For the portion.
    public var nutrients: Nutrients
    public var favorite: Bool
    /// One of the person's own: logged before, a favourite, or made by them.
    public var personal: Bool
    public var lastLogged: Date?
    /// Its place in the search or the scope: the order before a column is sorted.
    public var rank: Int

    public var id: String { food.id }

    /// "1 container", "150 g".
    public var portion: String { FoodUnits.label(count: count, unit: unit) }

    /// The portion in the food's basis units (grams, millilitres or servings), for sorting by size.
    public var amount: Double { FoodUnits.amount(count, unit) }

    public init(food: Food, personal: PersonalFood?, rank: Int, isOwn: Bool = false) {
        let suggestion = FoodUnits.suggested(
            for: food, lastUnitID: personal?.lastUnitID, lastCount: personal?.lastCount, lastAmount: personal?.lastAmount)
        self.food = food
        unit = suggestion.unit
        count = suggestion.count
        nutrients = FoodUnits.nutrients(food, count: suggestion.count, unit: suggestion.unit)
        favorite = personal?.favorite ?? false
        self.personal = personal != nil || isOwn
        lastLogged = personal?.lastLogged
        self.rank = rank
    }

    /// Where the food's numbers come from, in a word.
    public var sourceLabel: String { food.source.label }
}

extension FoodSource {
    public var label: String {
        switch self {
        case .usda: "USDA"
        case .off: "Open Food Facts"
        case .custom: "My food"
        case .recipe: "Recipe"
        case .label: "From its label"
        }
    }
}

/// The lists behind a food browser. Pure and quick, but over hundreds of foods: call it off the
/// main thread with the catalog's search.
public enum FoodBrowser {
    /// What a scope lists, kept to the words in `query` when there are any. Recent is newest logged
    /// first; favourites and the person's own foods go by name; All with nothing typed is the foods
    /// the person eats, most eaten first. All with something typed is a catalog search: use
    /// `listings(_:personal:)` for that.
    public static func listings(_ scope: FoodScope, query: String, personal: [PersonalFood], custom: [Food], limit: Int = 300) -> [FoodListing] {
        let byID = Dictionary(personal.map { ($0.food.id, $0) }, uniquingKeysWith: { first, _ in first })
        let own = Set(custom.map(\.id))
        var foods: [(Food, PersonalFood?)]
        switch scope {
        case .all:
            foods = personal.sorted { $0.score > $1.score }.map { ($0.food, $0) }
        case .recent:
            foods = personal.filter { $0.lastLogged != nil }.sorted { ($0.lastLogged ?? .distantPast) > ($1.lastLogged ?? .distantPast) }
                .map { ($0.food, $0) }
        case .favorites:
            foods = personal.filter(\.favorite).sorted { byName($0.food, $1.food) }.map { ($0.food, $0) }
        case .mine:
            foods = custom.sorted(by: byName).map { ($0, byID[$0.id]) }
        }
        let words = Self.words(query)
        if !words.isEmpty { foods = foods.filter { matches($0.0, words: words) } }
        return foods.prefix(limit).enumerated().map { rank, pair in
            FoodListing(food: pair.0, personal: pair.1, rank: rank, isOwn: own.contains(pair.0.id))
        }
    }

    /// A catalog search's results as rows, in the search's order.
    public static func listings(_ matches: [FoodMatch], personal: [PersonalFood], custom: [Food] = []) -> [FoodListing] {
        let byID = Dictionary(personal.map { ($0.food.id, $0) }, uniquingKeysWith: { first, _ in first })
        let own = Set(custom.map(\.id))
        return matches.enumerated().map { rank, match in
            FoodListing(food: match.food, personal: byID[match.food.id], rank: rank, isOwn: match.personal || own.contains(match.food.id))
        }
    }

    /// The words of a query, folded for comparing: "Greek  Yogurt" is ["greek", "yogurt"].
    public static func words(_ query: String) -> [String] {
        query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
    }

    /// Whether each word is in the food's name or brand, ignoring case and accents: "fage yog" finds
    /// "Greek yogurt · Fage", "creme" finds "Crème fraîche".
    public static func matches(_ food: Food, words: [String]) -> Bool {
        let text = "\(food.name) \(food.brand ?? "")".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return words.allSatisfy { text.contains($0) }
    }

    static func byName(_ a: Food, _ b: Food) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
}

/// A food table sorted by one of its columns. A food without the value (sodium a label didn't
/// list, a food with no NOVA group) goes last whichever way the column is sorted, so the top of the
/// list is always foods that have it; ties keep the search's order.
public struct FoodListingOrder: SortComparator, Hashable, Sendable {
    public enum Column: String, Hashable, Sendable {
        case relevance, name, portion, kcal, protein, carbs, fat, fiber, sugar, sodium, processing, source
    }

    public var column: Column
    public var order: SortOrder

    public init(_ column: Column, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    public func compare(_ a: FoodListing, _ b: FoodListing) -> ComparisonResult {
        let result: ComparisonResult
        switch column {
        case .relevance: result = Self.compare(a.rank, b.rank)
        case .name: result = Self.compare(a.food.title, b.food.title)
        case .portion: result = Self.compare(a.amount, b.amount)
        case .kcal: result = Self.compare(a.nutrients.kcal, b.nutrients.kcal)
        case .protein: result = Self.compare(a.nutrients.protein, b.nutrients.protein)
        case .carbs: result = Self.compare(a.nutrients.carbs, b.nutrients.carbs)
        case .fat: result = Self.compare(a.nutrients.fat, b.nutrients.fat)
        case .fiber: return ordered(a.nutrients.fiber, b.nutrients.fiber, a, b)
        case .sugar: return ordered(a.nutrients.sugar, b.nutrients.sugar, a, b)
        case .sodium: return ordered(a.nutrients.sodium, b.nutrients.sodium, a, b)
        case .processing: return ordered(a.food.processing, b.food.processing, a, b)
        case .source: result = Self.compare(a.sourceLabel, b.sourceLabel)
        }
        return result == .orderedSame ? Self.compare(a.rank, b.rank) : (order == .forward ? result : result.reversed)
    }

    /// Present values in the column's order, missing ones after them either way, then the search's order.
    private func ordered<T: Comparable>(_ x: T?, _ y: T?, _ a: FoodListing, _ b: FoodListing) -> ComparisonResult {
        switch (x, y) {
        case (let x?, let y?):
            let result = Self.compare(x, y)
            if result == .orderedSame { return Self.compare(a.rank, b.rank) }
            return order == .forward ? result : result.reversed
        case (.some, nil): return .orderedAscending
        case (nil, .some): return .orderedDescending
        case (nil, nil): return Self.compare(a.rank, b.rank)
        }
    }

    static func compare<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult { x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }

    static func compare(_ x: String, _ y: String) -> ComparisonResult { x.localizedStandardCompare(y) }
}

extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}
