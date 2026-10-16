import Foundation
import SystemCore
import Synchronization

/// The offline catalogs, read-only: USDA's generic foods and, when the app ships it, Open Food
/// Facts' packaged foods. Each file is opened in place (no copy) and one that fails to open leaves
/// the other working. Thread-safe; search is synchronous and fast, so call it off the main actor.
public final class FoodCatalog: @unchecked Sendable {
    /// The open catalogs, generic foods first.
    let catalogs: [Catalog]
    /// The phone's region as a catalog names a market ("us"), if it has one.
    let region: String?
    /// A word in fewer foods than `rare` is also searched as a word a typo away in ten times as
    /// many; a longer one in fewer than `uncommon` too, when that word is in 75 times as many.
    /// Labels misspell in proportion, so both grow with the catalogs: one food in 4,800 and one in 480.
    let rare: Double
    let uncommon: Double
    /// What a typed word probably meant, remembered for the launch since each keystroke asks again.
    let spellings = Mutex<[String: [String]]>([:])
    /// Whether words name a brand, by their full-text expression, remembered for the launch.
    let brandish = Mutex<[String: Bool]>([:])

    /// Opens the catalogs at these URLs. `region` is the phone's ISO region ("us"), which ranks
    /// packaged foods sold here above those sold only elsewhere.
    public init(usda: URL?, off: URL?, region: String = Locale.current.region?.identifier.lowercased() ?? "us") {
        let here = region.lowercased()
        self.region = here.count == 2 && here.unicodeScalars.allSatisfy({ $0.value >= 0x61 && $0.value <= 0x7A }) ? here : nil
        var catalogs: [Catalog] = []
        if let usda, let catalog = try? Catalog(url: usda, kind: .generic, region: self.region) { catalogs.append(catalog) }
        if let off, let catalog = try? Catalog(url: off, kind: .branded, region: self.region) { catalogs.append(catalog) }
        self.catalogs = catalogs
        let foods = Double(catalogs.reduce(0) { $0 + $1.foods })
        rare = foods / 4800
        uncommon = foods / 480
    }

    /// USDA from this package, plus `off.db` from the app bundle when it ships one.
    public static func standard(region: String = Locale.current.region?.identifier.lowercased() ?? "us") -> FoodCatalog {
        FoodCatalog(usda: Bundle.module.url(forResource: "usda", withExtension: "db"),
                    off: Bundle.main.url(forResource: "off", withExtension: "db"), region: region)
    }

    /// Each open catalog's provenance and licence, for the attribution screen.
    public var sources: [CatalogInfo] {
        catalogs.map { catalog in
            CatalogInfo(name: catalog.kind == .generic ? "USDA FoodData Central SR Legacy" : "Open Food Facts",
                        version: catalog.version, license: catalog.license, attribution: catalog.attribution,
                        source: catalog.source, foods: catalog.foods)
        }
    }

    /// Whether packaged foods (Open Food Facts) are available.
    public var hasPackagedFoods: Bool { catalogs.contains { $0.kind == .branded } }

    /// Ranked results for what the person typed, with their own foods first where they match. Waits
    /// for a last word's second letter, and a number alone isn't a search.
    public func search(_ query: String, personal: [PersonalFood] = [], limit: Int = 50) -> [FoodMatch] {
        guard limit > 0 else { return [] }
        let known = Self.known(personal)
        let found = searchCatalog(query, known: known)
        // The person's own foods come first, ranked like the catalog below them, so rows already on
        // screen don't move when the catalog answers. A typo the catalog corrected finds them too.
        let matcher = QueryMatcher(query, fixes: found.fixes)
        let own = rankSearch(query, personal.map(\.food).filter(matcher.matches), known: known,
                             hints: RankHints(fixes: found.fixes, brand: found.brand))
        var results = own.prefix(limit).map { FoodMatch(food: $0.food, score: $0.score, personal: true) }
        var listed = Set(results.map(\.food.id))
        for row in found.ranked where results.count < limit && listed.insert(row.food.id).inserted {
            results.append(FoodMatch(food: row.food, score: row.score, personal: known[row.food.id] != nil))
        }
        return results
    }

    /// Candidates for a food a model saw or a person described: specific to broad, ranked. The
    /// first is the best match; `score` lets a caller tell a clear winner (≥ 1.5, more than 1 ahead)
    /// from near-ties worth a second opinion. With a brand, two plain foods follow the brand's six
    /// best, so a misread brand is one tap from the plain food.
    public func candidates(name: String, brand: String?, personal: [PersonalFood] = [], limit: Int = 40) -> [FoodMatch] {
        matchCandidates(name: name, brand: brand ?? "", personal: personal, limit: limit)
    }

    /// A food by id: "usda:171287", "off:00016000275287", and the earlier "off:" forms that leave out
    /// leading zeros ("off:0016000275287", "off:06175634").
    public func food(id: String) -> Food? {
        if id.hasPrefix("usda:") {
            return catalogs.lazy.filter { $0.kind == .generic }.compactMap { $0.food(id: id) }.first
        }
        if id.hasPrefix("off:") {
            let code = id.dropFirst(4)
            guard (1...14).contains(code.count), code.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            let key = String(repeating: "0", count: 14 - code.count) + code
            return catalogs.lazy.filter { $0.kind == .branded }.compactMap { $0.food(barcode: key) }.first
        }
        return nil
    }

    /// A packaged food by any barcode form (EAN-13, EAN-8, UPC-A, UPC-E, ITF-14).
    public func food(barcode: String) -> Food? {
        food(barcode: barcode, symbology: nil)
    }

    /// A packaged food by barcode, trying first the reading the scanner's symbology makes likely.
    public func food(barcode: String, symbology: Barcode.Symbology?) -> Food? {
        for key in Barcode.keys(for: barcode, symbology: symbology) {
            for catalog in catalogs.reversed() {
                if let food = catalog.food(barcode: key) { return food }
            }
        }
        return nil
    }

    /// Warm caches and pages in the background after launch.
    public func prewarm() {
        DispatchQueue.global(qos: .utility).async { [self] in
            for query in ["ch", "chicken breast", "milk", "co"] { _ = searchCatalog(query, known: [:]) }
        }
    }

    /// The person's foods by id with how strongly each ranks; the strongest when one is listed twice.
    static func known(_ personal: [PersonalFood]) -> [String: Double] {
        var known: [String: Double] = [:]
        for item in personal { known[item.food.id] = max(known[item.food.id] ?? -.infinity, item.score) }
        return known
    }
}
