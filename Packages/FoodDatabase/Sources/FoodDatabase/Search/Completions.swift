import Foundation

/// What a search might be heading for: "chick" could go on to "chicken breast" or "chicken soup".
/// The person's own foods come first, then the everyday foods, the ways they're said ("grilled
/// salmon", "fat free milk") and the most scanned brands that read as typed (`EverydayPhrases`,
/// `PopularBrands`), then what the search's rows say: products and the foods those lists don't have. The rows are the ones the search already found, so a
/// typo it corrected carries through and nothing more is asked of the catalogs per keystroke.
public enum FoodCompletions {
    /// How many are offered at a time.
    public static let shown = 5
    /// How many to hand a model choosing among them.
    public static let options = 12
    /// A phrase past this stops being something to search for.
    private static let longest = 5
    /// One of the person's own foods counts for this many catalog foods.
    private static let ownWeight = 4.0
    /// A phrase found by a later word ("yog" for Greek yogurt) counts this much of one that
    /// starts as typed.
    private static let laterWord = 0.6
    private static let laterBrand = 0.5
    /// Typed words found in a name's order but apart ("protein b" in "protein powder, whey
    /// based"), and out of its order ("protein b" in "Barilla Protein+"), count this much of
    /// words found side by side.
    private static let apart = 0.6
    private static let outOfOrder = 0.35
    /// A packaged food scanned this much (the catalog's popularity) is one people look for by
    /// name, so its whole name is worth offering though no other food shares it.
    private static let popular = 2.0
    /// The most scanned brand counts this much beside the everyday foods' 7 to 14, the last on
    /// the list this much: a brand is what's meant once the letters leave the plain foods behind.
    private static let brandWeights = (most: 6.0, least: 2.5)

    /// Words a phrase doesn't end on.
    private static let connectors: Set<String> = ["a", "an", "and", "for", "from", "in", "of", "on", "or", "the", "to", "with", "without", "&"]

    /// A way a food is said ("grilled salmon") found by the food's word counts this much: after
    /// "oni", onion rings come before sauteed onions.
    private static let laterWay = 0.4
    /// How many ways of one kind ("whole wheat …") are offered while anything else is.
    private static let waysOfAKind = 2

    /// The everyday foods, the ways they're said and the brands, each with its words as compared,
    /// its weight, and for a way the word it starts with.
    private static let listed: [(words: [String], compared: [String], weight: Double, brand: Bool, way: String?)] = {
        let brands = PopularBrands.names.enumerated().map { rank, name in
            let share = Double(rank) / Double(max(1, PopularBrands.names.count - 1))
            return (name.split(separator: " ").map(String.init), brandWeights.most - (brandWeights.most - brandWeights.least) * share, true)
        }
        // The ways the everyday foods are said, where the list doesn't have them already, in
        // the singular or the plural: "fried eggs" is its "fried egg".
        let foods = Set(EverydayPhrases.all.map { Tally.key($0.words) })
        let said = EverydayPhrases.said.filter { !foods.contains(Tally.key($0.words)) }
        return (EverydayPhrases.all.map { ($0.words, $0.weight, false) } + brands).map { ($0.0, $0.0.map(plain), $0.1, $0.2, nil) }
            + said.map { ($0.words, $0.words.map(plain), $0.weight, false, $0.words.first) }
    }()

    /// Phrases for what's typed, the likeliest first, in lower case. `label` is a food's name as a
    /// person would say it. Nothing for fewer than two letters, as the search itself waits for them.
    public static func suggest(_ query: String, from matches: [FoodMatch], limit: Int = options, label: (Food) -> String = \.name) -> [String] {
        let typed = phraseWords(query)
        let wanted = typed.map(plain)
        guard limit > 0, wanted.joined().count >= 2 else { return [] }
        var tally = Tally()
        for (rank, match) in matches.enumerated() where match.personal || !match.away {
            let weight = (match.personal ? ownWeight : 1) / (1 + Double(rank) * 0.1)
            for cut in cuts(for: match.food, typed: wanted, label: label) { tally.add(cut, weight: weight * cut.fit, from: match) }
        }
        for phrase in listed {
            if let found = place(of: wanted, in: phrase.compared) {
                // A brand found by a later word is a longer reach than a food: "ban" isn't La Banderita.
                // And a way is only offered by words typed in its order: "chicken b" isn't baked chicken.
                guard phrase.way == nil || found.ordered else { continue }
                let reach = found.fit == 1 ? 1 : phrase.brand ? found.fit * laterBrand : phrase.way != nil ? laterWay : found.fit
                tally.add(listed: phrase.words, weight: phrase.weight * reach, way: phrase.way)
            } else if wanted.count == 1, phrase.compared.count > 1, wanted[0].count > phrase.compared[0].count,
                phrase.compared.joined().hasPrefix(wanted[0])
            {
                // Typed as one word: "hotd" is on its way to a hot dog, "redb" to Red Bull.
                tally.add(listed: phrase.words, weight: phrase.weight)
            }
        }
        // The best food found reads as nothing typed, and has a word a typo or two from it: the
        // search took it for that word, so the suggestions go on from there ("chiken" offers
        // chicken, then chicken breast).
        if wanted.count == 1, !tally.hasListed, let best = matches.first(where: { $0.personal || !$0.away }),
            cuts(for: best.food, typed: wanted, label: label).isEmpty,
            let meant = phraseWords(label(best.food)).first(where: { word in
                let compared = plain(word)
                return compared != wanted[0] && typos(wanted[0], compared, limit: allowedTypos(wanted[0])) <= allowedTypos(wanted[0])
            }), allowedTypos(wanted[0]) > 0
        {
            // With what does read as typed among the other foods: "cholu" may be a typo, and
            // is as far as Cholula is typed.
            let asTyped = tally.ranked(without: wanted, limit: limit)
            let onward = suggest(meant, from: matches, limit: limit - 1, label: label)
            var offered = [meant]
            for phrase in asTyped + onward where !offered.contains(phrase) { offered.append(phrase) }
            return Array(offered.prefix(limit))
        }
        var phrases = tally.ranked(without: wanted, limit: limit)
        // Nothing reads as what's typed, but the search found foods: it took it for a typo.
        if phrases.isEmpty, tally.isEmpty {
            var names = Tally()
            for (rank, match) in matches.prefix(shown).enumerated() {
                let words = Array(phraseWords(label(match.food)).prefix(3))
                names.add(Cut(words: words, whole: true, fit: 1), weight: 1 / (1 + Double(rank)), from: match)
            }
            phrases = names.ranked(without: wanted, limit: limit, anything: true)
        }
        return phrases
    }

    /// A phrase cut from a food's name: whether it's the whole of the name, the word after it
    /// when it isn't, and how well the typed words sit in it.
    private struct Cut {
        var words: [String]
        var whole: Bool
        var fit: Double
        /// It starts with the first word typed.
        var leads = true
        /// It ends on an everyday food.
        var named = false
        /// The whole of a chain's item as USDA lists it, found by a later word of its name.
        var item = false
    }

    private static let everyday = Set(EverydayPhrases.all.map { Tally.key($0.words) })

    /// The phrases one food offers: its name up to what's typed, and on a word, and whole if that's short.
    private static func cuts(for food: Food, typed: [String], label: (Food) -> String) -> [Cut] {
        var said = label(food)
        var words = phraseWords(said)
        var found = place(of: typed, in: words.map(plain))
        // What a chain calls its food can be in the catalog's name and not in how it's said:
        // "McDONALD'S, Egg McMUFFIN" is said "McDonald's".
        if found == nil, food.source == .usda, food.name != said, food.name.contains(","), !brandWords(name: food.name, brand: "").isEmpty {
            said = food.name
            words = phraseWords(said)
        }
        // A name still written as a catalog files it ("McDONALD'S, BIG MAC", "Babyfood, GERBER,
        // banana with orange") is read a part at a time: "big m" is on its way to a Big Mac.
        let chain = food.source == .usda && !brandWords(name: food.name, brand: "").isEmpty
        if said.contains(",") {
            for part in said.split(separator: ",") {
                let partWords = phraseWords(String(part))
                if let place = place(of: typed, in: partWords.map(plain)) {
                    (words, found) = (partWords, place)
                    break
                }
            }
        }
        // A chain typed whole goes on to its items as the catalog lists them: "kfc" to KFC
        // biscuit, where the name as it's said is the chain alone.
        var chainWords = 0
        if chain, let place = found, place.last == words.count - 1 {
            let parts = food.name.split(separator: ",")
            if parts.count > 1, phraseWords(String(parts[0])).map(plain) == words.map(plain) {
                chainWords = words.count
                words += phraseWords(String(parts[1]))
            }
        }
        // "fage yog": the brand was typed too, so it's part of what's searched for.
        var brand: [String] = []
        if found == nil, let name = food.brand {
            brand = phraseWords(name)
            words = brand + words
            found = place(of: typed, in: words.map(plain))
        }
        guard let found else { return [] }
        let own = (food.brand.map(phraseWords) ?? []).map(plain)
        let last = found.last
        var ends = [last + 1, last + 2]
        if words.count <= 4 { ends.append(words.count) }
        var cuts: [Cut] = []
        for var end in ends where end <= words.count {
            // On past a connector: "rice with" says less than "rice with beans".
            while end < words.count, connectors.contains(words[end - 1]) { end += 1 }
            var phrase = Array(words[..<max(min(end, longest), last + 1)])
            while let tail = phrase.last, connectors.contains(tail), phrase.count > last + 1 { phrase.removeLast() }
            // A label that says a word twice ("Apple Apple") isn't a phrase.
            guard !cuts.contains(where: { $0.words == phrase }), Set(phrase.map(plain)).count == phrase.count else { continue }
            // A brand by itself is a whole thing to search for, as a whole name is, wherever
            // it was found: the "Wheat Thins" a name starts with are the brand's.
            let whole = phrase.count == words.count || phrase.count == chainWords || (!own.isEmpty && phrase.map(plain) == own)
            // Part of a name is a phrase where it ends on a food: "kirkland signature almonds".
            var named = false
            if !whole, phrase.count > 1 {
                named = (1...min(3, phrase.count - 1)).contains { everyday.contains(Tally.key(Array(phrase.suffix($0)))) }
            }
            // A chain's own word for its item is one to search by, though the name starts
            // otherwise: "mcnug" is on its way to Chicken McNuggets.
            let item = chain && whole && !found.leads && typed.count == 1 && typed[0].count >= 4
            cuts.append(Cut(words: phrase, whole: whole, fit: found.fit, leads: found.leads, named: named, item: item))
        }
        return cuts + kinds(of: food, typed: typed, label: label).filter { kind in !cuts.contains { $0.words == kind.words } }
    }

    /// A brand typed first goes on to the foods it makes: "chobani" to Chobani Greek yogurt and
    /// "kirkland p" to Kirkland protein bars, wherever the food comes in the product's name
    /// ("Non-Fat Greek Yogurt, Vanilla").
    private static func kinds(of food: Food, typed: [String], label: (Food) -> String) -> [Cut] {
        guard let name = food.brand else { return [] }
        let brand = phraseWords(name)
        guard let first = brand.first, reads(plain(first), as: typed[0]) else { return [] }
        let words = phraseWords(label(food))
        var kinds: [Cut] = []
        var taken = Set<Int>()
        // The longest food first, so Greek yogurt isn't also offered as yogurt.
        for count in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - count) where !(start..<(start + count)).contains(where: taken.contains) {
                let food = Array(words[start..<(start + count)])
                guard everyday.contains(Tally.key(food)), !food.contains(where: brand.contains) else { continue }
                taken.formUnion(start..<(start + count))
                if let found = place(of: typed, in: (brand + food).map(plain)) {
                    kinds.append(Cut(words: brand + food, whole: false, fit: found.fit, leads: found.leads, named: true))
                }
            }
        }
        return kinds
    }

    /// Where the typed words fall among `words` (both as compared), when each starts one of them:
    /// the place of the last, and how well they sit. A phrase that starts as typed, with the
    /// words side by side, fits in full.
    private static func place(of typed: [String], in words: [String]) -> (last: Int, fit: Double, leads: Bool, ordered: Bool)? {
        var places: [Int] = []
        for word in typed {
            guard let index = words.indices.first(where: { !places.contains($0) && reads(words[$0], as: word) }) else {
                // Typed apart, a name written as one word: "chick f" is on its way to
                // Chick-fil-A, "cap n" to Cap'n Crunch.
                let joined = typed.joined()
                guard typed.count > 1, let index = words.firstIndex(where: { $0.count > typed[0].count && $0.hasPrefix(joined) }) else { return nil }
                return (index, index == 0 ? 1 : laterWord, index == 0, true)
            }
            places.append(index)
        }
        guard let first = places.first, let last = places.max() else { return nil }
        var fit = first == 0 ? 1 : laterWord
        let ordered = zip(places, places.dropFirst()).allSatisfy { $0 < $1 }
        if places.count > 1 {
            let beside = zip(places, places.dropFirst()).allSatisfy { $1 == $0 + 1 }
            fit *= beside ? 1 : ordered ? apart : outOfOrder
        }
        return (last, fit, first == 0, ordered)
    }

    /// "apples" typed reads as "apple" too, which a catalog's singular name wouldn't otherwise start.
    private static func reads(_ word: String, as typed: String) -> Bool {
        !typed.isEmpty && (word.hasPrefix(typed) || singular(word) == singular(typed))
    }

    private static func fold(_ word: String) -> String { word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// A word as it's compared: without case, accents or the marks inside it, so "mcdonald's" is
    /// "mcdonalds" as it's typed and "protein+" is protein.
    private static func plain(_ word: String) -> String {
        let folded = fold(word)
        guard !folded.unicodeScalars.allSatisfy(isWordScalar) else { return folded }
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(isWordScalar)))
    }

    /// "Potatoes" is "potato" as "eggs" is "egg".
    private static func singular(_ word: String) -> String {
        if word.count > 5, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        return word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
    }

    /// Lower-case words, up to any note in brackets, without a trademark's sign.
    static func phraseWords(_ text: String) -> [String] {
        let plain = text.prefix { $0 != "(" }
        return plain.split { $0.isWhitespace || $0 == "," || $0 == "/" }.compactMap { part in
            let word = part.trimmingCharacters(in: marks).lowercased()
            return word.isEmpty ? nil : word
        }
    }

    private static let marks = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "&")).union(
        CharacterSet(charactersIn: "®™©"))

    /// Phrases by how much weight they've gathered. One said two ways ("banana", "bananas") is one.
    private struct Tally {
        private struct Row {
            var words: [String]
            /// What the lists give it, and what the foods found do.
            var weight = 0.0
            var found = 0.0
            /// It starts as typed in some food's name.
            var leads = false
            /// One of the person's own foods says it.
            var own = false
            /// An everyday food or a brand people scan.
            var listed = false
            /// For a way a food is said, the word it starts with: "grilled".
            var way: String?
            /// How many foods say it, and whether it's the whole of one's name.
            var foods = 0
            var whole = false
            /// A food that isn't a label's: a packaged food's whole name is one product, and
            /// worth offering by itself only when it's one people look for.
            var plain = false
            var popularity = 0.0
            /// It ends on an everyday food: "chobani greek yogurt", from the flavours' names.
            var named = false
            /// A chain's item, found by its own word for it.
            var item = false
        }

        private var rows: [String: Row] = [:]

        var isEmpty: Bool { rows.isEmpty }

        static func key(_ words: [String]) -> String { words.map { singular(FoodCompletions.plain($0)) }.joined(separator: " ") }

        var hasListed: Bool { rows.values.contains(where: \.listed) }

        mutating func add(_ cut: Cut, weight: Double, from match: FoodMatch) {
            guard !cut.words.isEmpty else { return }
            var row = rows[Self.key(cut.words)] ?? Row(words: cut.words)
            row.found += weight
            row.foods += 1
            if cut.leads { row.leads = true }
            if match.personal { row.own = true }
            if cut.whole { row.whole = true }
            if match.food.source != .off { row.plain = true }
            row.popularity = max(row.popularity, match.food.popularity)
            if cut.named { row.named = true }
            if cut.item { row.item = true }
            rows[Self.key(cut.words)] = row
        }

        mutating func add(listed words: [String], weight: Double, way: String? = nil) {
            var row = rows[Self.key(words)] ?? Row(words: words)
            // As the list says it ("hot dog"), not as one label happens to ("hot dogs nature").
            row.words = words
            row.weight += weight
            row.listed = true
            row.way = way
            rows[Self.key(words)] = row
        }

        /// Whether a phrase is something to search for. A whole name has to be shared, a plain
        /// food's, or a product people look for: one label's wording isn't a search ("hot dogs
        /// nature", "greek yougert"). Part of a name has to end on a food: "chobani greek
        /// yogurt" from its flavours' names, not "green", which starts many names and is none,
        /// nor "greek style".
        private func worth(_ row: Row) -> Bool {
            if row.own || row.listed { return true }
            // A word found later in a name or two is a stretch: "tun" isn't a tunnel-boned leg of lamb.
            guard row.leads || row.foods >= 3 || row.item else { return false }
            if row.whole { return row.foods >= 2 || row.plain || row.popularity >= popular }
            return row.named && (row.foods >= 2 || row.plain)
        }

        /// A listed phrase goes by its place on the list, and the foods found only settle ties
        /// among its neighbours: sixty rows for "co" are mostly cookies, and coffee is still
        /// what's logged most.
        private func total(_ row: Row) -> Double { row.weight + (row.listed ? min(row.found, 2) : row.found) }

        /// `typed` as compared. A phrase that is what's typed isn't offered, written as one word
        /// or as two.
        func ranked(without typed: [String], limit: Int, anything: Bool = false) -> [String] {
            let same = typed.map(singular).joined()
            let order = rows.filter { $0.key.replacing(" ", with: "") != same && (anything || worth($0.value)) }.values.sorted { a, b in
                if a.own != b.own { return a.own }
                let (x, y) = (total(a), total(b))
                if x != y { return x > y }
                if a.words.count != b.words.count { return a.words.count < b.words.count }
                return a.words.lexicographicallyPrecedes(b.words)
            }
            // A few ways of one kind, then whatever else there is, then the rest of them: "who"
            // is whole milk, whole wheat bread and pasta, and still a Whopper.
            var kinds: [String: Int] = [:]
            var first: [Row] = []
            var held: [Row] = []
            for row in order {
                if let way = row.way {
                    kinds[way, default: 0] += 1
                    if kinds[way, default: 0] > waysOfAKind {
                        held.append(row)
                        continue
                    }
                }
                first.append(row)
            }
            return (first + held).prefix(limit).map { $0.words.joined(separator: " ") }
        }
    }
}
