import Foundation
import Synchronization

/// A typed search's ranked catalog foods, the corrections it searched for and the words that named
/// a brand.
struct CatalogSearch {
    var ranked: [Ranked] = []
    var fixes: Fixes = [:]
    var brand: [String] = []
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

    init(_ text: String, fixes: Fixes = [:]) {
        target = searchedWords(readQuery(text).words)
        numbers = target.filter(isNumber)
        query = CoverageQuery(seen: Named(name: text, brand: ""), target: target, prefix: true, fixes: fixes)
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
    /// else the two words it joins ("peanutbutter"). Remembered for the launch.
    func spell(_ word: String) -> [String] {
        if let remembered = spellings.withLock({ $0[word] }) { return remembered }
        let form = stem(word)
        let size = length(word)
        let limit = allowedTypos(length: size)
        let range = "SELECT term, foods FROM terms WHERE term >= ? AND term < ?"
        var known = uncommon
        if limit > 0 && !word.unicodeScalars.contains(where: isDigit) {
            known = Double(count(range, [.text(form), .text(form + "\u{FFFF}")]).total)
        }
        var fixes: [String] = []
        if known < rare || (known < uncommon && size >= 6) {
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
                guard let found = meter.misread(units, letters), found.edits > 0 else { continue }
                let key = stem(String(decoding: letters[..<found.length], as: UTF16.self))
                if let last = meant[key] {
                    if found.edits < last.edits {
                        meant[key] = (found.edits, foods)
                    } else if found.edits == last.edits {
                        meant[key] = (last.edits, last.foods + foods)
                    }
                } else {
                    meantKeys.append(key)
                    meant[key] = (found.edits, foods)
                }
            }
            let common = meantKeys.filter { Double(meant[$0]!.foods) >= least }
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
            }
            if fixes.isEmpty && known < rare && size >= 6 {
                // Two words typed without the space between them.
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
                if let best, Double(best.foods) >= least { fixes.append("\(best.left) \(stem(best.right))") }
            }
        }
        spellings.withLock { remembered in
            if remembered.count > 500 { remembered.removeAll() }
            remembered[word] = fixes
        }
        return fixes
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
    private func isChain(_ words: ArraySlice<String>, _ catalog: Catalog?, _ fixes: Fixes) -> Bool {
        let forms = words.map { searchForms($0) + (fixes[$0] ?? []) }
        guard
            let chain = chains.first(where: { chain in
                chain.count == forms.count && zip(chain, forms).allSatisfy { word, options in options.contains { starts(word, $0) } }
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
    /// "little". At least one word is left to name the food; a search for a brand alone ("kirkland",
    /// or "pop" on its way to Pop-Tarts) is searched as any other.
    private func findBrand(_ words: [String], _ fixes: Fixes) -> Range<Int>? {
        guard words.count > 1 else { return nil }
        let catalog = branded.first
        for size in stride(from: min(words.count - 1, 3), through: 1, by: -1) {
            for start in Set([0, words.count - size]).sorted() {
                let span = words[start..<(start + size)]
                // A letter on its own is a size or a variety ("k cup"), whatever brands start with it.
                guard span.contains(where: { length($0) > 1 }) else { continue }
                if let catalog, isBrand(span, catalog, fixes) { return start..<(start + size) }
                if isChain(span, catalog, fixes) { return start..<(start + size) }
            }
        }
        return nil
    }

    /// A typed search, best match first. Each word is a stemmed prefix and a word the catalogs
    /// barely know is also searched as what it probably meant. A search that names a brand also
    /// finds the brand's foods that share a word with the rest ("Shredded Bite Size Wheats" for
    /// "trader joes mini wheats") and the foods the rest names under any brand; a longer search that
    /// finds little also finds foods missing one of its words; and a search that finds nothing
    /// falls back to the word that names the food. The person's own foods in `known` rank higher,
    /// and packaged foods people scan more rank higher among themselves.
    func searchCatalog(_ query: String, known: [String: Double]) -> CatalogSearch {
        let reading = readQuery(query)
        // A single letter matches most of the catalog, so the search waits for a second one.
        let searched = searchedWords(reading.words)
        let foods = searched.filter { !isNumber($0) }
        guard !foods.isEmpty, !catalogs.isEmpty else { return CatalogSearch() }
        var fixes: Fixes = [:]
        for word in foods where fixes[word] == nil {
            let meant = spell(word)
            if !meant.isEmpty { fixes[word] = meant }
        }
        let term = { (word: String) in searchTerm(word, fixes) }
        let expression = searched.map(term).joined(separator: " AND ")
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
        // brand, a chain USDA names by its name), and those words' foods by any brand.
        let brandTerms = "(\(brand.map(term).joined(separator: " AND ")))"
        let anyWord = "(\(named.map(term).joined(separator: " OR ")))"
        let found = run([
            product.isEmpty ? [] : jobs(catalogs, named.map(term).joined(separator: " AND "), .typed),
            phrases.isEmpty ? [] : jobs(catalogs, (phrases + [expression]).joined(separator: " AND ")),
            jobs(catalogs, expression, .typed, lead: lead(foods[0])),
            product.isEmpty
                ? []
                : jobs(branded, "{brand}: \(brandTerms) AND \(anyWord)", .typed)
                    + jobs(catalogs.filter { $0.kind == .generic }, "{name}: \(brandTerms) AND \(anyWord)", .typed),
        ])
        let anyBrand = found[0]
        var pool = found[1] + found[2] + found[3] + anyBrand
        if pool.count < 10 && searched.count > 1 {
            // Few foods have every word, so also the word that names the food ("pizza slice" names
            // pizza) and, without a brand, foods missing one word ("zesty homestyle banana").
            let head = foods.last { !countWords.contains($0) } ?? foods[foods.count - 1]
            var more = [jobs(catalogs, term(head), .typed, lead: lead(head))]
            if span == nil && foods.count > 2 {
                let missing = searched.indices.map { i in
                    "(" + searched.indices.filter { $0 != i }.map { term(searched[$0]) }.joined(separator: " AND ") + ")"
                }
                more.append(jobs(catalogs, missing.joined(separator: " OR "), .typed))
            }
            pool += run(more).flatMap { $0 }
        }
        // What the words besides the brand usually name, from the foods they name by any brand.
        let kind = product.isEmpty ? nil : profile(for: named, anyBrand.map(\.entry), fixes: fixes)
        var seen = Set<String>()
        let unique = pool.lazy.map(\.entry).filter { seen.insert($0.food.id).inserted }
        let ranked = rankSearch(
            query, Array(unique), known: known,
            hints: RankHints(
                fixes: fixes, popularity: true, away: Set(pool.filter(\.away).map(\.food.id)),
                brand: brand, profile: kind))
        return CatalogSearch(ranked: ranked, fixes: fixes, brand: brand)
    }

    /// Catalog searches for a food a model saw, from most to least specific: brand and name, brand
    /// and head noun, the name, its last two words, the head noun ("cheese" of "cheddar cheese"),
    /// then the first word ("beef" of "beef patty").
    func catalogQueries(_ seen: Named) -> [String] {
        let name = nameWords(seen.name)
        let brand = Array(words(seen.brand).prefix(3))
        let every = { (list: [String]) in list.map(term).joined(separator: " AND ") }
        var queries: [String] = []
        if !brand.isEmpty && !name.isEmpty {
            queries.append(every(brand + name))
            if name.count > 1 { queries.append(every(brand + [name[name.count - 1]])) }
        }
        if !name.isEmpty { queries.append(every(name)) }
        if name.count > 2 { queries.append(every(Array(name.suffix(2)))) }
        if name.count > 1 { queries += [term(name[name.count - 1]), term(name[0])] }
        var seenQueries = Set<String>()
        return queries.filter { seenQueries.insert($0).inserted }
    }

    /// Candidates for a seen food: the person's own that match it, then catalog searches from most
    /// to least specific until 40 are found, ranked with the typed search's scorer.
    func matchCandidates(name said: String, brand: String, personal: [PersonalFood], limit: Int) -> [FoodMatch] {
        // A brand's own product keeps its name; a plain dish is looked up in the catalog's words.
        let name = brand.isEmpty ? catalogDish(said) : said
        let seen = Named(name: name, brand: brand)
        let known = Self.known(personal)
        var pool: [Entry] = []
        var ids: [String: Int] = [:]
        let check = CoverageQuery(seen: seen)
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
        func search(_ expression: String) -> [Entry] {
            if let found = searched[expression] { return found }
            let hits = match(catalogs, expression, .matching)
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
        // The everyday form can have a name too long for the broad searches to reach.
        for query in everydayQueries(seen, pool: pool) { _ = search(query) }
        // A misread brand should cost one tap, so the plain food stays among the options. What it
        // usually is also tells the brand's own name for it from the brand's other foods: Trader
        // Joe's Mini-Wheats are its "Shredded Bite Size Wheats", not its wheat bread.
        let plain = brand.isEmpty ? nil : catalogQueries(Named(name: name, brand: "")).first
        let kind = plain.flatMap { profile(for: nameWords(name), search($0)) }
        let ranked = scoreFoods(seen, pool, known: known, hints: RankHints(away: away, profile: kind))
        let head = ranked.prefix(brand.isEmpty ? 8 : 6)
        let generic = brand.isEmpty ? [] : ranked.dropFirst(head.count).filter { !FoodText($0.food).branded }.prefix(2)
        let first = Set((head + generic).map(\.index))
        let ordered = Array(head) + Array(generic) + ranked.filter { !first.contains($0.index) }
        return ordered.prefix(limit).map { FoodMatch(food: $0.food, score: $0.score, personal: known[$0.food.id] != nil) }
    }
}
