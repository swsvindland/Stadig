import Foundation
import Synchronization

/// A typed search's ranked catalog foods, the search as it was read (see `Respelt`), the corrections
/// it searched for, the words that named a brand and the words the catalogs barely know.
struct CatalogSearch: Sendable {
    var ranked: [Ranked] = []
    var text: String
    var fixes: Fixes = [:]
    var brand: [String] = []
    var doubted: Set<String> = []
    /// The other ways of writing the search's names, as one word or as two.
    var also: Fixes = [:]
    /// The foods found that aren't known to be sold in the phone's country.
    var elsewhere: Set<String> = []
    /// What was typed, where the reading added the catalogs' words for it ("ranch" is read as
    /// "ranch salad dressing"): the person's own foods are found by this, so their Ranch Dip still is.
    var typed: String?

    /// Everything a food's words may be read as: the corrections, then the other ways of writing.
    var readings: Fixes { fixes.merging(also) { $0 + $1 } }
    var respelt: Set<String> { Set(also.values.joined()) }
}

/// A name labels write as one word and as two, or that was typed as one and is written as two.
struct Compound: Sendable {
    /// More foods have it as one word ("popcorn", "kitkat") than as two ("red bull", "hot dog").
    var joined: Bool
    /// Both ways are the same kind of food: Redbull and Red Bull are both energy drinks, while
    /// Butterball is turkey and "butter balls" are sweets.
    var same: Bool
    /// Some label has the one word, so it is searched for too.
    var known = true
}

/// A search with each name labels write as one word or as two written the usual way, so "redbull"
/// and "red bull" are one search, as "pop corn" and "popcorn" are.
struct Respelt {
    var text: String
    /// The other way of writing it, for each word it stands for: "redbull" for "red" and for
    /// "bull", "pop corn" for "popcorn". Unlike a correction, it matches as well as the words do.
    var also: Fixes = [:]
    var forms: Set<String> = []
    /// What was typed, when `text` has words added to it: "ranch" for "ranch salad dressing".
    var typed: String?
}

/// A search of the catalogs and what it found, kept while the next few are typed.
struct RecentSearch: Sendable {
    struct Asked: Equatable, Sendable {
        var typed: String
        var out: String?
        var sides: [String]
        var beside: [String]
    }

    /// How many are kept: the foods typed together, the search as typed and a letter or two back.
    static let kept = 8

    var asked: Asked
    /// How often each of the person's own foods was logged, which ranks them.
    var known: [String: Double]
    var found: CatalogSearch
}

/// What the catalogs make of a typed word: whether they barely know it as typed, and what it
/// probably meant.
struct Spelling: Sendable {
    var doubted = false
    var fixes: [String] = []
}

/// How many rows a full-text match keeps from each catalog.
struct MatchLimits {
    var generic: Int
    var branded: Int

    static let few = MatchLimits(generic: 30, branded: 30)
    /// The generic catalog is small, so a deeper limit there reaches plain foods that rank below
    /// variations, and below the dishes made with them: a thousand of its foods have "chicken".
    static let typed = MatchLimits(generic: 500, branded: 60)
    /// What AI matching reads per query.
    static let matching = MatchLimits(generic: 400, branded: 30)
    /// Enough foods to say what a name's foods are usually like.
    static let sample = MatchLimits(generic: 12, branded: 12)
}

/// Words with insertion order, counting foods.
private struct OrderedCounts {
    private(set) var keys: [String] = []
    private(set) var values: [String: Int] = [:]

    mutating func add(_ key: String, _ count: Int) {
        if let value = values[key] {
            values[key] = value + count
        } else {
            keys.append(key)
            values[key] = count
        }
    }

    mutating func set(_ key: String, _ count: Int) {
        if values[key] == nil { keys.append(key) }
        values[key] = count
    }

    var total: Int { values.values.reduce(0, +) }
}

/// Whether foods answer a typed search, for the person's own lists, by the rule a catalog row needs
/// to appear: every word the search looks for is in the food's name or brand, each as a prefix or
/// as corrected ("chiken" finds chicken), and every number exactly ("2% milk" is not whole milk).
/// "flat white" doesn't find white rice, nor "rice cake" plain rice.
struct QueryMatcher {
    private let target: [String]
    private let numbers: [String]
    private let query: CoverageQuery

    init(_ text: String, fixes: Fixes = [:], doubted: Set<String> = [], respelt: Set<String> = []) {
        target = searchedWords(readQuery(text).words)
        numbers = target.filter(isNumber)
        query = CoverageQuery(
            seen: Named(name: text, brand: ""), target: target, prefix: true, fixes: fixes, doubted: doubted, respelt: respelt)
    }

    func matches(_ food: Food) -> Bool {
        guard target.contains(where: { !isNumber($0) }) else { return false }
        if !numbers.isEmpty {
            let found = tokens("\(food.name) \(food.brand ?? "")")
            if !numbers.allSatisfy(found.contains) { return false }
        }
        return query.cover(FoodText(food)).missing == 0
    }
}

/// One full-text expression to run against one catalog.
struct MatchJob: Sendable {
    var catalog: Catalog
    var expression: String
    var limit: Int
    var lead: String
    /// How the brands of the foods wanted start, in place of a lead: "swiss m".
    var begun = ""

    func run() -> [Catalog.Hit] {
        begun.isEmpty ? catalog.match(expression, limit: limit, lead: lead) : catalog.match(expression, limit: limit, brandBegun: begun)
    }
}

extension FoodCatalog {
    private var branded: [Catalog] { catalogs.filter { $0.kind == .branded } }

    /// A full-text expression for each of the given catalogs, generic foods first: each catalog
    /// ranks within its own corpus, and generic foods lead for ingredient searches.
    func jobs(_ catalogs: [Catalog], _ expression: String, _ limits: MatchLimits = .few, lead: String = "") -> [MatchJob] {
        catalogs.map { MatchJob(catalog: $0, expression: expression, limit: $0.kind == .generic ? limits.generic : limits.branded, lead: lead) }
    }

    /// Runs groups of jobs at once, each on its own connection, and gives each group's hits in order.
    func run(_ groups: [[MatchJob]]) -> [[Catalog.Hit]] {
        let all = groups.flatMap { $0 }
        let results = Mutex<[[Catalog.Hit]]>(Array(repeating: [], count: all.count))
        if all.count == 1 {
            results.withLock { $0[0] = all[0].run() }
        } else if all.count > 1 {
            DispatchQueue.concurrentPerform(iterations: all.count) { i in
                let hits = all[i].run()
                results.withLock { $0[i] = hits }
            }
        }
        let hits = results.withLock { $0 }
        var grouped: [[Catalog.Hit]] = []
        var next = 0
        for group in groups {
            grouped.append(hits[next..<(next + group.count)].flatMap { $0 })
            next += group.count
        }
        return grouped
    }

    /// Runs a full-text expression against the given catalogs at once; see `jobs`.
    func match(_ catalogs: [Catalog], _ expression: String, _ limits: MatchLimits = .few, lead: String = "") -> [Catalog.Hit] {
        run([jobs(catalogs, expression, limits, lead: lead)])[0]
    }

    private func count(_ sql: String, _ parameters: [SQLValue]) -> OrderedCounts {
        var found = OrderedCounts()
        for catalog in catalogs { for row in catalog.terms(sql, parameters) { found.add(row.term, row.foods) } }
        return found
    }

    /// What a typed word probably meant when the catalogs barely know it: the far more common
    /// catalog words it is a typo or two from ("chiken" is chicken, "chikc" the start of chicken),
    /// or the two words it joins ("peanutbutter"). A word with others typed after it is `whole`,
    /// not half typed, so only whole catalog words are read into it: "perue" before "chicken
    /// tenders" is Perdue or Peru, not the start of "perfect". Remembered for the launch.
    func spell(_ word: String, whole: Bool = false) -> Spelling {
        // No word has a space, so a whole word is remembered apart from the same one half typed.
        let remembering = whole ? "\(word) " : word
        if let remembered = spellings.withLock({ $0[remembering] }) { return remembered }
        let form = stem(word)
        let size = length(word)
        let limit = allowedTypos(length: size)
        let range = "SELECT term, foods FROM terms WHERE term >= ? AND term < ?"
        var known = uncommon
        // A word with a catalog wording of its own is known: "coke" is cola, not a typo of "cake".
        if limit > 0 && !word.unicodeScalars.contains(where: isDigit) && !typedAlternatives.contains(word) {
            known = Double(count(range, [.text(form), .text(form + "\u{FFFF}")]).total)
        }
        var fixes: [String] = []
        var doubted = known < rare || (known < uncommon && size >= 6)
        if doubted {
            let least = (known < rare ? 10 : 75) * (known + 1)
            // A half-typed word is the start of a catalog word; typos rarely touch both of the first
            // two letters, so words starting with either are read. A whole word may have a typo
            // anywhere. What it meant is in `least` foods, nearly always through one word in many
            // of them, so the words in a few foods, half of every catalog's, are left unread.
            var terms = OrderedCounts()
            let units = Array(word.utf16)
            var firsts: [String] = []
            for unit in units.prefix(2) {
                let letter = String(decoding: [unit], as: UTF16.self)
                if !firsts.contains(letter) { firsts.append(letter) }
            }
            for start in firsts {
                let found = count(
                    "\(range) AND length(term) >= ? AND foods >= ?",
                    [
                        .text(start), .text(start + "\u{FFFF}"), .integer(Int64(size - limit)),
                        .integer(Int64(max(2, (least / 25).rounded(.down)))),
                    ])
                for key in found.keys { terms.set(key, found.values[key]!) }
            }
            let near = count(
                "SELECT term, foods FROM terms WHERE length(term) BETWEEN ? AND ? AND foods >= ?",
                [.integer(Int64(size - limit)), .integer(Int64(size + limit)), .integer(Int64((least / 2).rounded(.up)))])
            for key in near.keys { terms.set(key, near.values[key]!) }

            var meter = TypoMeter()
            var meantKeys: [String] = []
            var meant: [String: (edits: Int, foods: Int)] = [:]
            for term in terms.keys {
                let foods = terms.values[term]!
                let letters = Array(term.utf16)
                let found: (edits: Int, length: Int)?
                if whole {
                    let edits = meter.distance(units[...], letters[...], limit: limit)
                    found = edits <= limit ? (edits, letters.count) : nil
                } else {
                    found = meter.misread(units, letters)
                }
                guard let found, found.edits > 0 else { continue }
                let key = stem(String(decoding: letters[..<found.length], as: UTF16.self))
                // A word and its plural are one reading, as near as the nearer of them and in the
                // foods of both: "triscuiits" is one letter from Triscuits, the name on few labels,
                // and so means Triscuit.
                if let last = meant[key] {
                    meant[key] = (min(found.edits, last.edits), last.foods + foods)
                } else {
                    meantKeys.append(key)
                    meant[key] = (found.edits, foods)
                }
            }
            let common = meantKeys.filter { Double(meant[$0]!.foods) >= least }
            var nearest: (edits: Int, foods: Int)?
            if let fewest = common.map({ meant[$0]!.edits }).min() {
                let likely = common.filter { meant[$0]!.edits == fewest }
                    .enumerated().sorted { a, b in
                        let (x, y) = (meant[a.element]!.foods, meant[b.element]!.foods)
                        return x != y ? x > y : a.offset < b.offset
                    }
                    .map(\.element)
                // A second reading only when it is nearly as likely: "brest" is breast or best.
                let top = Double(meant[likely[0]]!.foods)
                let picked = likely.prefix(2).filter { Double(meant[$0]!.foods) >= top / 10 }
                // "tortil" already searches for tortilla.
                fixes = picked.filter { key in !picked.contains { $0 != key && starts(key, $0) } }
                nearest = (fewest, meant[likely[0]]!.foods)
            }
            if (nearest?.edits ?? .max) > 1 && known < rare && size >= 6 {
                // Two words typed without the space between them, which is likelier than two typos
                // when both words are in more foods than the word two typos away: "organicvalley"
                // is Organic Valley, not "organically".
                let splits = (0..<(size - 5)).map { i in
                    (String(decoding: units[..<(i + 3)], as: UTF16.self), String(decoding: units[(i + 3)...], as: UTF16.self))
                }
                var parts: [String] = []
                for (left, right) in splits { for part in [left, right] where !parts.contains(part) { parts.append(part) } }
                let marks = Array(repeating: "?", count: parts.count).joined(separator: ",")
                let found = count("SELECT term, foods FROM terms WHERE term IN (\(marks))", parts.map(SQLValue.text))
                var best: (left: String, right: String, foods: Int)?
                for (left, right) in splits {
                    let foods = min(found.values[left] ?? 0, found.values[right] ?? 0)
                    if best == nil || foods > best!.foods { best = (left, right, foods) }
                }
                if let best, Double(best.foods) >= least, best.foods > nearest?.foods ?? 0 { fixes = ["\(best.left) \(stem(best.right))"] }
            }
        }
        // A name the catalogs know isn't the commoner word it would be a long shot from:
        // "skittles" isn't skinless, "triscuit" biscuit, a "mcchicken" chicken or "halo" halibut
        // begun. A likelier typo is still read ("protien", whatever labels spell it so).
        if fixes.contains(where: { isLongShot($0, for: word) }), isName(word, whole: whole) {
            fixes.removeAll { isLongShot($0, for: word) }
            doubted = !fixes.isEmpty
        }
        // And a word USDA wrote, whole or in the plural, is no typo of any other: "ghee" isn't
        // green, nor a "collard" Holland.
        if doubted,
            catalogs.contains(where: {
                $0.kind == .generic && !$0.terms("SELECT term, foods FROM terms WHERE term IN (?, ?)", [.text(word), .text(word + "s")]).isEmpty
            })
        {
            fixes = []
            doubted = false
        }
        let spelling = Spelling(doubted: doubted, fixes: fixes)
        spellings.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[remembering] = spelling
        }
        return spelling
    }

    /// Whether a word is a name as typed: one in a name USDA wrote, or a word of the brand of a
    /// food people scan here. Labels' own names don't count, as they spell a word as they like.
    /// A word still being typed is one that starts such a name, by its letters as typed: "skip"
    /// is on its way to Skippy, where "bred" isn't a brand sold elsewhere begun.
    private func isName(_ word: String, whole: Bool) -> Bool {
        let key = "name \(whole ? "whole" : "begun") \(word)"
        if let remembered = brandish.withLock({ $0[key] }) { return remembered }
        let named = catalogs.contains { catalog in
            if catalog.kind == .generic {
                let found =
                    whole
                    ? catalog.terms("SELECT term, foods FROM terms WHERE term IN (?, ?, ?)", [.text(word), .text(stem(word)), .text(word + "s")])
                    : catalog.terms("SELECT term, foods FROM terms WHERE term >= ? AND term < ? LIMIT 1", [.text(word), .text(word + "\u{FFFF}")])
                return !found.isEmpty
            }
            let forms = whole && stem(word) != word ? [word, stem(word)] : [word]
            let brands = forms.map { "\"\($0)\"\(whole ? "" : "*")" }.joined(separator: " OR ")
            return catalog.isScanned("{brand}: (\(brands))", atLeast: 1.5)
        }
        brandish.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[key] = named
        }
        return named
    }

    // MARK: One word or two

    /// A name on fewer labels than this, written either way, isn't one labels write both ways.
    private static let fewLabels = 20

    /// How many foods have a word or its singular, whole: "peach" is one, "peache" on its way to
    /// "peaches" isn't yet.
    private func foods(named word: String) -> Int {
        let forms = stem(word) == word ? [word] : [word, stem(word)]
        let marks = Array(repeating: "?", count: forms.count).joined(separator: ",")
        return count("SELECT term, foods FROM terms WHERE term IN (\(marks))", forms.map(SQLValue.text)).total
    }

    /// Two words in a row, in the catalogs' full-text syntax.
    private func inARow(_ left: String, _ right: String) -> String { "\"\(left) \(stem(right))\"*" }

    /// Whether the foods with a name as one word and the foods with it as two are the same kind of
    /// food, by their usual energy and macros: a name written two ways, not two names.
    private func alike(_ left: String, _ right: String) -> Bool {
        let found = run([jobs(catalogs, "\"\(stem(left + right))\"*", .sample), jobs(catalogs, inARow(left, right), .sample)])
        guard let one = profile(found[0].map(\.food)), let two = profile(found[1].map(\.food)) else { return false }
        return one.distance(to: two) < 2.25
    }

    /// How labels write two words they also write as one ("red bull", "pop corn"). Nil when fewer
    /// than 20 labels have the one word ("green tea" beside 15 of "greentea"), unless it was typed
    /// as one (`asOne`), next to no label has it and labels write the two: "organicvalley" is
    /// Organic Valley. A word a few labels have ("buttercup", on 19) is left as it is: it may be
    /// a food of its own, with too few foods to tell. Remembered for the launch.
    func compound(_ left: String, _ right: String, asOne: Bool = false) -> Compound? {
        let key = "\(left) \(right)\(asOne ? " " : "")"
        if let known = compounds.withLock({ $0[key] }) { return known }
        let few = Self.fewLabels
        var found: Compound?
        let joined = foods(named: left + right)
        // A word only the generic catalog has is still searched for beside the two labels
        // write: "water chestnuts" are USDA's "Waterchestnuts".
        let generic =
            !asOne && joined > 0 && joined < few
            && catalogs.first(where: { $0.kind == .generic })?.terms(
                "SELECT term, foods FROM terms WHERE term IN (?, ?)", [.text(left + right), .text(stem(left + right))]
            ).isEmpty == false
        if joined >= few || (asOne && joined < 4) || generic {
            let apart = catalogs.reduce(0) { $0 + $1.count(inARow(left, right), cap: 20_000) }
            if joined >= few {
                found = Compound(joined: joined > apart, same: apart >= few && alike(left, right))
            } else if apart >= few {
                found = Compound(joined: false, same: true, known: joined > 0)
            }
        }
        compounds.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[key] = .some(found)
        }
        return found
    }

    /// Where a word typed as one divides into two that labels also write for the same food
    /// ("redbull", "hotdogs", "popcorn"), each half a word of 20 foods or more. The last word of a
    /// search has to be one labels have (`whole`): unknown, it may only be half typed.
    func halves(of word: String, whole: Bool) -> (left: String, right: String, compound: Compound)? {
        let units = Array(word.utf16)
        guard units.count >= 6 else { return nil }
        let splits = (3...(units.count - 3)).map { i in
            (String(decoding: units[..<i], as: UTF16.self), String(decoding: units[i...], as: UTF16.self))
        }
        var parts: [String] = []
        for (left, right) in splits { for part in [left, right] where !parts.contains(part) { parts.append(part) } }
        let marks = Array(repeating: "?", count: parts.count).joined(separator: ",")
        let known = count("SELECT term, foods FROM terms WHERE term IN (\(marks))", parts.map(SQLValue.text)).values
        // The halves in the most foods first, and no more than three ways of dividing the word.
        let likely = splits.map { ($0.0, $0.1, min(known[$0.0] ?? 0, known[$0.1] ?? 0)) }.filter { $0.2 >= Self.fewLabels }
            .sorted { $0.2 > $1.2 }.prefix(3)
        for (left, right, _) in likely {
            if let compound = compound(left, right, asOne: whole), compound.same { return (left, right, compound) }
        }
        return nil
    }

    /// The search with its names written the way most labels write them, and the other way kept to
    /// search for as well: "redbull energy" becomes "red bull energy", also finding Redbull, and "pop
    /// corn" becomes "popcorn", also finding Pop Corn. A word typed as one is only read as two when
    /// labels write both for the same kind of food; two typed apart always find the one word too
    /// ("butter ball turkey" finds Butterball's). Only the words that name the food are read, not
    /// its amount, and the one word has to be a whole word of the catalogs': "pea che" is on its
    /// way to pea cheese as much as to peaches. A name a model gave isn't being typed (`typing`
    /// false), so its last word is whole too.
    /// A search with a way of cooking said in two words as the one the catalogs use, and without
    /// where the food was cooked: "pan seared salmon" is "seared salmon" and "slow cooker
    /// chicken" "chicken". Nil where it says neither, or names nothing beside it.
    func plainlyCooked(_ query: String) -> String? {
        let scalars = plainScalars(query)
        let tokens = scanTokens(scalars)
        for way in cookingWays where tokens.count > way.said.count {
            guard
                let at = tokens.indices.first(where: { i in
                    i + way.said.count <= tokens.count && way.said.indices.allSatisfy { tokens[i + $0].word == way.said[$0] }
                })
            else { continue }
            let rest = makeString(scalars[tokens[at + way.said.count - 1].end...])
            let text = (makeString(scalars[..<tokens[at].start]) + way.means.joined(separator: " ") + rest).trimmingCharacters(in: .whitespaces)
            // A second way in the same search: "oven baked chicken with pan fried potatoes".
            return plainlyCooked(text) ?? text
        }
        return nil
    }

    /// Whether the whole of a search is what's said for something else, here or anywhere.
    private func shortened(_ typed: String) -> Bool {
        let said = tokens(typed)
        return regionalName(said, in: region) != nil || shortNames[said.joined(separator: " ")] != nil
    }

    func respell(_ query: String, typing: Bool = true, meant: [String: String] = [:]) -> Respelt {
        let scalars = plainScalars(query)
        let tokens = scanTokens(scalars)
        let names = Set(searchedWords(readQuery(query).words))
        let named = { (i: Int) in
            names.contains(tokens[i].word) && !stopWords.contains(tokens[i].word) && !tokens[i].word.unicodeScalars.contains(where: isDigit)
        }
        // A percentage in words is the number labels and USDA write: "2 percent milk" is 2% milk.
        if let written = percentWritten(query) {
            var read = respell(written, typing: typing, meant: meant)
            read.typed = read.typed ?? query
            return read
        }
        // A common misspelling is the word meant, whatever labels are misspelt the same way:
        // "brocolli", "protien", "smoothy".
        if let at = tokens.indices.first(where: { named($0) && Misspellings.meant[tokens[$0].word] != nil }),
            let word = Misspellings.meant[tokens[at].word]
        {
            return respell(makeString(scalars[..<tokens[at].start]) + word + makeString(scalars[tokens[at].end...]), typing: typing, meant: meant)
        }
        // A search one typo from an everyday food is that food, where USDA has no such word
        // and no brand people scan is called it: "french fires" is french fries, whatever
        // labels have "fire" in their names, and "refried bens" refried beans.
        let namedTokens = tokens.indices.filter(named)
        // Not a word with a meaning of its own, typed alone: a "cuke" is a cucumber, not a Coke.
        let own =
            namedTokens.count == 1 && tokens.count == 1
            && (describingName(tokens[0].word) != nil || shortNames[tokens[0].word] != nil || aloneName(tokens[0].word) != nil
                || isRegionalName(tokens[0].word, in: region))
        if typing, !own, let (at, word) = EverydayPhrases.misspelt(namedTokens.map { tokens[$0].word }) {
            let token = tokens[namedTokens[at]]
            // After other words of the food it's a word, known only as written: the "saue" of
            // "hot saue" isn't sauerkraut begun, nor the "fires" of "french fires" a brand
            // called Fire. Alone, it may be a name begun.
            let known =
                namedTokens.count == 1
                ? isName(token.word, whole: token.end < scalars.count)
                : catalogs.contains { catalog in
                    catalog.kind == .generic
                        ? !catalog.terms("SELECT term, foods FROM terms WHERE term = ?", [.text(token.word)]).isEmpty
                        : catalog.isScanned("{brand}: \"\(token.word)\"", atLeast: 1.5)
                }
            if !known { return respell(makeString(scalars[..<token.start]) + word + makeString(scalars[token.end...]), typing: typing, meant: meant) }
        }
        // A label's word for how a food was grown or made, typed first, says nothing of which
        // food it is: "organic ranch" is read as "ranch" is, and "homemade mac and cheese" as
        // mac and cheese. The word stays in the search for the foods that say it.
        if tokens.count > 1, labelWords.contains(stem(tokens[0].word)), named(1) || tokens.count > 2 {
            let label = makeString(scalars[tokens[0].start..<tokens[0].end])
            var read = respell(makeString(scalars[tokens[1].start...]), typing: typing, meant: meant)
            read.text = "\(label) \(read.text)"
            if read.typed != nil { read.typed = query }
            return read
        }
        // What people type for a food instead of its name: "pb&j". And the one it's on its way
        // to, where the words begin an everyday name: "mac and chees".
        let short = tokens.map(\.word)
        let begun = typing && tokens.last?.end == scalars.count && EverydayPhrases.isBegun(short)
        // First what the words mean where the phone is: in Britain chips are fries.
        if let name = regionalName(short, in: region) ?? shortNames[short.joined(separator: " ")] ?? (begun ? shortNameBegun(short) : nil) {
            var read = respell(name, typing: false)
            read.typed = read.typed ?? query
            return read
        }
        // A name being typed as one word is read as its words: "hotd" is on its way to a hot dog.
        if typing, let last = tokens.last, last.end == scalars.count, named(tokens.count - 1), let apart = EverydayPhrases.apart(last.word) {
            return respell(makeString(scalars[..<last.start]) + apart, typing: typing, meant: meant)
        }
        // One letter after a food's or a brand's first words is enough to say which: "chicken b"
        // is searched as chicken breast, where the letter alone would be left out.
        if typing, let last = tokens.last, last.end == scalars.count, length(last.word) == 1, !isNumber(last.word), tokens.count > 1,
            scalars[last.start - 1] == " ",
            let whole = EverydayPhrases.completing(tokens.dropLast().indices.filter(named).map { tokens[$0].word } + [last.word])
        {
            var read = respell(makeString(scalars[..<last.start]) + whole, typing: false)
            read.typed = read.typed ?? query
            return read
        }
        // The word still being typed, as the food it's most likely on its way to: it's read by
        // that food's other names too, so "hot do" already finds frankfurters.
        var likely: String?
        if typing, let last = tokens.last, last.end == scalars.count, named(tokens.count - 1) {
            likely = EverydayPhrases.likely(tokens.indices.filter(named).map { tokens[$0].word })
        }
        var respelt = Respelt(text: "")
        var text: [Unicode.Scalar] = []
        var copied = 0
        func write(_ words: String, over range: Range<Int>) {
            text += scalars[copied..<range.lowerBound]
            text += Array(words.unicodeScalars)
            copied = range.upperBound
        }
        func also(_ form: String, for words: [String]) {
            for word in words where respelt.also[word]?.contains(form) != true { respelt.also[word, default: []].append(form) }
            respelt.forms.insert(form)
        }
        // An everyday name the catalogs file under another: "hot dogs" also find frankfurters.
        // `read` is the words as they're taken, where the last is still being typed.
        func everyday(_ typed: [String], read: [String]? = nil) {
            let read = read ?? typed
            for name in everydayNames where typed.count >= name.said.count && read.prefix(name.said.count).map(stem) == name.said {
                if writtenNames.contains(name.said[0]), typed.prefix(name.said.count).map(stem) != name.said { continue }
                for (at, catalog) in name.means { also(catalog, for: [typed[at]]) }
            }
        }
        // Typed alone, "ranch" is the dressing and "spaghetti" is also USDA's pasta. A word still
        // being typed is, from four letters.
        // For a food a model named, apart from how much of it: a "side salad" is a salad.
        let only = tokens.indices.filter { named($0) && (typing || !countWords.contains(tokens[$0].word)) }
        if only.count == 1 {
            let alone = tokens[only[0]]
            // A word with a meaning of its own is that, whatever it could be a typo of:
            // "mezcal" isn't Mezcla.
            // Nor is the start of one, where no everyday food starts the same: "mezca".
            let begun = typing && likely == nil && alone.end == scalars.count ? aloneBegun(alone.word) : nil
            let word =
                aloneName(alone.word) != nil
                ? alone.word : begun ?? meant[alone.word] ?? likely.flatMap { length(alone.word) >= 4 ? $0 : nil } ?? alone.word
            // Or it only describes one, and is the everyday food it most often starts: "skim",
            // and "fren" on its way to french. With nothing else typed, and as typed: a
            // letter after it may start a brand ("swiss m"), and "snapp" isn't snap misspelt.
            let described =
                tokens.count == 1
                ? describingName(alone.word) ?? likely.flatMap { length(alone.word) >= 4 ? describingName($0) : nil } : nil
            // First what the word means where the phone is, whole or on its way: in Britain
            // "2 biscuits" are cookies.
            if let meant = regionalName([word], in: region) ?? aloneName(word) ?? described {
                write(meant, over: alone.start..<alone.end)
                text += scalars[copied...]
                // Read as any search of those words is: a bell pepper is USDA's sweet pepper,
                // flax seeds its flaxseed.
                var read = respell(makeString(text[...]), typing: false)
                read.typed = query
                return read
            }
            if let filed = aloneFiled[stem(word)] { also(filed, for: [alone.word]) }
        } else {
            // With only whether it's cooked said of it, the word is as good as alone: "cooked
            // spaghetti" is the pasta too, not the one kind USDA lists as spaghetti. A way of
            // cooking names a dish: baked ziti.
            let foods = only.filter { !["cooked", "boiled", "uncooked", "raw", "dry"].contains(tokens[$0].word) }
            if foods.count == 1, let filed = aloneFiled[stem(tokens[foods[0]].word)] { also(filed, for: [tokens[foods[0]].word]) }
        }
        // A word read as another, half typed or misspelt, is read by that word's own other wordings
        // and spellings: "ketchu" and "ketchep" are on their way to catsup too, "milkshak" to
        // "milk shake".
        var others = meant
        if let likely, let last = tokens.last, others[last.word] == nil { others[last.word] = likely }
        for (typed, word) in others.sorted(by: { $0.key < $1.key }) {
            if typedAlternatives.contains(word) { for form in forms(word) where form != stem(word) { also(form, for: [typed]) } }
            if let (left, right, _) = halves(of: word, whole: true) { also("\(left) \(stem(right))", for: [typed]) }
        }
        if let likely, let last = tokens.last {
            let before = tokens.count - 2
            if before >= 0, named(before), length(tokens[before].word) > 2, let compound = compound(tokens[before].word, likely),
                compound.joined || compound.same
            {
                also(stem(tokens[before].word + likely), for: [tokens[before].word, last.word])
            }
        }
        var i = 0
        while i < tokens.count {
            defer { i += 1 }
            guard named(i) else { continue }
            let word = tokens[i].word
            let run = (i..<tokens.count).prefix(while: named).map { tokens[$0].word }
            var read = run.map { meant[$0] ?? $0 }
            if let likely, i + run.count == tokens.count { read[read.count - 1] = likely }
            everyday(run, read: read)
            if let (left, right, compound) = halves(of: word, whole: !typing || i < tokens.count - 1) {
                if compound.joined {
                    also("\(left) \(stem(right))", for: [word])
                } else {
                    write("\(left) \(right)", over: tokens[i].start..<tokens[i].end)
                    // "Hotdogs" are frankfurters as "hot dogs" are.
                    everyday([left, right])
                    if compound.known { also(stem(word), for: [left, right]) }
                    continue
                }
            }
            // "Mc" typed apart starts a name the catalogs write as one word, however far the
            // rest is typed: "mc flurry", "mc donalds", "mc d".
            if word == "mc", i + 1 < tokens.count, named(i + 1), !isNumber(tokens[i + 1].word),
                scalars[tokens[i].end..<tokens[i + 1].start].allSatisfy(isSpace)
            {
                let next = tokens[i + 1].word
                write(word + next, over: tokens[i].start..<tokens[i + 1].end)
                also("\(word) \(stem(next))", for: [word + next])
                i += 1
                continue
            }
            // Halves of three letters or more, as a word typed as one divides: "pea ch" isn't peach.
            guard i + 1 < tokens.count, named(i + 1), length(word) > 2 else { continue }
            let typed = tokens[i + 1].word
            // A misspelt second word joins as the word it meant: "flax sedes" is flaxseed too.
            let next = meant[typed] ?? typed
            guard length(next) > 2, scalars[tokens[i].end..<tokens[i + 1].start].allSatisfy({ isSpace($0) || $0 == "-" }) else { continue }
            guard let compound = compound(word, next) else { continue }
            if next != typed {
                // And apart as well as joined: "crisp bead" is Wasa's "Crisp Bread" as much as a crispbread.
                also(stem(word + next), for: [word, typed])
                also(stem(next), for: [typed])
            } else if compound.joined && compound.same {
                write(word + next, over: tokens[i].start..<tokens[i + 1].end)
                also("\(word) \(stem(next))", for: [word + next])
                i += 1
            } else {
                also(stem(word + next), for: [word, next])
            }
        }
        text += scalars[copied...]
        respelt.text = makeString(text[...])
        return respelt
    }

    /// Whether words name a brand: they are in the brand of at least 20 packaged foods and half
    /// again as many brands as names ("trader joes", "kirkland", "great value"). Brands that name
    /// their products ("oreo", "cheerios", "coke") are searched as names.
    private func isBrand(_ words: ArraySlice<String>, _ catalog: Catalog, _ fixes: Fixes) -> Bool {
        let expression = words.map { searchTerm($0, fixes) }.joined(separator: " AND ")
        if let remembered = brandish.withLock({ $0[expression] }) { return remembered }
        // Counting stops at 2,000: past that, a word is too common in names to be only a brand.
        let inBrands = catalog.count("{brand}: (\(expression))")
        let brand = inBrands >= 20 && Double(inBrands) >= 1.5 * Double(catalog.count("{name}: (\(expression))"))
        brandish.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[expression] = brand
        }
        return brand
    }

    /// A search with "2 percent" or "one percent" in it, written "2%" and "1%"; nil without one.
    private func percentWritten(_ query: String) -> String? {
        let parts = query.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let at = parts.firstIndex(where: { $0.lowercased() == "percent" }), at > 0 else { return nil }
        let numbers = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5"]
        let before = parts[at - 1].lowercased()
        guard let number = numbers[before] ?? (isNumber(before) ? before : nil) else { return nil }
        return (parts[..<(at - 1)] + ["\(number)%"] + parts[(at + 1)...]).joined(separator: " ")
    }

    /// Whether the words together name a food far more often than the one at `brand` is the
    /// brand of a food the others name: "great northern beans" aren't Great Value's, "general tso
    /// chicken" isn't General Mills', "little smokies" aren't Little Debbie's and a "garlic clove"
    /// isn't Clover Valley's. Five foods at least are named by them all, and twice as many as
    /// the brand has; a brand's own (Mission's tortillas, Président's brie) have several times
    /// more than are named so.
    private func isNamed(_ words: [String], without brand: Int, _ catalog: Catalog, _ fixes: Fixes) -> Bool {
        let all = words.map { searchTerm($0, fixes) }
        let key = "named \(brand) \(all.joined(separator: " "))"
        if let remembered = brandish.withLock({ $0[key] }) { return remembered }
        let rest = all.indices.filter { $0 != brand }.map { all[$0] }.joined(separator: " AND ")
        let foods = catalog.count("{name}: (\(all.joined(separator: " AND ")))", cap: 300)
        let named = foods >= 5 && foods >= 2 * catalog.count("({brand}: (\(all[brand]))) AND ({name}: (\(rest)))", cap: 100)
        brandish.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[key] = named
        }
        return named
    }

    /// The chains and brands the generic catalog writes first in capitals ("PAPA JOHN'S 14" Pepperoni
    /// Pizza", "LITTLE CAESARS …", "McDONALD'S, BIG MAC"), in plain words. A brand written with more
    /// than one run is the words its runs share: KRAFT, not "KRAFT FREE" from KRAFT FREE Singles.
    var chains: [[String]] {
        chainNames.withLock { cached in
            if let cached { return cached }
            var order: [String] = []
            var shared: [String: [String]] = [:]
            for catalog in catalogs where catalog.kind == .generic {
                for name in catalog.names() {
                    let run = brandWords(name: name, brand: "")
                    guard let first = run.first else { continue }
                    if let known = shared[first] {
                        shared[first] = zip(known, run).prefix { $0 == $1 }.map(\.0)
                    } else {
                        order.append(first)
                        shared[first] = run
                    }
                }
            }
            let found = order.compactMap { shared[$0] }
            cached = found
            return found
        }
    }

    /// Whether words name a chain or brand the generic catalog writes first ("little caesars", "papa
    /// johns", "wendys"), unless packaged foods use them in names far more often than as a brand.
    /// Only the search's last word may be the start of the chain's, `halfTyped`, and not when it is
    /// a word of its own: "mcdon" is on its way to McDonald's, but "apple" isn't Applebee's, before
    /// "cinnamon oats" or after.
    private func isChain(_ words: ArraySlice<String>, _ catalog: Catalog?, _ fixes: Fixes, halfTyped: Bool) -> Bool {
        let forms = words.map { searchForms($0) + (fixes[$0] ?? []) }
        let started =
            halfTyped
            && words.last.map { word in
                count("SELECT term, foods FROM terms WHERE term IN (?, ?)", [.text(word), .text(stem(word))]).total < 20
            } == true
        guard
            let chain = chains.first(where: { chain in
                chain.count == forms.count
                    && zip(chain, forms).enumerated().allSatisfy { i, pair in
                        pair.1.contains { started && i == forms.count - 1 ? starts(pair.0, $0) : same(pair.0, $0) }
                    }
            })
        else { return false }
        guard let catalog else { return true }
        // Counted as the chain's own words in a row, so "chick fil" isn't every chicken fillet nor
        // "domino" every German Dominostein.
        let phrase = "\"\(chain.joined(separator: " "))\""
        let key = "chain \(phrase)"
        if let remembered = brandish.withLock({ $0[key] }) { return remembered }
        let inNames = catalog.count("{name}: \(phrase)")
        let brand = inNames < 20 || 1.5 * Double(catalog.count("{brand}: \(phrase)")) >= Double(inNames)
        brandish.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[key] = brand
        }
        return brand
    }

    /// Whether the generic catalog names a food by exactly these words, as its own name or
    /// another it keeps for it, and they aren't one of the most scanned brands: "Mai Tai", "Tom
    /// Collins", not Cape Cod's chips.
    private func isPlainName(_ words: ArraySlice<String>) -> Bool {
        let said = words.joined(separator: " ")
        let key = "plain \(said)"
        if let remembered = brandish.withLock({ $0[key] }) { return remembered }
        let stems = words.map(stem)
        // In any order: USDA writes "Thyme, fresh" for fresh thyme.
        let sorted = stems.sorted()
        let popular = PopularBrands.names.contains { FoodDatabase.words($0).map(stem) == stems }
        // By each word rather than as a phrase: the words searched leave out the "with" of
        // "Pasta with meat sauce".
        let each = words.map { "\"\($0)\"" }.joined(separator: " AND ")
        let named =
            !popular
            && catalogs.contains { catalog in
                catalog.kind == .generic
                    && catalog.match("{name also}: (\(each))", limit: 40).contains { hit in
                        FoodDatabase.words(hit.entry.food.name).map(stem).sorted() == sorted || hit.entry.also.contains { $0.text.titled == stems }
                    }
            }
        brandish.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[key] = named
        }
        return named
    }

    /// The words at the start or end of a search that name a brand, the most words first: "trader
    /// joes" in "trader joes mini wheats" or "mini wheats trader joes", and "little caesars" before
    /// "little". A search of two or three words that is a brand as a whole ("trader joes", "great
    /// value") is that brand, not "trader" and a food called "joes"; a brand of one word alone
    /// ("kirkland", or "pop" on its way to Pop-Tarts) is searched as any other.
    private func findBrand(_ words: [String], _ fixes: Fixes, typed: String = "") -> Range<Int>? {
        guard words.count > 1 else { return nil }
        let catalog = branded.first
        // A restaurant chain is the brand, whatever the catalogs have of it, and no more of the
        // search: the second "taco" of "taco bell taco" is the food.
        if let chain = Chains.chain(in: words, typed: typed) { return chain.span }
        for size in stride(from: min(words.count, 3), through: 1, by: -1) {
            for start in Set([0, words.count - size]).sorted() {
                let span = words[start..<(start + size)]
                // A letter on its own is a size or a variety ("k cup"), whatever brands start with it.
                guard span.contains(where: { length($0) > 1 }) else { continue }
                // Nor are two letters at the end a brand begun: the "do" of "hot do" isn't Doritos.
                if size == 1, start + size == words.count, length(words[start]) < 3 { continue }
                if let catalog, isBrand(span, catalog, fixes) {
                    if size == 1, isNamed(words, without: start, catalog, fixes) { continue }
                    // Nor is any of a search a brand where USDA names a food by exactly its
                    // words: a "mai tai" is the drink, whatever mixes are listed under it, and
                    // "eggs benedict" the dish, whoever sells eggs as Benedict.
                    if isPlainName(words.filter { !labelWords.contains(stem($0)) }[...]) { continue }
                    return start..<(start + size)
                }
                if isChain(span, catalog, fixes, halfTyped: start + size == words.count) { return start..<(start + size) }
            }
        }
        return nil
    }

    /// A typed search, best match first. Each word is a stemmed prefix and a word the catalogs
    /// barely know is also searched as what it probably meant. A search that names a brand also
    /// finds the brand's foods that share a word with the rest ("Shredded Bite Size Wheats" for
    /// "trader joes mini wheats") and the foods the rest names under any brand, and a brand alone
    /// finds all of its foods ("trader joes"); a longer search that finds little also finds foods
    /// missing one of its words; and a search that finds nothing falls back to the word that names
    /// the food. The person's own foods in `known` rank higher, and packaged foods people scan more
    /// rank higher among themselves.
    /// The words of a search the catalogs barely know that can each have meant only one other
    /// word, by that word: "ketchep" is ketchup and "spagheti" spaghetti. The search still looks
    /// for the word as typed, which may be a small brand's; this is for reading the word's
    /// everyday names and spellings as if it had been typed right. Not a word with two readings
    /// ("gali" is gala or garlic), one that is only cut short, or one the generic catalog has.
    func typos(in typed: String) -> [String: String] {
        let scalars = plainScalars(typed)
        let tokens = scanTokens(scalars)
        let searched = searchedWords(readQuery(typed).words)
        // An everyday food's whole name has no typo in it: raita isn't ratatouille.
        guard !EverydayPhrases.isName(searched) else { return [:] }
        let names = Set(searched)
        var meant: [String: String] = [:]
        for (i, token) in tokens.enumerated() where names.contains(token.word) && length(token.word) >= 4 && !stopWords.contains(token.word) {
            let spelling = spell(token.word, whole: i < tokens.count - 1 || token.end < scalars.count)
            guard spelling.doubted else { continue }
            // A name the catalogs know, or the start of one, is no typo to read by another
            // word's names: "noos" may be noodles, and is as far as Noosa is typed.
            guard !isName(token.word, whole: i < tokens.count - 1 || token.end < scalars.count) else { continue }
            // Of two readings, the one that makes one word with the word before it: after
            // "flax", "sends" is seeds.
            var readings = spelling.fixes
            if readings.count > 1, i > 0 { readings = readings.filter { !$0.contains(" ") && compound(tokens[i - 1].word, $0) != nil } }
            guard readings.count == 1, let fix = readings.first, !fix.contains(" "), !token.word.hasPrefix(fix),
                catalogs.first(where: { $0.kind == .generic })?.terms("SELECT term, foods FROM terms WHERE term = ?", [.text(stem(token.word))])
                    .isEmpty != false
            else { continue }
            meant[token.word] = fix
        }
        return meant
    }

    func searchCatalog(_ typed: String, known: [String: Double]) -> CatalogSearch {
        let search = searchCatalog(typed, known: known, out: nil)
        // A search in Spanish, or a food's Hindi name, is searched as it reads in English,
        // where the catalog doesn't name a food by the words as typed ("Pollo asado") and a
        // plain food has every word of the English: "pollo" is chicken and "frijoles negros"
        // black beans. Its first three, then the foods found as typed, which is where the
        // labels that say "Frijoles Negros" are, then the rest. Whatever brand the words
        // were taken for: "chuleta de puerco" is a pork chop, not Pavo's.
        if let english = inEnglish(typed), !isPlainName(searchedWords(words(typed))[...]) {
            let read = searchCatalog(english, known: known)
            if let first = read.ranked.first, first.name >= 1, !FoodText(first.food).branded {
                var both = read
                let asTyped = Self.joined(Array(read.ranked.prefix(3)), search.ranked.filter { $0.name >= 1 })
                both.ranked = Self.joined(asTyped, Self.joined(read.ranked, search.ranked))
                both.elsewhere.formUnion(search.elsewhere)
                both.typed = read.typed ?? typed
                return both
            }
        }
        // A way of cooking said in two words is searched as the catalogs' one, where no brand
        // is named and a plain food has every word left: "pan seared salmon" is the salmon,
        // "air fried chicken" baked chicken. Its first three, then the foods with every word
        // as typed, which is where a label called "Air Fried Chicken" is, then the rest of
        // each. A brand's search is left as typed.
        if search.brand.isEmpty, let plainly = plainlyCooked(typed) {
            let plain = searchCatalog(plainly, known: known)
            if let first = plain.ranked.first, first.name >= 1, !FoodText(first.food).branded {
                var both = plain
                let asTyped = Self.joined(Array(plain.ranked.prefix(3)), search.ranked.filter { $0.name >= 1 })
                both.ranked = Self.joined(asTyped, Self.joined(plain.ranked, search.ranked))
                both.elsewhere.formUnion(search.elsewhere)
                both.typed = plain.typed ?? typed
                return both
            }
        }
        if let apart = searchApart(typed, search, known: known) { return apart }
        if let with = searchWith(search, known: known) { return with }
        // A restaurant chain typed with a food: where no food found is the chain's and has the
        // other words, it's that food as a restaurant serves it. "Five guys fries" are fries
        // from fast food and "kfc mashed potatoes" mashed potatoes from one, with what the
        // words found after them.
        let searched = searchedWords(readQuery(search.text).words)
        guard let chain = Chains.chain(in: searched, typed: typed) else { return search }
        // Its own item, or a plain food the catalog keeps the chain's name for: a Dairy Queen
        // Blizzard is the soft serve blended with candy.
        let theirs = search.ranked.prefix(5).contains(where: \.mine)
        if theirs { return search }
        let food = searched.indices.filter { !chain.span.contains($0) }.map { searched[$0] }.joined(separator: " ")
        let plain = searchCatalog(food, known: known, out: chain.place)
        // A plain food with every word left, as typed: a Subway "footlong" isn't oolong tea
        // misspelt, nor a Wendy's Baconator the crisps flavoured like one.
        guard let first = plain.ranked.first, first.name >= 1, plain.fixes.isEmpty, !FoodText(first.food).branded else { return search }
        // Those foods first, then the ones all the words found. The reading stays the first
        // search's, which the person's own foods are found by.
        var both = search
        both.ranked = Self.joined(plain.ranked, search.ranked)
        both.elsewhere.formUnion(plain.elsewhere)
        return both
    }

    /// The foods typed together with "and", "&" or "+", apart: the burger and the fries of
    /// "burger and fries", and the three of "eggs, bacon and toast". Nil for one food or more
    /// than three.
    private static func foodsTyped(_ typed: String) -> [String]? {
        var foods: [[Substring]] = [[]]
        var joined = false
        for word in typed.lowercased().split(separator: " ") {
            if word == "and" || word == "&" || word == "+" {
                foods.append([])
                joined = true
            } else if word.hasSuffix(",") {
                foods[foods.count - 1].append(word.dropLast())
                foods.append([])
            } else {
                foods[foods.count - 1].append(word)
            }
        }
        // "Eggs, bacon, and toast" has nothing between its last comma and its "and".
        let names = foods.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
        // What follows a "with" is what one food comes with: "coffee with cream and sugar".
        guard joined, names.count == 2 || names.count == 3, !foods.joined().contains("with") else { return nil }
        return names.allSatisfy { !searchedWords(words($0)).isEmpty } ? names : nil
    }

    /// One of the foods typed together, as it's searched for alone: with salt, pepper is the
    /// black pepper in the other shaker; with chips, fish is fried and the chips are fries;
    /// with waffles, chicken is fried.
    private static func alone(_ food: String, among foods: [String]) -> String {
        // By its own words, and the others by their last: organic fish is fish, and battered
        // fish is still fish to the chips.
        let named = foodWords(food).map(stem)
        let others = foods.compactMap { foodWords($0).last.map(stem) }
        return beside.first { [stem($0.food)] == named && others.contains(stem($0.with)) }?.means ?? food
    }

    private static let beside: [(food: String, with: String, means: String)] = [
        ("pepper", "salt", "black pepper"), ("fish", "chips", "fried fish"), ("chips", "fish", "french fries"),
        ("chicken", "waffles", "fried chicken"),
        // With salsa, guacamole or queso, chips are tortilla chips, wherever chips are fries.
        ("chips", "salsa", "tortilla chips"), ("chips", "guacamole", "tortilla chips"), ("chips", "guac", "tortilla chips"),
        ("chips", "queso", "tortilla chips"),
    ]

    /// A flavour is the food of that flavour: the foods found whose names join the two as
    /// typed ("Cookies & Cream Ice Cream") before a plain food that only has both words
    /// ("Cookies, chocolate cream covered biscuit sticks"). Nil where none does.
    private static func flavoured(_ ranked: [Ranked], _ flavour: Flavour) -> [Ranked]? {
        let joins = { (found: Ranked) in
            let text = FoodText(found.food)
            return text.said.indices.dropLast().contains { i in
                same(text.said[i], flavour.before) && same(text.said[i + 1], flavour.after) && text.runs[i] != text.runs[i + 1]
                    && text.joint.contains(text.runs[i + 1])
            }
        }
        // The first food found may be one already, whatever else was said of it.
        if let first = ranked.first, joins(first) { return ranked }
        let named = ranked.filter { $0.name >= 1 && joins($0) }
        return named.isEmpty ? nil : joined(named, ranked)
    }

    /// A food's words as they're read: each as corrected, without the ones that only say how
    /// it comes or how many ("organic", "homemade", "2").
    private static func foodWords(_ text: String, fixes: Fixes = [:]) -> [String] {
        let read = searchedWords(words(text)).map { word in fixes[word].flatMap { $0.count == 1 && !$0[0].contains(" ") ? $0[0] : nil } ?? word }
        let named = read.filter { !saysHow($0) && !isNumber($0) }
        return named.isEmpty ? read : named
    }

    /// What the foods typed or named together are, by their words and the foods found.
    private enum Together {
        /// One food, as found: an everyday name ("mac and cheese", whole or with its last word
        /// still being typed), one the catalog names by all the words ("Sweet and sour pork")
        /// or calls so, or a dish of the last word with all of them (a "Ham sandwich on
        /// white, with cheese" for a ham and cheese sandwich).
        case one
        /// One food, these first: a flavour's foods ("cookies and cream"), or the plain food
        /// named as the foods together ("Beans and rice"), where it's among the first three.
        case first([Ranked])
        /// Foods of their own.
        case apart
    }

    /// Everyday pairs that are two foods on a plate as much as one dish, by their stems.
    private static let platePairs: Set<String> = ["chicken rice", "rice bean"]

    /// How the foods typed or named beside each other are said to be cooked: dry heat for the
    /// "grilled chicken" of "grilled chicken and rice".
    private static func waysSaid(_ foods: [String]) -> Set<Heat> {
        Set(foods.flatMap { words($0).compactMap { heats[stem($0)] } })
    }

    /// `parts` are each food's words as read (see `foodWords`), `found` what the words found
    /// together. `cooked` is how any was said to be cooked: then a plain food named as the
    /// foods together is them only if it's cooked that kind of way, and the catalog's name
    /// for the two isn't enough. Grilled chicken and rice aren't the survey's mixed dish of
    /// chicken and rice, nor its fried rice with chicken.
    /// `names` is false for an everyday name no plain food answers, which is then its foods.
    private func together(_ parts: [[String]], _ found: [Ranked], cooked: Set<Heat> = [], names: Bool = true) -> Together {
        let all = Array(parts.joined())
        let stems = all.map(stem)
        if let flavour = flavours.first(where: { stems.starts(with: $0.stems) }) {
            return Self.flavoured(found, flavour).map { .first($0) } ?? .one
        }
        let said = Array(parts.joined(separator: ["and"]))
        // Not, said with how one was cooked, a pair that is two foods on a plate as much as a
        // dish: the grilled chicken and the rice.
        let name = names && (EverydayPhrases.isName(all) || EverydayPhrases.isName(said) || EverydayPhrases.isBegun(said))
        if name, cooked.isEmpty || !Self.platePairs.contains(stems.joined(separator: " ")) { return .one }
        if cooked.isEmpty, isPlainName(all[...]) { return .one }
        guard let first = found.first else { return .apart }
        if first.called || first.calling { return .one }
        let named = found.prefix(3).firstIndex { found in
            let text = FoodText(found.food)
            return !text.branded && isJoint(text, parts) && cooked.isSubset(of: text.cooking.kinds)
        }
        if let named { return named == 0 ? .one : .first(Self.joined([found[named]], found)) }
        // The dish the last word names, where the first food found is one with each food and
        // every word of the last: a ham sandwich with cheese for a cheese sandwich, not fried
        // rice for brown rice.
        if let last = parts.last, last.count > 1, let kind = last.last.map(stem) {
            let text = FoodText(first.food)
            let head = text.said.indices.last { text.runs[$0] == text.runs[0] }.map { text.said[$0] }
            // Its last word may still be being typed: "ham and cheese sandw".
            let named = head.map { same($0, kind) || starts($0, kind) } == true
            if !text.branded, named, hasEach(text, parts.dropLast() + last.dropLast().map { [$0] }) { return .one }
        }
        return .apart
    }

    /// Two or three foods typed together that no one food found is ("burger and fries",
    /// "eggs, bacon & toast"): each searched for alone, the first of each, then a label
    /// called exactly the two together, then the rest of each in turn, before what the words
    /// found together. Nil where the words are one food (see `Together`) or a brand's, and
    /// where a part alone is no plain food: "salt and vinegar chips", "surf and turf".
    private func searchApart(_ typed: String, _ search: CatalogSearch, known: [String: Double]) -> CatalogSearch? {
        // As what was typed is read, where the whole of it is said for something else: avocado
        // toast is avocado and toast, and in Britain cheese and biscuits are cheese and
        // crackers. Else as typed.
        let reworded = search.typed != nil && shortened(typed) ? Self.foodsTyped(search.text) : nil
        guard search.brand.isEmpty, let foods = reworded ?? Self.foodsTyped(typed) else { return nil }
        let first = { (ranked: [Ranked]) in
            var named = search
            named.ranked = ranked
            return named
        }
        // By the words as typed, then by each food as it's read alone: a typo corrected, a
        // short name written out.
        let typedParts = foods.map { Self.foodWords($0) }
        let cooked = Self.waysSaid(foods)
        // An everyday dish said with how it's cooked is the dish, found by its name: baked
        // mac and cheese is mac and cheese. One no plain food answers is its foods: fish and
        // chips are fried fish and fries, where the catalogs have only labels called so.
        let dish = Array(typedParts.joined(separator: ["and"]))
        var names = true
        if EverydayPhrases.isName(dish), cooked.isEmpty || !Self.platePairs.contains(typedParts.joined().map(stem).joined(separator: " ")) {
            let named = cooked.isEmpty ? search : searchCatalog(dish.joined(separator: " "), known: known, out: nil)
            if let top = named.ranked.first, top.name >= 1, !FoodText(top.food).branded {
                guard !cooked.isEmpty else { return nil }
                var both = named
                both.ranked = Self.joined(named.ranked, search.ranked)
                both.elsewhere.formUnion(search.elsewhere)
                both.typed = named.typed ?? typed
                return both
            }
            names = false
        }
        switch together(typedParts, search.ranked, cooked: cooked, names: names) {
        case .one: return nil
        case .first(let ranked): return first(ranked)
        case .apart: break
        }
        let each = foods.map { searchCatalog(Self.alone($0, among: foods), known: known, out: nil) }
        let parts = foods.indices.map { i in
            Self.alone(foods[i], among: foods) == foods[i] ? Self.foodWords(each[i].text, fixes: each[i].fixes) : typedParts[i]
        }
        if parts != typedParts {
            switch together(parts, search.ranked, cooked: cooked, names: names) {
            case .one: return nil
            case .first(let ranked): return first(ranked)
            case .apart: break
            }
        }
        // Each a food of its own, as typed: its first is a plain food or a chain's item with
        // every word of it.
        guard each.allSatisfy({ $0.fixes.isEmpty && $0.ranked.first.map { $0.name >= 1 && $0.food.source == .usda } == true }) else { return nil }
        let sorted = parts.joined().map(stem).sorted()
        let labels = search.ranked.prefix(10).filter { words($0.food.name).map(stem).sorted() == sorted && isJoint(FoodText($0.food), parts) }
        var both = search
        both.ranked = Self.joined(Self.inTurn(each.map(\.ranked), then: Array(labels.prefix(2))), search.ranked)
        for found in each { both.elsewhere.formUnion(found.elsewhere) }
        return both
    }

    /// A food typed with what it comes with is found by its own words: "toast with butter"
    /// is toast, not a label called Toast Butter, and "salad with dressing" a salad, not the
    /// dressing. The food that has what it comes with is first among the ones it is: mashed
    /// potatoes with gravy, a sandwich with turkey. Nil where nothing is typed after "with",
    /// or the first food found is the whole: one the catalog names by all of it or calls so,
    /// as typed or as read (its "Pasta with meat sauce", its "Biscuit with gravy"), however
    /// it's said to be cooked.
    private func searchWith(_ search: CatalogSearch, known: [String: Double]) -> CatalogSearch? {
        // What a food is served on is what it comes with: eggs on toast, chili over rice.
        let typed = servedWith(search.text) ?? search.text
        guard tokens(typed).contains("with") else { return nil }
        let read = seenName(typed)
        guard !read.sides.isEmpty, !isPlainName(Self.foodWords(search.text, fixes: search.fixes)[...]) else { return nil }
        if let first = search.ranked.first, first.called || first.calling { return nil }
        var with = searchCatalog(read.main, known: known, out: nil, sides: read.sides, beside: read.beside)
        // What it comes with is a food to log too: where the food found doesn't have it, each
        // comes right after it, as foods typed together do. Toast, then butter; coffee, then
        // cream and sugar. Not after the tea that is "with milk".
        guard let first = with.ranked.first, with.ranked.count > 1 else { return with }
        let text = FoodText(first.food)
        let without = wordsWithout(text)
        var beside: [Ranked] = []
        for food in Self.besideTyped(typed) {
            // The salad "with assorted vegetables, no dressing" doesn't have the dressing.
            let named = Self.foodWords(food).filter(read.beside.contains)
            let lacks = named.contains { word in without.contains { same($0, stem(word)) } }
            guard !named.isEmpty, lacks || !hasEach(text, [named]) else { continue }
            let found = searchCatalog(food, known: known, out: nil)
            guard found.fixes.isEmpty, let side = found.ranked.first, side.name >= 1, side.food.source == .usda else { continue }
            beside.append(side)
        }
        if !beside.isEmpty { with.ranked = Self.joined([first] + beside, with.ranked) }
        return with
    }

    /// The foods typed after "with", apart: the cream and the sugar of "coffee with cream
    /// and sugar".
    private static func besideTyped(_ text: String) -> [String] {
        var foods: [[Substring]] = []
        for word in text.lowercased().split(separator: " ") {
            if word == "with" || word == "w" {
                if foods.isEmpty { foods.append([]) }
            } else if foods.isEmpty {
                continue
            } else if word == "and" || word == "&" || word == "+" {
                foods.append([])
            } else if foods[foods.count - 1].isEmpty, ["a", "an", "the", "some"].contains(word) {
                // "A bun" is a bun.
                continue
            } else if word.hasSuffix(",") {
                foods[foods.count - 1].append(word.dropLast())
                foods.append([])
            } else {
                foods[foods.count - 1].append(word)
            }
        }
        return foods.map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    }

    /// Lists in turn: the first of each, then `then`, then the second of each and so on, no
    /// food twice.
    private static func inTurn(_ lists: [[Ranked]], then: [Ranked] = []) -> [Ranked] {
        var all = lists.compactMap(\.first) + then
        var seen = Set(all.map(\.food.id))
        for i in 1..<max(2, lists.map(\.count).max() ?? 0) {
            for list in lists where i < list.count && seen.insert(list[i].food.id).inserted { all.append(list[i]) }
        }
        return all
    }

    /// The same for two or three foods a model names as one ("Eggs and bacon"). Where no food
    /// found is both, each food's own candidates in turn, then what the words found
    /// together, and `apart` says none of them is the whole. Not the plain foods only named
    /// after both ("Crackers, cheese", a cracker too), which read as the two to whoever
    /// compares the words. Nil for one food as found, or where the person's own food is
    /// named so.
    private func candidatesTogether(
        _ name: String, _ ranked: [Ranked], personal: [PersonalFood], known: [String: Double]
    ) -> (ranked: [Ranked], apart: Bool)? {
        guard let foods = Self.foodsTyped(name) else { return nil }
        if let first = ranked.first, known[first.food.id] != nil, first.name >= 1 { return nil }
        let parts = foods.map { Self.foodWords($0) }
        // An everyday name no plain food answers is its foods (see `searchApart`).
        let dish = Array(parts.joined(separator: ["and"]))
        let names = !EverydayPhrases.isName(dish) || ranked.first.map { $0.name >= 1 && !FoodText($0.food).branded } == true
        switch together(parts, ranked, cooked: Self.waysSaid(foods), names: names) {
        case .one: return nil
        case .first(let ranked): return (ranked, false)
        case .apart: break
        }
        let each = foods.map { rankCandidates(name: Self.alone($0, among: foods), brand: "", personal: personal, known: known, out: nil) }
        guard each.allSatisfy({ $0.first.map { $0.name >= 1 && ($0.food.source == .usda || known[$0.food.id] != nil) } == true }) else { return nil }
        let apart = { (found: Ranked) in
            let text = FoodText(found.food)
            return text.branded || known[found.food.id] != nil || !hasEach(text, parts) || isJoint(text, parts)
        }
        return (Self.joined(Self.inTurn(each).filter(apart), ranked.filter(apart)), true)
    }

    /// One list's foods, then the other's that aren't among them, with no score above the one
    /// before it: a caller that orders by score keeps this order.
    private static func joined(_ first: [Ranked], _ rest: [Ranked]) -> [Ranked] {
        let found = Set(first.map(\.food.id))
        var both = first + rest.filter { !found.contains($0.food.id) }
        for i in both.indices.dropFirst() { both[i].score = min(both[i].score, both[i - 1].score) }
        return both
    }

    /// With `out`, the food as such a place serves it comes first (see `RankHints.out`).
    /// `sides` is what the food was typed with, which only tells two foods that are the food
    /// apart (see `RankHints.sides`).
    private func searchCatalog(
        _ typed: String, known: [String: Double], out: String?, sides: [String] = [], beside: [String] = []
    ) -> CatalogSearch {
        // One of the last few searches, as it was found: the person's own foods count the same.
        let asked = RecentSearch.Asked(typed: typed, out: out, sides: sides, beside: beside)
        if let found = recent.withLock({ list in list.first { $0.asked == asked && $0.known == known }?.found }) { return found }
        let found = searchCatalogs(typed, known: known, out: out, sides: sides, beside: beside)
        recent.withLock { list in
            list.insert(RecentSearch(asked: asked, known: known, found: found), at: 0)
            if list.count > RecentSearch.kept { list.removeLast() }
        }
        return found
    }

    private func searchCatalogs(_ typed: String, known: [String: Double], out: String?, sides: [String], beside: [String]) -> CatalogSearch {
        guard !catalogs.isEmpty else { return CatalogSearch(text: typed) }
        // A name labels write as one word or as two is searched the usual way, and the other too;
        // a word that can only have been a typo is read by the names of the word it meant.
        let respelt = respell(typed, meant: typos(in: typed))
        let query = respelt.text
        let reading = readQuery(query)
        // A single letter matches most of the catalog, so the search waits for a second one.
        let searched = searchedWords(reading.words)
        let foods = searched.filter { !isNumber($0) }
        guard !foods.isEmpty else { return CatalogSearch(text: query) }
        var fixes: Fixes = [:]
        var doubted = Set<String>()
        // Not the words of an everyday food's whole name: "mapo tofu" isn't mayo. Nor a
        // restaurant chain's: El Pollo Loco isn't coconut, whatever the catalogs have of it.
        let everyday = EverydayPhrases.isName(searched)
        let chain = Chains.chain(in: searched, typed: typed)?.span ?? (Chains.isName(searched) ? 0..<searched.count : nil)
        for (i, word) in searched.enumerated() where !everyday && !isNumber(word) && fixes[word] == nil && chain?.contains(i) != true {
            let spelling = spell(word, whole: i < searched.count - 1)
            if !spelling.fixes.isEmpty { fixes[word] = spelling.fixes }
            if spelling.doubted { doubted.insert(word) }
        }
        // Two letters with a word after them are a word, not the start of one (see `isShortWord`).
        let short = Set(searched.dropLast().filter(isShortWord))
        let term = { (word: String) in short.contains(word) ? "\"\(word)\"" : searchTerm(word, fixes) }
        let expression = searched.map(term).joined(separator: " AND ")
        // Each search below is also made with every name written the other way, as one word or as
        // two. It's a search of its own: among the alternatives of one expression, the rarer
        // spelling's foods would take the places of the usual one's.
        // And one for each other wording, where the words have more than one between them:
        // "crunchy peanut butter" is "chunk" peanut butter, or crunchy "peanutbutter".
        let wordings = Array(Set(respelt.also.values.joined())).sorted().prefix(3)
        let others = wordings.map { form in
            { (word: String) in respelt.also[word]?.contains(form) == true ? searchTerm(word, [word: [form]], only: true) : term(word) }
        }
        let other = { (word: String) in respelt.also[word].map { searchTerm(word, [word: $0], only: true) } ?? term(word) }
        // And with every word by its other wording at once, where each has its own: "bok choy"
        // is "pak choi".
        let ways = respelt.also.isEmpty ? [term] : wordings.count > 1 ? [term] + others + [other] : [term, other]
        // USDA names lead with the food ("Chicken, broilers or fryers, breast…"), so those come first.
        let lead = { (word: String) in fixes[word]?.first ?? searchForms(word)[0] }
        // The words alone rank 12-grain bread too low to reach it for "12 grain bread", or a chain's
        // 14" pizza among every pepperoni pizza for "14 inch pepperoni pizza".
        // Nor do the words without the letter they end with reach Special K for "special k".
        let phrases =
            reading.counts.map { "\"\($0.0) \(stem($0.1))\"*" } + reading.sizes.map { "(\"\($0)\" OR \"\($0)in\"*)" }
            + (reading.letter.isEmpty ? [] : ["\"\(reading.letter[0]) \(reading.letter[1])\""])
        let span = findBrand(searched, fixes, typed: typed)
        let brand = span.map { Array(searched[$0]) } ?? []
        let named = span.map { span in searched.indices.filter { !span.contains($0) }.map { searched[$0] } } ?? []
        let product = named.filter { !isNumber($0) }
        // With a brand, also the brand's foods with any of the other words (packaged foods by their
        // brand, a chain USDA names by its name), and those words' foods by any brand. A brand alone
        // is all of its foods, the most scanned first.
        var any: [String] = []
        for word in named { for way in ways where !any.contains(way(word)) { any.append(way(word)) } }
        let anyWord = product.isEmpty ? "" : " AND (\(any.joined(separator: " OR ")))"
        let found = run([
            product.isEmpty ? [] : ways.flatMap { way in jobs(catalogs, named.map(way).joined(separator: " AND "), .typed) },
            phrases.isEmpty ? [] : jobs(catalogs, (phrases + [expression]).joined(separator: " AND ")),
            jobs(catalogs, expression, .typed, lead: lead(foods[0])),
            brand.isEmpty
                ? []
                : ways.flatMap { way in
                    let brandTerms = "(\(brand.map(way).joined(separator: " AND ")))"
                    return jobs(branded, "{brand}: \(brandTerms)\(anyWord)", .typed)
                        + jobs(catalogs.filter { $0.kind == .generic }, "{name}: \(brandTerms)\(anyWord)", .typed)
                },
            ways.dropFirst().flatMap { way in jobs(catalogs, searched.map(way).joined(separator: " AND "), .typed) },
            // The foods of the word the last is most likely on its way to: two letters match too
            // much for the everyday food to be among the first found ("ch" for chicken).
            EverydayPhrases.likely(searched).map { likely in
                jobs(catalogs, (searched.dropLast().map(term) + [searchTerm(likely)]).joined(separator: " AND "), .typed, lead: stem(likely))
            } ?? [],
            // The plain foods without a word for how they're cooked or cut, which the ranking
            // may read as the food asked for (see `Ease`): cooked salmon for "baked salmon",
            // salmon for "salmon fillet". The words together only find the labels that say so.
            span == nil ? ways.flatMap { easedJobs(searched, $0, lead) } : [],
            // And the usual kind of what was typed, which the first rows found needn't hold:
            // orange juice among every food with "juice" in its name.
            span == nil ? everydayQueries(Named(name: query, brand: "")).flatMap { jobs(catalogs.filter { $0.kind == .generic }, $0, .typed) } : [],
            // The words as typed, where a correction is a long shot: the foods of a name the
            // catalogs know come after the correction's, which are many more ("skittles"
            // beside every skinless chicken breast). Not for a likelier typo, which would
            // only find the labels that share it.
            fixes.contains { word, readings in readings.contains { isLongShot($0, for: word) } }
                ? jobs(catalogs, searched.map { searchTerm($0) }.joined(separator: " AND "), .typed, lead: searchForms(foods[0])[0]) : [],
            // And the brands that start as a corrected word alone is typed, which the
            // correction's foods would crowd out: "cholu" is on its way to Cholula, whatever
            // "chou…" it is also read as.
            searched.count == 1 && !fixes.isEmpty ? jobs(branded, "{brand}: \(searchTerm(searched[0]))", .typed) : [],
            // And the brands that go on from a word with the letter typed after it, which the
            // word alone needn't reach: "swiss m" is on its way to Swiss Miss among every
            // Swiss cheese. A phrase that ends on one letter is too slow to search for.
            searched.count == 1 && !reading.letter.isEmpty
                ? branded.map {
                    MatchJob(
                        catalog: $0, expression: "{brand}: \"\(reading.letter[0])\"", limit: MatchLimits.few.branded, lead: "",
                        begun: "\(reading.letter[0]) \(reading.letter[1])")
                } : [],
            // And the foods that have what the food was typed with, however many are the food:
            // "Potato, mashed, from restaurant, with gravy" among every mashed potato.
            sides.isEmpty
                ? [] : jobs(catalogs, ([expression] + sides.map { searchTerm($0) }).joined(separator: " AND "), .typed, lead: lead(foods[0])),
        ])
        let anyBrand = found[0]
        var pool =
            found[1] + found[2] + found[4] + found[3] + anyBrand + found[5] + found[6] + found[7] + found[8] + found[9] + found[10] + found[11]
        if pool.count < 10 && searched.count > 1 {
            // Few foods have every word, so also the word that names the food ("pizza slice" names
            // pizza) and, without a brand, foods missing one word ("zesty homestyle banana").
            let head = foods.last { !countWords.contains($0) } ?? foods[foods.count - 1]
            // Each expression once: another wording of an earlier word leaves the last as it is.
            var asked = Set<String>()
            var more = ways.map { $0(head) }.filter { asked.insert($0).inserted }.map { jobs(catalogs, $0, .typed, lead: lead(head)) }
            if span == nil && foods.count > 2 {
                // Among labels only where none has every word: it's the slowest thing a search
                // asks of three million of them, and a label that has them all is the one meant.
                // Every word but the last whole, and none read as another: "gali" may be Galli
                // misspelt, whatever Galil sells by the other words.
                let whole = searched.dropLast().map(stem)
                let labelled =
                    fixes.isEmpty
                    && (found[2] + found[4]).contains { hit in
                        let text = hit.entry.text
                        return text.branded && whole.allSatisfy { word in (text.all + text.own).contains { same($0, word) } }
                    }
                let from = labelled ? catalogs.filter { $0.kind == .generic } : catalogs
                for way in ways {
                    let missing = searched.indices.map { i in
                        "(" + searched.indices.filter { $0 != i }.map { way(searched[$0]) }.joined(separator: " AND ") + ")"
                    }
                    let expression = missing.joined(separator: " OR ")
                    if asked.insert(expression).inserted { more.append(jobs(from, expression, .typed)) }
                }
            }
            pool += run(more).flatMap { $0 }
        }
        var search = CatalogSearch(text: query, fixes: fixes, brand: brand, doubted: doubted, also: respelt.also)
        search.typed = respelt.typed
        // What the words besides the brand usually name, from the foods they name by any brand.
        let kind = product.isEmpty ? nil : profile(for: named, anyBrand.map(\.entry), fixes: search.readings, respelt: respelt.forms)
        var seen = Set<String>()
        let unique = pool.lazy.map(\.entry).filter { seen.insert($0.food.id).inserted }
        search.elsewhere = Set(pool.filter { !$0.home }.map(\.food.id))
        search.ranked = rankSearch(
            query, Array(unique), known: known,
            hints: RankHints(
                fixes: search.readings, popularity: true, away: Set(pool.filter(\.away).map(\.food.id)),
                brand: brand, profile: kind, doubted: doubted, respelt: respelt.forms, sides: sides, beside: beside, out: out))
        return search
    }

    /// Searches of the generic foods for the words that say what a food is, without the ones that
    /// say how it's cooked or cut: the foods a search for those words alone would find, which
    /// show what the food is filed under, and with a way of cooking among the words left out,
    /// its cooked ones, however many others there are.
    private func easedJobs(_ words: [String], _ term: (String) -> String, _ lead: (String) -> String) -> [MatchJob] {
        let rest = words.filter { !isEasable($0) }
        guard rest.count < words.count, let first = rest.first(where: { !isNumber($0) }) else { return [] }
        let generic = catalogs.filter { $0.kind == .generic }
        let food = rest.map(term).joined(separator: " AND ")
        return jobs(generic, food, .typed, lead: lead(first))
            + (words.contains(where: isHeat) ? jobs(generic, "\(food) AND \(heatedTerm)", .typed, lead: lead(first)) : [])
    }

    /// Catalog searches for a food a model saw, from most to least specific: brand and name, brand
    /// and head noun, the name, its last two words, the head noun ("cheese" of "cheddar cheese"),
    /// then the first word ("beef" of "beef patty"). With `also`, each word that has another name
    /// is searched by that instead: "frankfurter" for the words of "hot dog".
    func catalogQueries(_ seen: Named, also: Fixes = [:]) -> [String] {
        let name = nameWords(seen.name)
        let brand = Array(words(seen.brand).prefix(3))
        let wording = { (word: String) in also[word].map { searchTerm(word, [word: $0], only: true) } ?? term(word) }
        let every = { (list: [String]) in list.map(wording).joined(separator: " AND ") }
        var queries: [String] = []
        if !brand.isEmpty && !name.isEmpty {
            queries.append(every(brand + name))
            if name.count > 1 { queries.append(every(brand + [name[name.count - 1]])) }
        }
        if !name.isEmpty { queries.append(every(name)) }
        if name.count > 2 { queries.append(every(Array(name.suffix(2)))) }
        if name.count > 1 { queries += [wording(name[name.count - 1]), wording(name[0])] }
        var seenQueries = Set<String>()
        return queries.filter { seenQueries.insert($0).inserted }
    }

    /// Candidates for a seen food: the person's own that match it, then catalog searches from most
    /// to least specific until 40 are found, ranked with the typed search's scorer.
    func matchCandidates(name said: String, brand: String, personal: [PersonalFood], limit: Int) -> [FoodMatch] {
        let known = Self.known(personal)
        var ranked = rankCandidates(name: said, brand: brand, personal: personal, known: known, out: nil)
        // A restaurant chain's food the catalogs have none of is that food as such a place
        // serves it, as when it's typed (see `searchCatalog`): fries from Five Guys are fries
        // from fast food, before another brand's fries or the plain ones.
        if let place = Chains.place(of: brand), !ranked.prefix(5).contains(where: \.mine) {
            let plain = rankCandidates(name: said, brand: "", personal: personal, known: known, out: place)
            if let first = plain.first, first.name >= 1, !FoodText(first.food).branded { ranked = Self.joined(plain, ranked) }
        }
        // Two foods named as one: the food named as both first, or, where no food found is,
        // each one's candidates, none of them named by the whole, so nothing is logged for
        // the two without a look.
        var whole = true
        if brand.isEmpty, let both = candidatesTogether(seenName(Self.named(said, in: region)).main, ranked, personal: personal, known: known) {
            ranked = both.ranked
            whole = !both.apart
        }
        return ranked.prefix(limit).map {
            FoodMatch(food: $0.food, score: $0.score, personal: known[$0.food.id] != nil, named: whole && $0.name >= 1, called: whole && $0.called)
        }
    }

    /// The candidates in order. With `out`, the food as such a place serves it comes first (see
    /// `RankHints.out`).
    private func rankCandidates(name said: String, brand: String, personal: [PersonalFood], known: [String: Double], out: String?) -> [Ranked] {
        // What's said for a food instead of its name is read by the whole of it first: a
        // "hamburger with cheese" is a cheeseburger, not a hamburger that comes with cheese.
        let said = brand.isEmpty ? Self.named(said, in: region) : said
        // What a model says comes with a food or about it ("toast with butter", "yogurt
        // (nonfat)") is kept apart from its name: the food is found by its own words. A brand's
        // product keeps its whole name.
        var (food, sides, beside) = brand.isEmpty ? seenName(said) : (said, [], [])
        // What the catalog names by exactly the words seen is that food, whatever it's said to
        // come with: its "Pasta with meat sauce", its "Biscuit with gravy".
        if !sides.isEmpty, isPlainName(words(said)[...]) { (food, sides, beside) = (said, [], []) }
        // A plain dish is looked up in the catalog's words.
        let dish = brand.isEmpty ? catalogDish(plainlyCooked(food) ?? food) : said
        // Its names are read as a typed search's are: written the way most labels write them
        // ("hotdog" is "hot dog", "soy milk" is "soymilk"), and also by the catalogs' own name for
        // them, so a hot dog is USDA's frankfurter and a bell pepper its sweet pepper.
        let read = respell(dish, typing: false)
        // A brand's "Ranch" is its own; only a plain "ranch" is the salad dressing.
        let name = brand.isEmpty ? read.text : read.typed ?? read.text
        let seen = Named(name: name, brand: brand)
        var pool: [Entry] = []
        var ids: [String: Int] = [:]
        // The person's own foods are found by the name as it was said: their Ranch Dip by "ranch".
        let own = read.typed ?? name
        let check = CoverageQuery(seen: Named(name: own, brand: brand), target: nameWords(own), fixes: read.also, respelt: read.forms)
        for item in personal {
            let entry = Entry(item.food)
            guard check.cover(entry.text).name >= 0.5 else { continue }
            if let index = ids[item.food.id] {
                pool[index] = entry
            } else {
                ids[item.food.id] = pool.count
                pool.append(entry)
            }
        }
        var away = Set<String>()
        var searched: [String: [Entry]] = [:]
        // The foods whose names start as the name said come first of what each search keeps:
        // "Fish & Chips" among everything with fish and chips in its name. Not with a brand,
        // whose own name for the food may start any way: "Shredded Bite Size Wheats".
        let lead = brand.isEmpty ? nameWords(name).first.map(stem) ?? "" : ""
        func search(_ expression: String) -> [Entry] {
            if let found = searched[expression] { return found }
            let hits = match(catalogs, expression, .matching, lead: lead)
            for hit in hits {
                if hit.away { away.insert(hit.food.id) }
                if ids[hit.food.id] == nil {
                    ids[hit.food.id] = pool.count
                    pool.append(hit.entry)
                }
            }
            let found = hits.map(\.entry)
            searched[expression] = found
            return found
        }
        for query in catalogQueries(seen) {
            if pool.count >= 40 { break }
            _ = search(query)
        }
        // By its other name too, as far as the first search that finds it, however many foods
        // have the words said: relish and buns have "hot dog", and the frankfurters don't.
        if !read.also.isEmpty {
            for query in catalogQueries(seen, also: read.also) where !search(query).isEmpty { break }
        }
        // The everyday form can have a name too long for the broad searches to reach.
        for query in everydayQueries(seen, pool: pool) { _ = search(query) }
        // And the food without the words for how it's cooked or cut: salmon for a grilled
        // salmon fillet, which the ranking may read as USDA's cooked salmon (see `Ease`).
        // Both the foods a search for those words alone would find, which show what the food is
        // filed under, and its cooked ones.
        if brand.isEmpty {
            let said = nameWords(name)
            let rest = said.filter { !isEasable($0, seen: true) }
            if rest.count < said.count, !rest.isEmpty {
                // By its other name too: a seared tuna steak is USDA's fresh tuna.
                let wording = { (word: String) in read.also[word].map { searchTerm(word, [word: $0], only: true) } ?? term(word) }
                for way in read.also.isEmpty ? [term] : [term, wording] {
                    let food = rest.map(way).joined(separator: " AND ")
                    _ = search(food)
                    if said.contains(where: isHeat) { _ = search("\(food) AND \(heatedTerm)") }
                }
            }
            // And the food with what was said to come with it, where one entry is both:
            // "Potato, mashed, from restaurant, with gravy".
            if !sides.isEmpty { _ = search((said + sides).map(term).joined(separator: " AND ")) }
        }
        // A misread brand should cost one tap, so the plain food stays among the options. What it
        // usually is also tells the brand's own name for it from the brand's other foods: Trader
        // Joe's Mini-Wheats are its "Shredded Bite Size Wheats", not its wheat bread.
        let plain = brand.isEmpty ? nil : catalogQueries(Named(name: name, brand: "")).first
        let kind = plain.flatMap { profile(for: nameWords(name), search($0), fixes: read.also, respelt: read.forms) }
        var ranked = scoreFoods(
            seen, pool, known: known,
            hints: RankHints(fixes: read.also, away: away, profile: kind, respelt: read.forms, sides: sides, beside: beside, out: out))
        // Where the reading added words to the name, the person's own foods are ranked by it as
        // it was said: their Ranch Dip has "ranch", not "salad dressing".
        if own != name {
            let mine = pool.filter { known[$0.food.id] != nil }
            for said in scoreFoods(Named(name: own, brand: brand), mine, known: known, hints: RankHints(away: away)) {
                if let i = ranked.firstIndex(where: { $0.food.id == said.food.id }) {
                    ranked[i].score = max(ranked[i].score, said.score)
                } else {
                    ranked.append(Ranked(food: said.food, score: said.score, index: pool.count + ranked.count, name: said.name))
                }
            }
            ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        }
        let head = ranked.prefix(brand.isEmpty ? 8 : 6)
        let generic = brand.isEmpty ? [] : ranked.dropFirst(head.count).filter { !FoodText($0.food).branded }.prefix(2)
        let first = Set((head + generic).map(\.index))
        return Array(head) + Array(generic) + ranked.filter { !first.contains($0.index) }
    }
}

/// A flavour named as two foods: a search for one is for the ice cream, the crisps or the
/// sauce of that flavour, not for the two foods.
private struct Flavour {
    /// Its words without the "and", stemmed, as a search's are compared.
    let stems: [String]
    /// The words either side of the "and", stemmed.
    let before: String
    let after: String

    init(_ name: String) {
        let said = name.split(separator: " ").map(String.init)
        let and = said.firstIndex(of: "and") ?? 1
        stems = said.filter { $0 != "and" }.map(stem)
        before = stem(said[and - 1])
        after = stem(said[and + 1])
    }
}

private let flavours: [Flavour] = [
    "cookies and cream", "salt and vinegar", "sour cream and onion", "sweet and salty", "sweet and sour", "hot and sour", "peaches and cream",
    "strawberries and cream", "berries and cream", "fruit and nut", "honey and oats", "milk and honey", "black and white",
    "sea salt and vinegar", "cheddar and sour cream", "cinnamon and sugar", "brown sugar and cinnamon", "maple and brown sugar",
    "apples and cinnamon", "apple and cinnamon", "lemon and lime", "garlic and herb", "cheese and onion", "chocolate and peanut butter",
    "peanut butter and chocolate", "chocolate and vanilla",
].map(Flavour.init)
