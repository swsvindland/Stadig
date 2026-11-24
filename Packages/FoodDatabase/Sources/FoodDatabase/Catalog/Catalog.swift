import Foundation
import Synchronization
import SystemCore

/// One catalog file, open read-only in place: USDA's generic foods or Open Food Facts' packaged ones.
final class Catalog: Sendable {
    enum Kind: Sendable { case generic, branded }

    /// A food a full-text match found, whether it is sold only in other countries, and whether
    /// it's known to be sold in the phone's: a label that lists only the world, or nowhere, isn't.
    struct Hit: Sendable {
        var entry: Entry
        var away: Bool
        var home = true
        var food: Food { entry.food }
    }

    let kind: Kind
    let version: String
    let license: String
    let attribution: String
    let source: String
    /// Rows, counted by the last rowid: catalogs are written once, in order.
    let foods: Int
    /// The order version 3 rows keep nutrient values in; nil for object rows.
    let order: [String]?
    private let pool: ConnectionPool
    private let barcodeIsInteger: Bool
    private let columns: String
    private let matchSQL: String
    private let scannedSQL: String
    private let begunSQL: String
    /// Rows already read this launch, by rowid: each keystroke finds most of the last one's foods.
    private let read = Mutex<[Int64: Entry]>([:])
    /// The generic catalog's rowids by food id, read on the first lookup by id: the file has no
    /// index on id, and the meal planner and the person's foods look up dozens to hundreds by id.
    private let rowids = Mutex<[String: Int64]?>(nil)

    /// Opens a catalog and reads its metadata; throws when the file isn't a catalog.
    init(url: URL, kind: Kind, region: String?) throws {
        self.kind = kind
        pool = try ConnectionPool(url: url)
        var meta: [String: String] = [:]
        var markets = false
        var quality = false
        var integerBarcodes = false
        var otherNames = false
        var foods = 0
        try pool.with { connection in
            try connection.query("SELECT key, value FROM catalog_meta") { row in
                if let key = row.string(0), let value = row.string(1) { meta[key] = value }
            }
            try connection.query("SELECT name, type FROM pragma_table_info('foods')") { row in
                if row.string(0) == "markets" { markets = true }
                if row.string(0) == "nova" { quality = true }
                if row.string(0) == "barcode" { integerBarcodes = row.string(1)?.uppercased() == "INTEGER" }
                if row.string(0) == "also" { otherNames = true }
            }
            try connection.query("SELECT max(rowid) FROM foods") { row in foods = Int(row.int(0)) }
        }
        guard let version = meta["version"] else { throw SQLiteError(code: 0, message: "\(url.lastPathComponent) has no catalog version") }
        self.version = version
        license = meta["license"] ?? ""
        attribution = meta["attribution"] ?? ""
        source = meta["source"] ?? ""
        self.foods = foods
        order = meta["nutrients"].flatMap { JSONValue.parse($0)?.array?.compactMap(\.string) }
        barcodeIsInteger = integerBarcodes
        // Catalogs from before processing and traits were kept read as unknown for both. Only USDA's
        // foods have other names: the chains' items FNDDS files under them.
        columns =
            "foods.rowid, foods.id, foods.name, foods.brand, foods.barcode, foods.data, foods.popularity, "
            + (quality ? "foods.nova, foods.traits" : "NULL, NULL") + (otherNames ? ", foods.also" : ", ''")
        // A brand's recipe differs between countries (US and French Oreos), so a packaged food sold
        // only elsewhere ranks below the foods sold here; one whose countries aren't known isn't one.
        let away: String
        let home: String
        if markets, let region {
            let sold = { (market: String) in "instr(' ' || foods.markets || ' ', ' \(market) ')" }
            away = "(foods.markets <> '' AND \(sold(region)) = 0 AND \(sold("world")) = 0)"
            // Generic foods are everywhere's.
            home = kind == .generic ? "1" : "(\(sold(region)) > 0)"
        } else {
            away = "0"
            home = "1"
        }
        // The foods of the brands that start a given way, the most scanned first.
        begunSQL = """
            SELECT \(columns), \(away) AS away, \(home) AS home FROM (
              SELECT rowid FROM food_search WHERE food_search MATCH ? LIMIT ?
            ) AS hit
            JOIN foods ON foods.rowid = hit.rowid
            WHERE foods.brand LIKE ?
            ORDER BY away, foods.popularity DESC
            LIMIT ?
            """
        scannedSQL =
            "SELECT 1 FROM food_search JOIN foods ON foods.rowid = food_search.rowid "
            + "WHERE food_search MATCH ? AND foods.popularity >= ? AND NOT \(away) LIMIT 1"
        // Names starting with the lead word come before the full-text ranking, then the foods sold
        // in the phone's region, and among packaged foods the ones scanned more often come sooner.
        matchSQL = """
            SELECT \(columns), \(away) AS away, \(home) AS home FROM (
              SELECT rowid, bm25(food_search, 3.0, 1.0) AS score FROM food_search WHERE food_search MATCH ? LIMIT ?
            ) AS hit
            JOIN foods ON foods.rowid = hit.rowid
            ORDER BY foods.name LIKE ? DESC, away, hit.score - 0.5 * foods.popularity
            LIMIT ?
            """
    }

    var foodSource: FoodSource { kind == .generic ? .usda : .off }

    /// A row of `columns` as a food.
    private func food(_ row: SQLRow) -> Food? {
        guard let name = row.string(2) else { return nil }
        let barcode = row.isNull(4) ? nil : barcodeKey(barcodeIsInteger ? String(row.int(4)) : row.string(4))
        let id: String
        if kind == .branded, let barcode {
            id = "off:\(barcode)"
        } else if let stored = row.string(1) {
            id = stored
        } else {
            return nil
        }
        guard let data = row.withBytes(5, { RowData(data: $0, order: order) }) ?? nil else { return nil }
        let brand = row.string(3)
        // Traits are a bit set: 1 is fermented with live cultures. Unset says no only where the
        // catalog looked (USDA names, Open Food Facts labels and ingredients).
        return Food(
            id: id, name: name, brand: brand?.isEmpty == false ? brand : nil, barcode: barcode, basis: data.basis,
            nutrients: data.nutrients, extras: data.extras, portions: data.portions, source: foodSource,
            popularity: row.isNull(6) ? 0 : row.double(6),
            processing: row.isNull(7) ? nil : Processing(rawValue: Int(row.int(7))),
            fermented: row.isNull(8) ? nil : row.int(8) & 1 == 1)
    }

    /// How many matches a catalog ranks. Millions of packaged foods match "ch" or "chicken", so only
    /// the first matches in row order, the most scanned, are ranked; the generic catalog is small
    /// enough to rank whole.
    private var candidates: Int { kind == .generic ? -1 : 1000 }

    /// Runs a full-text expression. Names starting with `lead` come first.
    func match(_ expression: String, limit: Int, lead: String = "") -> [Hit] {
        hits(matchSQL, [.text(expression), .integer(Int64(candidates)), .text(lead.isEmpty ? "" : "\(lead)%"), .integer(Int64(limit))])
    }

    /// The foods an expression matches whose brand starts as `begun` does, the most scanned
    /// first: the brands with the word "swiss" that go on with an "m".
    func match(_ expression: String, limit: Int, brandBegun begun: String) -> [Hit] {
        hits(begunSQL, [.text(expression), .integer(Int64(candidates)), .text("\(begun)%"), .integer(Int64(limit))])
    }

    private func hits(_ sql: String, _ parameters: [SQLValue]) -> [Hit] {
        var hits: [Hit] = []
        var fresh: [(Int64, Entry)] = []
        pool.read { connection in
            try connection.query(sql, parameters) { row in
                let rowid = row.int(0)
                if let entry = read.withLock({ $0[rowid] }) {
                    hits.append(Hit(entry: entry, away: row.int(10) == 1, home: row.int(11) == 1))
                } else if let food = food(row) {
                    // The traits' third bit marks a dish of several foods.
                    let entry = Entry(food, also: row.string(9) ?? "", dish: !row.isNull(8) && row.int(8) & 4 != 0)
                    fresh.append((rowid, entry))
                    hits.append(Hit(entry: entry, away: row.int(10) == 1, home: row.int(11) == 1))
                }
            }
        }
        if !fresh.isEmpty {
            read.withLock { read in
                if read.count + fresh.count > 6000 { read.removeAll(keepingCapacity: true) }
                for (rowid, entry) in fresh { read[rowid] = entry }
            }
        }
        return hits
    }

    /// How many foods an expression matches, counting no further than `cap`.
    func count(_ expression: String, cap: Int = 2000) -> Int {
        var found = 0
        pool.read { connection in
            try connection.query(
                "SELECT count(*) FROM (SELECT rowid FROM food_search WHERE food_search MATCH ? LIMIT ?)",
                [.text(expression), .integer(Int64(cap))]
            ) { row in found = Int(row.int(0)) }
        }
        return found
    }

    /// Whether some food an expression matches is one people scan, and not sold only elsewhere.
    func isScanned(_ expression: String, atLeast popularity: Double) -> Bool {
        var found = false
        pool.read { connection in
            try connection.query(scannedSQL, [.text(expression), .real(popularity)]) { _ in found = true }
        }
        return found
    }

    /// Rows of the `terms` vocabulary: each word the catalog knows and how many foods use it.
    func terms(_ sql: String, _ parameters: [SQLValue]) -> [(term: String, foods: Int)] {
        var rows: [(term: String, foods: Int)] = []
        pool.read { connection in
            try connection.query(sql, parameters) { row in
                if let term = row.string(0) { rows.append((term, Int(row.int(1)))) }
            }
        }
        return rows
    }

    /// Every food's name, for the small generic catalog: the chains it names are read from them.
    func names() -> [String] {
        guard kind == .generic else { return [] }
        var names: [String] = []
        pool.read { connection in
            try connection.query("SELECT name FROM foods") { row in
                if let name = row.string(0) { names.append(name) }
            }
        }
        return names
    }

    /// The food stored under a 14-digit barcode key.
    func food(barcode key: String) -> Food? {
        let value: SQLValue = barcodeIsInteger ? .integer(Int64(key) ?? -1) : .text(key)
        return first("SELECT \(columns) FROM foods WHERE barcode = ? LIMIT 1", [value])
    }

    /// The food with a stored id.
    func food(id: String) -> Food? {
        guard kind == .generic, let rowids = rowidsByID() else { return first("SELECT \(columns) FROM foods WHERE id = ? LIMIT 1", [.text(id)]) }
        guard let rowid = rowids[id] else { return nil }
        return first("SELECT \(columns) FROM foods WHERE rowid = ?", [.integer(rowid)])
    }

    /// Every stored id's rowid, the first row's where two share one, as `WHERE id = ?` finds it.
    /// Nil when the file can't be read, so lookups fall back to the scan rather than find nothing.
    private func rowidsByID() -> [String: Int64]? {
        rowids.withLock { cached in
            if let cached { return cached }
            var found: [String: Int64] = [:]
            do {
                try pool.with { connection in
                    try connection.query("SELECT id, rowid FROM foods WHERE id IS NOT NULL ORDER BY rowid") { row in
                        if let id = row.string(0), found[id] == nil { found[id] = row.int(1) }
                    }
                }
            } catch {
                catalogLog.error("\(self.pool.url.lastPathComponent, privacy: .public) ids: \(String(describing: error), privacy: .public)")
                return nil
            }
            cached = found
            return found
        }
    }

    /// Reads that failed since the catalog opened.
    var failures: Int { pool.failures.load(ordering: .relaxed) }

    /// Forgets rows already read and closes spare connections; see `FoodCatalog.releaseMemory`.
    func releaseMemory() {
        read.withLock { $0.removeAll() }
        pool.trim()
    }

    private func first(_ sql: String, _ parameters: [SQLValue]) -> Food? {
        var found: Food?
        pool.read { connection in
            try connection.query(sql, parameters) { row in found = found ?? food(row) }
        }
        return found
    }
}
