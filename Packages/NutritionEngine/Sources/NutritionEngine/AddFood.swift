import Foundation
import SystemCore

/// What someone typed into Today's composer, read into the foods they mean: "chick 200",
/// "2 eggs, toast, coffee", "500 kcal". Commas separate foods; each part has the words to find
/// and, maybe, an amount. Nothing here knows a catalog: the app finds the foods and turns an
/// amount into one of a food's units with `AddFoodAmount.portion(counted:)`.
public enum AddFoodText {
    /// Every part of what's typed, in order. An empty part after a comma is the person still typing
    /// (`.typing`); empty parts between commas are dropped.
    public static func parse(_ text: String) -> [AddFoodPart] {
        let raw = pieces(text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var parts: [AddFoodPart] = []
        for (index, piece) in raw.enumerated() {
            let last = index == raw.count - 1
            if piece.isEmpty {
                // "2 eggs, " is waiting for the next food; ",," is nothing.
                if last && raw.count > 1 { parts.append(AddFoodPart(text: "", kind: .typing, words: [], amount: nil)) }
                continue
            }
            parts.append(part(piece))
        }
        return parts
    }

    /// The text between commas, except a comma between two digits: "rice 1,5 kg" is one food.
    static func pieces(_ text: String) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let between = index > 0 && index + 1 < characters.count && characters[index - 1].isNumber && characters[index + 1].isNumber
            if character == ",", !between {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)
        return pieces
    }

    /// The parts that name something to log: what Return logs.
    public static func loggable(_ parts: [AddFoodPart]) -> [AddFoodPart] {
        parts.filter { $0.kind != .typing && !($0.kind == .food && $0.words.isEmpty) }
    }

    static func part(_ text: String) -> AddFoodPart {
        let tokens = tokenize(text)
        var amount: AddFoodAmount?
        var words: [String] = []
        var kcal: Double?
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            switch token {
            case .number(let value):
                if let next, case .word(let word) = next, energyWords.contains(word), kcal == nil {
                    kcal = value
                    index += 2
                    continue
                }
                if let next, case .times = next, amount == nil {
                    // "2 x yogurt", "2 × yogurt"
                    amount = AddFoodAmount(count: value, unit: nil, multiplier: true)
                    index += 2
                    continue
                }
                // "2 x 150 g": a multiple of the amount that follows it.
                let times = amount.flatMap { $0.multiplier ? $0.count : nil }
                if amount == nil || times != nil {
                    let count = value * (times ?? 1)
                    if let next, case .word(let word) = next, let unit = AddFoodUnit(word: word) {
                        amount = AddFoodAmount(count: count, unit: unit, multiplier: false)
                        // "2 eggs": the word names the food as well as counting it.
                        if unit.namesFood { words.append(word) }
                        index += 2
                        continue
                    }
                    amount = AddFoodAmount(count: count, unit: nil, multiplier: false)
                    index += 1
                    continue
                }
                // A second number is noise to the search: it's left out, with its unit.
                if let next, case .word(let word) = next, let unit = AddFoodUnit(word: word), !unit.namesFood {
                    index += 2
                } else {
                    index += 1
                }
            case .times:
                // "yogurt x2", "yogurt × 2"
                if let next, case .number(let value) = next, amount == nil {
                    amount = AddFoodAmount(count: value, unit: nil, multiplier: true)
                    index += 2
                } else {
                    index += 1
                }
            case .word(let word):
                if !fillers.contains(word) && !energyWords.contains(word) { words.append(word) }
                index += 1
            }
        }
        if let kcal {
            return AddFoodPart(text: text, kind: .quickAdd(kcal: kcal), words: words, amount: nil)
        }
        return AddFoodPart(text: text, kind: .food, words: words, amount: amount)
    }

    enum Token: Equatable {
        case number(Double)
        case word(String)
        case times
    }

    /// Words and numbers, lowercased, with an amount stuck to its unit split off ("200g", "1.5kg",
    /// "x2", "2x"), fractions ("1/2", "½", "1½") and number words ("two", "half") read as numbers.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let folded = text.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let raws = folded.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for (position, raw) in raws.enumerated() {
            var piece = raw
            if piece == "x" || piece == "×" || piece == "*" {
                tokens.append(.times)
                continue
            }
            // "x2", "×2"
            if let first = piece.first, first == "x" || first == "×", let value = number(String(piece.dropFirst())) {
                tokens += [.times, .number(value)]
                continue
            }
            // "2x", "2×"
            if let last = piece.last, last == "x" || last == "×", let value = number(String(piece.dropLast())) {
                tokens += [.number(value), .times]
                continue
            }
            if let value = number(piece) {
                tokens.append(.number(value))
                continue
            }
            if let value = numberWords[piece] {
                tokens.append(.number(value))
                continue
            }
            // "half a banana", "half cup oats", "couple of eggs"; but "half and half" and "quarter
            // pounder" are foods.
            if let value = partWords[piece], position + 1 < raws.count,
                ["a", "an", "of"].contains(raws[position + 1]) || AddFoodUnit(word: raws[position + 1]) != nil
            {
                tokens.append(.number(value))
                continue
            }
            // "200g", "1.5kg", "330ml", "½cup": a number with a unit stuck on.
            if let split = piece.firstIndex(where: { !($0.isNumber || $0 == "." || $0 == "," || $0 == "/" || fractionGlyphs[$0] != nil) }),
                split > piece.startIndex, let value = number(String(piece[..<split]))
            {
                let rest = String(piece[split...])
                if AddFoodUnit(word: rest) != nil || energyWords.contains(rest) {
                    tokens += [.number(value), .word(rest)]
                    continue
                }
            }
            piece = piece.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !piece.isEmpty { tokens.append(.word(piece)) }
        }
        return tokens
    }

    /// The most any amount can be: nobody eats more than 100 kg of anything at once.
    static let most = 100_000.0

    /// "200", "1.5", ".5", "1,5", "1,000", "1/2", "1½", "½": a positive number up to `most`, or nil.
    static func number(_ text: String) -> Double? {
        let value: Double?
        if let glyph = text.last.flatMap({ fractionGlyphs[$0] }) {
            let whole = String(text.dropLast())
            value = whole.isEmpty ? glyph : plain(whole).map { $0 + glyph }
        } else if let slash = text.firstIndex(of: "/") {
            guard let top = plain(String(text[..<slash])), let bottom = plain(String(text[text.index(after: slash)...])), bottom > 0 else {
                return nil
            }
            value = top / bottom
        } else {
            value = plain(text)
        }
        guard let value, value.isFinite, value > 0, value <= most else { return nil }
        return value
    }

    /// ASCII digits with at most one point: "1.5", ".5", "1,5" (a decimal comma) and "1,000" (a
    /// thousands one). Nothing signed, nothing in exponents, no "inf".
    static func plain(_ text: String) -> Double? {
        var text = text
        if text.contains(",") {
            let groups = text.split(separator: ",", omittingEmptySubsequences: false)
            let thousands = groups.count > 1 && (1...3).contains(groups[0].count) && groups.dropFirst().allSatisfy { $0.count == 3 }
            text = thousands ? groups.joined() : text.replacingOccurrences(of: ",", with: ".")
        }
        guard !text.isEmpty, text != ".", text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), text.filter({ $0 == "." }).count <= 1
        else { return nil }
        return Double(text.hasPrefix(".") ? "0" + text : text)
    }

    static let fractionGlyphs: [Character: Double] = ["¼": 0.25, "⅓": 1.0 / 3, "½": 0.5, "⅔": 2.0 / 3, "¾": 0.75]
    static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]
    /// Amount words that are also in foods' names, read as amounts only before "a", "of" or a unit.
    static let partWords: [String: Double] = ["half": 0.5, "quarter": 0.25, "couple": 2]
    static let energyWords: Set<String> = ["kcal", "cal", "cals", "calorie", "calories", "kcals"]
    /// Words that say nothing about which food: "a bowl of oats" is oats.
    static let fillers: Set<String> = ["a", "an", "of", "some", "and", "the", "my"]
}

/// One food (or a number of calories) in what's typed.
public struct AddFoodPart: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Words to find, maybe with an amount.
        case food
        /// "500 kcal": calories without a food, named by any other words ("pizza 800 kcal").
        case quickAdd(kcal: Double)
        /// Nothing yet after a comma: the next food is still being typed.
        case typing
    }

    /// The part as typed, trimmed.
    public var text: String
    public var kind: Kind
    /// The words to search for, lowercased, without the amount or filler words.
    public var words: [String]
    public var amount: AddFoodAmount?

    /// The words as one search.
    public var query: String { words.joined(separator: " ") }
}

/// An amount as typed: a count, with a unit if one was named, or a multiple of the usual amount.
public struct AddFoodAmount: Hashable, Sendable {
    public var count: Double
    public var unit: AddFoodUnit?
    /// "x2", "2×": times the usual amount.
    public var multiplier: Bool

    /// The most of a food's own portion a bare number is taken to count: "2 eggs" is two eggs,
    /// "banana 120" is 120 grams.
    public static let mostPieces = 12.0
    /// The least a bare number is taken as grams for a food logged by weight: "rice 2" is twice the
    /// usual, "rice 200" is 200 grams.
    public static let leastGrams = 5.0

    /// What the amount means for a food. `counted` says whether the food's usual amount is a count
    /// of something (a slice, an egg, a scoop, a serving) rather than a weight or volume.
    public func portion(counted: Bool) -> AddFoodPortion {
        if multiplier { return .times(count) }
        guard let unit else {
            if counted { return count <= Self.mostPieces ? .pieces(nil, count) : .basis(count) }
            return count >= Self.leastGrams ? .basis(count) : .times(count)
        }
        switch unit {
        case .gram, .millilitre: return .basis(count)
        case .kilogram, .litre: return .basis(count * 1000)
        case .ounce, .pound, .cup, .tablespoon, .teaspoon, .serving: return .measure(unit.rawValue, count)
        case .slice, .scoop, .piece, .egg: return .pieces(unit.portionWord, count)
        }
    }
}

/// How an amount reads for one food, for the app to turn into one of its units.
public enum AddFoodPortion: Hashable, Sendable {
    /// The usual amount, times this.
    case times(Double)
    /// Grams or millilitres, whichever the food is counted in.
    case basis(Double)
    /// A measure by its unit id ("oz", "lb", "cup", "tbsp", "tsp", "serving") and count.
    case measure(String, Double)
    /// The food's own portion, the one whose name has this word if one does ("slice", "scoop"), and
    /// a count of them.
    case pieces(String?, Double)
}

/// A unit someone types after a number.
public enum AddFoodUnit: String, Hashable, Sendable, CaseIterable {
    case gram = "g"
    case kilogram = "kg"
    case ounce = "oz"
    case pound = "lb"
    case millilitre = "ml"
    case litre = "l"
    case cup
    case tablespoon = "tbsp"
    case teaspoon = "tsp"
    case serving
    case slice
    case scoop
    case piece
    case egg

    init?(word: String) {
        guard let unit = Self.names[word] else { return nil }
        self = unit
    }

    /// "Eggs" counts eggs and is also what to look for.
    var namesFood: Bool { self == .egg }

    /// The word a food's own portion has for this unit.
    var portionWord: String? {
        switch self {
        case .slice: "slice"
        case .scoop: "scoop"
        default: nil
        }
    }

    static let names: [String: AddFoodUnit] = {
        var names: [String: AddFoodUnit] = [:]
        let spellings: [(AddFoodUnit, [String])] = [
            (.gram, ["g", "gr", "gram", "grams", "gm", "gms"]),
            (.kilogram, ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]),
            (.ounce, ["oz", "ounce", "ounces"]),
            (.pound, ["lb", "lbs", "pound", "pounds"]),
            (.millilitre, ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres"]),
            (.litre, ["l", "liter", "liters", "litre", "litres"]),
            (.cup, ["cup", "cups"]),
            (.tablespoon, ["tbsp", "tbs", "tablespoon", "tablespoons"]),
            (.teaspoon, ["tsp", "teaspoon", "teaspoons"]),
            (.serving, ["serving", "servings", "portion", "portions"]),
            (.slice, ["slice", "slices"]),
            (.scoop, ["scoop", "scoops"]),
            (.piece, ["piece", "pieces", "pc", "pcs"]),
            (.egg, ["egg", "eggs"]),
        ]
        for (unit, words) in spellings { for word in words { names[word] = unit } }
        return names
    }()
}

/// Ordering what the composer offers: the person's own foods ahead of the catalog's for the same
/// words. A typed word matches a word of a food's name that it starts ("chick" → "Chicken
/// breast"), plurals included ("eggs" → "Egg, whole").
public enum AddFoodRanking {
    /// Whether every typed word starts a word of `name`.
    public static func matches(_ words: [String], name: String) -> Bool {
        guard !words.isEmpty else { return false }
        let hay = nameWords(name)
        return words.allSatisfy { word in
            let stems = stems(of: fold(word))
            return hay.contains { candidate in stems.contains { candidate.hasPrefix($0) } }
        }
    }

    /// `candidates` with the person's own foods (a non-nil `own` score) that match every word first,
    /// best score first; then the others that match, in the order given (the catalog's ranking);
    /// then everything else in the order given. Stable, so ties keep the catalog's order.
    public static func rank<C>(_ candidates: [C], words: [String], name: (C) -> String, own: (C) -> Double?) -> [C] {
        let tiers = candidates.enumerated().map { index, candidate -> (tier: Int, score: Double, index: Int) in
            let matched = matches(words, name: name(candidate))
            if matched, let score = own(candidate) { return (0, score, index) }
            return (matched ? 1 : 2, 0, index)
        }
        return
            tiers
            .sorted { a, b in
                if a.tier != b.tier { return a.tier < b.tier }
                if a.tier == 0, a.score != b.score { return a.score > b.score }
                return a.index < b.index
            }
            .map { candidates[$0.index] }
    }

    static func fold(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func nameWords(_ name: String) -> [String] {
        fold(name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The word, and the word without a plural ending: "eggs" → "egg", "tomatoes" → "tomato",
    /// "berries" → "berr".
    static func stems(of word: String) -> [String] {
        var stems = [word]
        for ending in ["ies", "es", "s"] where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            stems.append(String(word.dropLast(ending.count)))
        }
        return stems
    }
}

/// What goes with a food: what's been eaten in the same moment as it before, most often and most
/// recently first. After yogurt, the honey and granola usually eaten with it.
public enum GoesWith {
    /// Foods eaten in the same moment as any of `anchors` (by `LogAgain`'s key: the food's id, or its
    /// name and brand) on days before `now`'s, each moment counting `0.5^(daysAgo/21)` once per food.
    /// The anchors themselves, and quick adds, aren't offered.
    public static func rank(
        with anchors: [FoodEntry], entries: [FoodEntry], now: Date, calendar: Calendar = .current, limit: Int = 8
    ) -> [LogAgainItem] {
        let keys = Set(anchors.map(LogAgain.key))
        guard !keys.isEmpty else { return [] }
        let today = Day(now, calendar: calendar)
        let earliest = today.adding(days: -180)
        let byDay = Dictionary(grouping: entries.filter { $0.day < today && $0.day > earliest }, by: \.day)
        var scores: [String: (score: Double, count: Int, latest: FoodEntry)] = [:]
        for (day, list) in byDay {
            let recency = pow(0.5, Double(day.days(until: today)) / LogAgain.halfLife)
            for moment in Timeline.moments(list) where moment.entries.contains(where: { keys.contains(LogAgain.key($0)) }) {
                var seen = Set<String>()
                for entry in moment.entries where entry.source != .quickAdd {
                    let key = LogAgain.key(entry)
                    guard !keys.contains(key), seen.insert(key).inserted else { continue }
                    var current = scores[key] ?? (0, 0, entry)
                    current.score += recency
                    current.count += 1
                    if entry.date > current.latest.date { current.latest = entry }
                    scores[key] = current
                }
            }
        }
        return scores.map { LogAgainItem(id: $0.key, template: $0.value.latest, score: $0.value.score, timesLogged: $0.value.count) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            .prefix(limit)
            .map { $0 }
    }
}
