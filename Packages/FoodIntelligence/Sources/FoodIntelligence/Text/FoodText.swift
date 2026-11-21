import Foundation

// The few word rules the model's replies are cleaned and measured with. FoodDatabase ranks
// catalog foods with its own copy; these only decide which seen foods are which.

/// A compiled ICU regular expression. `NSRegularExpression` is thread-safe, so it can be a shared
/// constant, unlike `Regex`, which isn't `Sendable`.
struct Pattern: Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = true) {
        // The patterns are literals in this module; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Where the first match is, at or after `start`. The text before `start` still counts for `\b`,
    /// and `^` is only ever the text's start.
    func firstRange(in text: String, from start: String.Index? = nil) -> Range<String.Index>? {
        let range = NSRange((start ?? text.startIndex)..., in: text)
        return regex.firstMatch(in: text, options: [.withTransparentBounds, .withoutAnchoringBounds], range: range).flatMap {
            Range($0.range, in: text)
        }
    }

    /// The first match's text, or one of its groups.
    func firstMatch(in text: String, group: Int = 0) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[range])
    }

    /// Every match's groups; a group that didn't take part is "".
    func allMatches(in text: String) -> [[String]] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    /// Every match replaced by `replacement` (literal text), or only the first.
    func replacing(in text: String, with replacement: String, all: Bool = true) -> String {
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        let range = NSRange(text.startIndex..., in: text)
        if all { return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template) }
        guard let match = regex.firstMatch(in: text, range: range), let found = Range(match.range, in: text) else { return text }
        return text.replacingCharacters(in: found, with: replacement)
    }

    /// The text around each match, with the matches themselves at odd indexes.
    func splitKeepingMatches(_ text: String) -> [String] {
        var pieces: [String] = []
        var start = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let found = Range(match.range, in: text) else { continue }
            pieces.append(String(text[start..<found.lowerBound]))
            pieces.append(String(text[found]))
            start = found.upperBound
        }
        pieces.append(String(text[start...]))
        return pieces
    }
}

enum FoodText {
    static let stopWords: Set<String> = ["a", "an", "and", "the", "of", "with", "in", "on", "or", "s", "to", "for", "style"]

    /// "Tomato slice" and "bacon strip" name a food plus how much of it.
    static let countWords: Set<String> = [
        "slice", "slices", "piece", "pieces", "strip", "strips", "leaf", "leaves", "wedge", "wedges", "chunk", "chunks",
        "serving", "servings", "portion", "portions", "cup", "cups", "bowl", "bowls", "plate", "plates", "side", "sides",
        "order", "orders", "small", "medium", "large", "regular", "jumbo", "mini", "kid", "kids", "tall", "grande", "venti",
    ]

    /// Size words describe a portion rather than count it: "2 large", not "2 larges".
    static let sizes: Set<String> = ["small", "medium", "large", "regular", "extra", "jumbo", "whole", "kid"]

    /// Catalog wording differs from everyday names: USDA files burger buns under "Rolls, hamburger".
    static let alternatives: [String: [String]] = [
        "fries": ["fries", "fried"], "bun": ["bun", "roll"], "buns": ["bun", "roll"], "ketchup": ["ketchup", "catsup"],
        "soda": ["soda", "carbonated"], "pop": ["carbonated"], "strip": ["strip", "slice"], "strips": ["strip", "slice"],
        "oatmeal": ["oatmeal", "oat"], "burger": ["burger", "hamburger"], "burgers": ["burger", "hamburger"],
    ]

    /// Lowercased without accents: "Crème" is "creme".
    static func plain(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: nil).lowercased()
    }

    /// Runs of letters and digits.
    static func tokens(_ value: String) -> [String] {
        plain(value).split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    static func words(_ value: String) -> [String] {
        tokens(value).filter { !stopWords.contains($0) }
    }

    /// The words that name the food, without counts and sizes ("mini" names products: Mini-Wheats).
    /// A bowl named last is a dish, as the catalog reads it: a poke bowl, a burrito bowl.
    static func nameWords(_ name: String) -> [String] {
        let list = words(name)
        let dish = list.count > 1 && (list.last == "bowl" || list.last == "bowls") ? list.count - 1 : -1
        let food = list.indices.filter { $0 == dish || list[$0] == "mini" || !countWords.contains(list[$0]) }.map { list[$0] }
        return Array((food.isEmpty ? list : food).prefix(6))
    }

    private static let iePlural = Pattern("(?:cook|brown|smooth|vegg|hoag|pierog|good|calor)ies$", caseInsensitive: false)
    private static let esPlural = Pattern("(?:ches|shes|xes|oes|sses)$", caseInsensitive: false)
    private static let notPlural = Pattern("(?:ss|us|is)$", caseInsensitive: false)

    /// A prefix shared by a word's singular and plural: "tomatoes" → "tomato", "berries" → "berr".
    static func stem(_ word: String) -> String {
        let n = word.count
        if n <= 3 { return word }
        if iePlural.matches(word) { return String(word.dropLast()) }
        if word.hasSuffix("ies") { return n > 5 ? String(word.dropLast(3)) : word }
        if esPlural.matches(word) { return String(word.dropLast(2)) }
        if word.hasSuffix("y") && n > 4 { return String(word.dropLast()) }
        // "Turkeys" and "Wendy's" end like "turkey" and "Wendy" do.
        if word.hasSuffix("ys") && n > 5 { return String(word.dropLast(2)) }
        if notPlural.matches(word) { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// The stems a word is searched and compared as, with the catalog's own wording.
    static func forms(_ word: String) -> [String] { alternatives[word] ?? [stem(word)] }

    /// Both sides stemmed: a match may differ only by a plural-length ending.
    static func same(_ word: String, _ form: String) -> Bool {
        word == form || (form.count > 1 && word.hasPrefix(form) && word.count - form.count <= 2)
    }

    /// Trimmed, single-spaced and at most `limit` characters.
    static func clean(_ value: String, limit: Int = 80) -> String {
        String(value.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
    }
}

/// Brands as the model writes them, which is sometimes a way of saying there isn't one.
enum Brands {
    private static let none = Pattern(#"^(?:none|n/?a|unknown|generic|homemade|no brand|unbranded|-)$"#)

    /// The brand cleaned, or nil when it's empty or says there is none ("None", "N/A", "generic").
    static func clean(_ value: String?, limit: Int = 80) -> String? {
        let brand = FoodText.clean(value ?? "", limit: limit)
        return brand.isEmpty || none.matches(brand) ? nil : brand
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
