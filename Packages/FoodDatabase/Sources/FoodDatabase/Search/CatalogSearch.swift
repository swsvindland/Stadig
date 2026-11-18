import Foundation
import Synchronization

/// A typed search's ranked catalog foods, the search as it was read (see `Respelt`), the corrections
/// it searched for, the words that named a brand and the words the catalogs barely know.
struct CatalogSearch {
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
    /// The generic catalog is small, so a deeper limit there reaches plain foods that rank below variations.
    static let typed = MatchLimits(generic: 150, branded: 60)
    /// What AI matching reads per query.
    static let matching = MatchLimits(generic: 100, branded: 30)
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
            results.withLock { $0[0] = all[0].catalog.match(all[0].expression, limit: all[0].limit, lead: all[0].lead) }
        } else if all.count > 1 {
            DispatchQueue.concurrentPerform(iterations: all.count) { i in
                let job = all[i]
                let hits = job.catalog.match(job.expression, limit: job.limit, lead: job.lead)
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
        let doubted = known < rare || (known < uncommon && size >= 6)
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
        let spelling = Spelling(doubted: doubted, fixes: fixes)
        spellings.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[remembering] = spelling
        }
        return spelling
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
        // What people type for a food instead of its name: "pb&j".
        if let name = shortNames[tokens.map(\.word).joined(separator: " ")] {
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
                for (at, catalog) in name.means { also(catalog, for: [typed[at]]) }
            }
        }
        // Typed alone, "ranch" is the dressing and "spaghetti" is also USDA's pasta. A word still
        // being typed is, from four letters.
        let only = tokens.indices.filter(named)
        if only.count == 1 {
            let alone = tokens[only[0]]
            let word = meant[alone.word] ?? likely.flatMap { length(alone.word) >= 4 ? $0 : nil } ?? alone.word
            if let meant = aloneNames[stem(word)] {
                write(meant, over: alone.start..<alone.end)
                text += scalars[copied...]
                respelt.text = makeString(text[...])
                respelt.typed = query
                return respelt
            }
            if let filed = aloneFiled[stem(word)] { also(filed, for: [alone.word]) }
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

    /// The words at the start or end of a search that name a brand, the most words first: "trader
    /// joes" in "trader joes mini wheats" or "mini wheats trader joes", and "little caesars" before
    /// "little". A search of two or three words that is a brand as a whole ("trader joes", "great
    /// value") is that brand, not "trader" and a food called "joes"; a brand of one word alone
    /// ("kirkland", or "pop" on its way to Pop-Tarts) is searched as any other.
    private func findBrand(_ words: [String], _ fixes: Fixes) -> Range<Int>? {
        guard words.count > 1 else { return nil }
        let catalog = branded.first
        for size in stride(from: min(words.count, 3), through: 1, by: -1) {
            for start in Set([0, words.count - size]).sorted() {
                let span = words[start..<(start + size)]
                // A letter on its own is a size or a variety ("k cup"), whatever brands start with it.
                guard span.contains(where: { length($0) > 1 }) else { continue }
                // Nor are two letters at the end a brand begun: the "do" of "hot do" isn't Doritos.
                if size == 1, start + size == words.count, length(words[start]) < 3 { continue }
                if let catalog, isBrand(span, catalog, fixes) {
                    if size == 1, isNamed(words, without: start, catalog, fixes) { continue }
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
        let names = Set(searchedWords(readQuery(typed).words))
        var meant: [String: String] = [:]
        for (i, token) in tokens.enumerated() where names.contains(token.word) && length(token.word) >= 4 && !stopWords.contains(token.word) {
            let spelling = spell(token.word, whole: i < tokens.count - 1 || token.end < scalars.count)
            guard spelling.doubted else { continue }
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
        for (i, word) in searched.enumerated() where !isNumber(word) && fixes[word] == nil {
            let spelling = spell(word, whole: i < searched.count - 1)
            if !spelling.fixes.isEmpty { fixes[word] = spelling.fixes }
            if spelling.doubted { doubted.insert(word) }
        }
        let term = { (word: String) in searchTerm(word, fixes) }
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
        let ways = respelt.also.isEmpty ? [term] : wordings.count > 1 ? [term] + others : [term, other]
        // USDA names lead with the food ("Chicken, broilers or fryers, breast…"), so those come first.
        let lead = { (word: String) in fixes[word]?.first ?? searchForms(word)[0] }
        // The words alone rank 12-grain bread too low to reach it for "12 grain bread", or a chain's
        // 14" pizza among every pepperoni pizza for "14 inch pepperoni pizza".
        let phrases =
            reading.counts.map { "\"\($0.0) \(stem($0.1))\"*" } + reading.sizes.map { "(\"\($0)\" OR \"\($0)in\"*)" }
        let span = findBrand(searched, fixes)
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
            span == nil ? easedJobs(searched, term, lead) : [],
        ])
        let anyBrand = found[0]
        var pool = found[1] + found[2] + found[4] + found[3] + anyBrand + found[5] + found[6]
        if pool.count < 10 && searched.count > 1 {
            // Few foods have every word, so also the word that names the food ("pizza slice" names
            // pizza) and, without a brand, foods missing one word ("zesty homestyle banana").
            let head = foods.last { !countWords.contains($0) } ?? foods[foods.count - 1]
            var more = ways.map { way in jobs(catalogs, way(head), .typed, lead: lead(head)) }
            if span == nil && foods.count > 2 {
                for way in ways {
                    let missing = searched.indices.map { i in
                        "(" + searched.indices.filter { $0 != i }.map { way(searched[$0]) }.joined(separator: " AND ") + ")"
                    }
                    more.append(jobs(catalogs, missing.joined(separator: " OR "), .typed))
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
                brand: brand, profile: kind, doubted: doubted, respelt: respelt.forms))
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
        // A brand's own product keeps its name; a plain dish is looked up in the catalog's words.
        let dish = brand.isEmpty ? catalogDish(said) : said
        // Its names are read as a typed search's are: written the way most labels write them
        // ("hotdog" is "hot dog", "soy milk" is "soymilk"), and also by the catalogs' own name for
        // them, so a hot dog is USDA's frankfurter and a bell pepper its sweet pepper.
        let read = respell(dish, typing: false)
        // A brand's "Ranch" is its own; only a plain "ranch" is the salad dressing.
        let name = brand.isEmpty ? read.text : read.typed ?? read.text
        let seen = Named(name: name, brand: brand)
        let known = Self.known(personal)
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
        if brand.isEmpty {
            let said = nameWords(name)
            let rest = said.filter { !isEasable($0) }
            if rest.count < said.count, !rest.isEmpty {
                _ = search(rest.map(term).joined(separator: " AND ") + (said.contains(where: isHeat) ? " AND \(heatedTerm)" : ""))
            }
        }
        // A misread brand should cost one tap, so the plain food stays among the options. What it
        // usually is also tells the brand's own name for it from the brand's other foods: Trader
        // Joe's Mini-Wheats are its "Shredded Bite Size Wheats", not its wheat bread.
        let plain = brand.isEmpty ? nil : catalogQueries(Named(name: name, brand: "")).first
        let kind = plain.flatMap { profile(for: nameWords(name), search($0), fixes: read.also, respelt: read.forms) }
        var ranked = scoreFoods(seen, pool, known: known, hints: RankHints(fixes: read.also, away: away, profile: kind, respelt: read.forms))
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
        let ordered = Array(head) + Array(generic) + ranked.filter { !first.contains($0.index) }
        return ordered.prefix(limit).map { FoodMatch(food: $0.food, score: $0.score, personal: known[$0.food.id] != nil) }
    }
}
