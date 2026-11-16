import Foundation
import Synchronization
import Testing

@testable import FoodDatabase

/// How often a search puts the food it was typed for first, however it was typed. Packaged foods
/// people in the US scan are each asked for a dozen ways (the brand first, last or between the
/// name's words, the words in another order, a typo, a word half typed or left out), and the report
/// says where the food came for each way. It fails when a way of typing falls below its floor, so a
/// change to the ranking that helps one search can't quietly cost the rest.
@Suite("Search quality", .enabled(if: Catalogs.hasOFF, "needs Apps/MacroTrack/Catalogs/off.db or OFF_DB"), .serialized)
struct SearchQualityTests {
    /// A food to search for, and its name and brand as words a person would type.
    struct Target {
        var name: String
        var brand: String
        var named: [String]
        var branded: [String]
    }

    /// SplitMix64: small, seeded and the same everywhere.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The first `count` of the most scanned US foods, shuffled, whose name is two to five words a
    /// person would type whole and whose brand isn't already in it.
    static func targets(_ count: Int) throws -> [Target] {
        guard let url = Catalogs.offURL else { return [] }
        var rows: [(String, String)] = []
        try ConnectionPool(url: url).with { connection in
            try connection.query(
                """
                SELECT name, brand FROM foods
                WHERE markets IN ('us', 'us world', 'ca us', 'ca us world') AND brand <> '' AND popularity >= 2.2
                ORDER BY rowid LIMIT 20000
                """
            ) { row in
                if let name = row.string(0), let brand = row.string(1) { rows.append((name, brand)) }
            }
        }
        var random = Seeded(state: 2026)
        rows.shuffle(using: &random)
        var seen = Set<String>()
        var targets: [Target] = []
        for (name, brand) in rows where name.utf8.allSatisfy({ $0 < 0x80 }) && brand.utf8.allSatisfy({ $0 < 0x80 }) {
            let named = words(name)
            let branded = words(brand)
            guard (2...5).contains(named.count), (1...3).contains(branded.count) else { continue }
            guard named.allSatisfy({ length($0) > 2 && !$0.unicodeScalars.contains(where: isDigit) }), branded.allSatisfy({ length($0) > 2 }) else {
                continue
            }
            guard Set(named).isDisjoint(with: branded), Set(named).count == named.count else { continue }
            guard seen.insert(same(name, brand)).inserted else { continue }
            targets.append(Target(name: name, brand: brand, named: named, branded: branded))
            if targets.count == count { break }
        }
        return targets
    }

    /// The same product listed another way has the same words: "Pepsi Zero Sugar · Pepsi" and
    /// "ZERO SUGAR · PEPSI".
    static func same(_ name: String, _ brand: String) -> String {
        Set(words("\(name) \(brand)").map(stem)).sorted().joined(separator: " ")
    }

    /// One typo inside a word: two letters swapped, or one dropped, doubled or changed.
    static func typo(_ word: String, _ random: inout Seeded) -> String {
        var letters = Array(word)
        let i = Int.random(in: 1..<(letters.count - 1), using: &random)
        switch Int.random(in: 0..<4, using: &random) {
        case 0 where letters[i] != letters[i + 1]: letters.swapAt(i, i + 1)
        case 1: letters.remove(at: i)
        case 2: letters.insert(letters[i], at: i)
        default: letters[i] = "aeioustrnl".first { $0 != letters[i] } ?? "e"
        }
        return String(letters)
    }

    /// The ways a food is typed, each with the search for it.
    static func searches(for target: Target, _ random: inout Seeded) -> [(way: String, query: String)] {
        let name = target.named
        let brand = target.branded
        var found: [(String, [String])] = [("brand first", brand + name), ("brand last", name + brand)]
        let middle = Int.random(in: 1..<name.count, using: &random)
        found.append(("brand between the name's words", Array(name[..<middle]) + brand + Array(name[middle...])))
        found.append(("name backwards, brand last", name.reversed() + brand))
        var mixed = name + brand
        for _ in 0..<5 where mixed == name + brand || mixed == brand + name { mixed.shuffle(using: &random) }
        found.append(("every word shuffled", mixed))
        if let i = name.indices.filter({ length(name[$0]) >= 5 }).randomElement(using: &random) {
            var wrong = name
            wrong[i] = typo(name[i], &random)
            found.append(("a typo in the name", brand + wrong))
            found.append(("a typo in the name, brand last", wrong + brand))
        }
        if let i = brand.indices.filter({ length(brand[$0]) >= 5 }).randomElement(using: &random) {
            var wrong = brand
            wrong[i] = typo(brand[i], &random)
            found.append(("a typo in the brand", wrong + name))
        }
        if let last = name.last, length(last) >= 5 {
            found.append(("the name's last word half typed", brand + name.dropLast() + [String(last.prefix(max(3, last.count / 2)))]))
        }
        if let last = brand.last, length(last) >= 5 {
            found.append(("the brand last and half typed", name + brand.dropLast() + [String(last.prefix(max(3, last.count / 2 + 1)))]))
        }
        if brand.count > 1 { found.append(("the brand typed as one word", [brand.joined()] + name)) }
        if name.count > 2 {
            var shorter = name
            shorter.remove(at: Int.random(in: 0..<name.count, using: &random))
            found.append(("a word of the name left out", brand + shorter))
        }
        found.append(("the name without its brand", name))
        return found.map { ($0.0, $0.1.joined(separator: " ")) }
    }

    /// The least share of searches, of each way that names one food, that must put it first. Each
    /// is a few points under what the ranking does on this catalog, for the foods that differ only
    /// in how they're listed; the two ways that leave a word out name several foods and have none.
    static let floors: [String: Double] = [
        "brand first": 0.94, "brand last": 0.92, "brand between the name's words": 0.93, "name backwards, brand last": 0.93,
        "every word shuffled": 0.92, "a typo in the name": 0.93, "a typo in the name, brand last": 0.92, "a typo in the brand": 0.93,
        "the name's last word half typed": 0.94, "the brand last and half typed": 0.91, "the brand typed as one word": 0.78,
    ]

    @Test("a packaged food is found first however its name and brand are typed")
    func ranks() throws {
        let count = ProcessInfo.processInfo.environment["SEARCH_QUALITY_FOODS"].flatMap(Int.init) ?? 120
        let targets = try Self.targets(count)
        try #require(targets.count == count, "the catalog has \(targets.count) such foods")
        var random = Seeded(state: 7)
        var searches: [(way: String, query: String, wanted: String)] = []
        for target in targets {
            for search in Self.searches(for: target, &random) { searches.append((search.way, search.query, Self.same(target.name, target.brand))) }
        }
        let asked = searches
        let catalog = Catalogs.both
        let places = Mutex<[Int?]>(Array(repeating: nil, count: asked.count))
        DispatchQueue.concurrentPerform(iterations: asked.count) { i in
            let found = catalog.search(asked[i].query, limit: 10)
            let place = found.firstIndex { Self.same($0.food.name, $0.food.brand ?? "") == asked[i].wanted }
            places.withLock { $0[i] = place }
        }
        let placed = places.withLock { $0 }
        var ways: [String] = []
        var byWay: [String: [Int?]] = [:]
        for (i, search) in asked.enumerated() {
            if byWay[search.way] == nil { ways.append(search.way) }
            byWay[search.way, default: []].append(placed[i])
        }
        let share = { (places: [Int?], within: Int) in Double(places.filter { ($0 ?? .max) < within }.count) / Double(max(1, places.count)) }
        var report = "Search quality (\(targets.count) foods, \(asked.count) searches): first, in the first three, in the first ten\n"
        for way in ways {
            let places = byWay[way] ?? []
            let line = [1, 3, 10].map { String(format: "%5.1f%%", 100 * share(places, $0)) }.joined(separator: " ")
            report += "  \(line)  \(way) (\(places.count))\n"
            if let floor = Self.floors[way] {
                let missed = asked.indices.filter { asked[$0].way == way && placed[$0] != 0 }.prefix(6).map { asked[$0].query }
                #expect(share(places, 1) >= floor, "\(way): \(missed.joined(separator: " | "))")
            }
        }
        report += "  " + [1, 3, 10].map { String(format: "%5.1f%%", 100 * share(placed, $0)) }.joined(separator: " ") + "  all"
        print(report)
        #expect(share(placed, 3) >= 0.92, "in the first three, over every way of typing")
    }
}
