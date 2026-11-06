import Foundation

/// What a search might be heading for: "chick" could go on to "chicken breast" or "chicken soup".
/// Read from the rows a search already found, so a typo the search corrected and the person's own
/// foods at the top of them carry through, and nothing more is asked of the catalogs per keystroke.
public enum FoodCompletions {
    /// How many are offered at a time.
    public static let shown = 5
    /// How many to hand a model choosing among them.
    public static let options = 12
    /// A phrase past this stops being something to search for.
    private static let longest = 5
    /// One of the person's own foods counts for this many catalog foods.
    private static let ownWeight = 4.0

    /// Words a phrase doesn't end on.
    private static let connectors: Set<String> = ["a", "an", "and", "for", "from", "in", "of", "on", "or", "the", "to", "with", "without", "&"]

    /// Phrases for what's typed, the likeliest first, in lower case. `label` is a food's name as a
    /// person would say it. Nothing for fewer than two letters, as the search itself waits for them.
    public static func suggest(_ query: String, from matches: [FoodMatch], limit: Int = options, label: (Food) -> String = \.name) -> [String] {
        let typed = phraseWords(query)
        guard limit > 0, typed.joined().count >= 2 else { return [] }
        var tally = Tally()
        for (rank, match) in matches.enumerated() {
            let weight = (match.personal ? ownWeight : 1) / (1 + Double(rank) * 0.1)
            for phrase in phrases(for: match.food, typed: typed, label: label) { tally.add(phrase, weight: weight) }
        }
        // Nothing reads as what's typed, but the search found foods: it took it for a typo.
        if tally.isEmpty {
            for (rank, match) in matches.prefix(shown).enumerated() {
                let words = phraseWords(label(match.food))
                tally.add(Array(words.prefix(3)), weight: 1 / (1 + Double(rank)))
            }
        }
        return tally.ranked(without: typed, limit: limit)
    }

    /// The phrases one food offers: its name up to what's typed, and on a word, and whole if that's short.
    private static func phrases(for food: Food, typed: [String], label: (Food) -> String) -> [[String]] {
        let title = phraseWords(label(food))
        var words = title
        var last = lastMatch(of: typed, in: words)
        // "fage yog": the brand was typed too, so it's part of what's searched for.
        if last == nil, let brand = food.brand {
            words = phraseWords(brand) + title
            last = lastMatch(of: typed, in: words)
        }
        guard let last else { return [] }
        var ends = [last + 1, last + 2]
        if words.count <= 4 { ends.append(words.count) }
        var phrases: [[String]] = []
        for var end in ends where end <= words.count {
            // On past a connector: "rice with" says less than "rice with beans".
            while end < words.count, connectors.contains(words[end - 1]) { end += 1 }
            var phrase = Array(words[..<max(min(end, longest), last + 1)])
            while let tail = phrase.last, connectors.contains(tail), phrase.count > last + 1 { phrase.removeLast() }
            if !phrases.contains(phrase) { phrases.append(phrase) }
        }
        return phrases
    }

    /// Where the last typed word falls among `words`, when each typed word starts one of them.
    private static func lastMatch(of typed: [String], in words: [String]) -> Int? {
        var last = 0
        var used = Set<Int>()
        for word in typed {
            let wanted = fold(word)
            guard let index = words.indices.first(where: { !used.contains($0) && reads(fold(words[$0]), as: wanted) }) else { return nil }
            used.insert(index)
            last = max(last, index)
        }
        return last
    }

    /// "apples" typed reads as "apple" too, which a catalog's singular name wouldn't otherwise start.
    private static func reads(_ word: String, as typed: String) -> Bool {
        word.hasPrefix(typed) || singular(word) == singular(typed)
    }

    private static func fold(_ word: String) -> String { word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    private static func singular(_ word: String) -> String { word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word }

    /// Lower-case words, up to any note in brackets.
    static func phraseWords(_ text: String) -> [String] {
        let plain = text.prefix { $0 != "(" }
        return plain.split { $0.isWhitespace || $0 == "," || $0 == "/" }.compactMap { part in
            let word = part.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "&"))).lowercased()
            return word.isEmpty ? nil : word
        }
    }

    /// Phrases by how much weight they've gathered. One said two ways ("banana", "bananas") is one.
    private struct Tally {
        private var rows: [String: (words: [String], weight: Double)] = [:]

        var isEmpty: Bool { rows.isEmpty }

        static func key(_ words: [String]) -> String { words.map { singular(fold($0)) }.joined(separator: " ") }

        mutating func add(_ words: [String], weight: Double) {
            guard !words.isEmpty else { return }
            rows[Self.key(words), default: (words, 0)].weight += weight
        }

        func ranked(without typed: [String], limit: Int) -> [String] {
            let same = Self.key(typed)
            let order = rows.filter { $0.key != same }.values.sorted { a, b in
                if a.weight != b.weight { return a.weight > b.weight }
                if a.words.count != b.words.count { return a.words.count < b.words.count }
                return a.words.lexicographicallyPrecedes(b.words)
            }
            return order.prefix(limit).map { $0.words.joined(separator: " ") }
        }
    }
}
